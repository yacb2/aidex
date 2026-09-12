#!/usr/bin/env bash
# Run the native `claude plugin eval` suite over the aidex skills.
#
#   ./tests/native-eval/run-eval.sh                  # iterate: 1 run, both arms
#   ./tests/native-eval/run-eval.sh --verdict         # decide: 3 runs, both arms
#   ./tests/native-eval/run-eval.sh --case 'decision*'
#   ./tests/native-eval/run-eval.sh --only artifact   # every case of one skill
#
# --only <skill> is sugar for --case '<skill>--*'. build-wrapper.sh names each
# collected case `<skill>--<case>` from its FOLDER, so the DOUBLE dash is what
# keeps --only plan from also selecting plan-exec cases. Use --case for anything
# narrower.
#
# Pinned by policy, not by taste:
#   --no-publish   the HTML report must stay local (artifacts-local-first, gate 3)
#   --trust-plugin no TTY for the first-run trust prompt. This IS a trust bypass,
#                  so the runner is written so it cannot be aimed anywhere else:
#                  the target is always `.` inside $REPO/_tmp/evalkit, which
#                  build-wrapper.sh deletes and rebuilds on every invocation from
#                  this repo's own skills/ and skills/*/evals/native/. The trust
#                  boundary is therefore "code committed to this repo" — review a
#                  case's setup.sh in the diff like any other executable, because
#                  --scaffold runs it as you.
#   --scaffold     cases need their fixture tree; without it they run bare
#   --allow-tools  Write Edit ONLY. Granting Bash aborts every run on a machine
#                  whose ~/.docker holds symlinks (Docker Desktop) — the eval
#                  sandbox refuses rather than risk exposing the credential
#                  store. RED->GREEN proof therefore belongs in CI, not here.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL="${EVAL_MODEL:-claude-sonnet-5}"
JUDGE="${EVAL_JUDGE_MODEL:-haiku}"
MIN_DELTA="${EVAL_MIN_DELTA:-0.30}"
MAX_COST="${EVAL_MAX_COST:-8}"
RUNS=1
CASE_GLOB='*'

KEEP_TEMP=()
[ "${EVAL_KEEP_TEMP:-}" = "1" ] && KEEP_TEMP=(--keep-temp)

while [ $# -gt 0 ]; do
  case "$1" in
    --verdict) RUNS=3; shift ;;
    --case)    CASE_GLOB="$2"; shift 2 ;;
    --only)    CASE_GLOB="$2--*"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

"$REPO/tests/native-eval/build-wrapper.sh"

OUT="$REPO/_tmp/native-eval-$(date +%Y-%m-%dT%H-%M-%S).json"
cd "$REPO/_tmp/evalkit"
# `claude plugin eval` exits 1 whenever any case scores below --threshold
# (default 1.0). That is an expected outcome here, not a runner failure: the
# verdict is the delta assertion below. Capture the status instead of letting
# `set -e` abort before the summary is printed.
set +e
claude plugin eval . \
  --eval-dir plugin-evals \
  --case "$CASE_GLOB" \
  --runs "$RUNS" \
  --ablation with-without \
  --scaffold \
  --allow-tools Write Edit \
  --model "$MODEL" \
  --judge-model "$JUDGE" \
  --max-cost-usd "$MAX_COST" \
  --no-publish \
  --trust-plugin \
  ${KEEP_TEMP[@]+"${KEEP_TEMP[@]}"} \
  --json "$OUT"
eval_status=$?
set -e
[ -s "$OUT" ] || { echo "eval produced no JSON (exit $eval_status)" >&2; exit "$eval_status"; }

# `--threshold` gates the with-arm score only; there is no delta flag. The
# verdict this suite cares about IS the delta, so assert it here.
MIN_DELTA="$MIN_DELTA" RUNS="$RUNS" python3 - "$OUT" <<'PY'
import json, os, sys

d = json.load(open(sys.argv[1]))
min_delta = float(os.environ["MIN_DELTA"])
runs = int(os.environ["RUNS"])
print(f"\nruns/case: {runs}   reference cost: USD {d['costUsd']:.3f}   {d['durationSeconds']}s")
print(f"{'case':38} {'with':>6} {'without':>8} {'delta':>7}  verdict")
if not d["cases"]:
    print("\nERROR: the run selected ZERO cases — a green result here means nothing.")
    print("--case matches the `name:` in case.yaml, not the folder name.")
    sys.exit(1)
failed = []
for c in d["cases"]:
    a = c["aggregates"]
    ok = a["delta"] >= min_delta
    print(f"{c['name']:38} {a['score']:6.2f} {a['scoreWithout']:8.2f} {a['delta']:7.2f}  {'ok' if ok else 'BELOW'}")
    runs_with = c["arms"]["with"]
    indicators = {g["name"] for r in runs_with for g in r["graders"] if not g["scored"]}
    for name in sorted(indicators):
        fired = sum(
            1 for r in runs_with
            for g in r["graders"]
            if g["name"] == name and not g["scored"] and g["passed"]
        )
        print(f"    indicator {name}: fired {fired}/{len(runs_with)}")
    # A run that hit its budget carries `error` and its last message is a
    # mid-task sentence: the llm point it lost says nothing about the skill.
    for arm in ("with", "without"):
        for i, r in enumerate(c["arms"][arm]):
            if r.get("error"):
                print(f"    {arm} run {i}: {r['error']} ({r['turns']} turns) -- score invalid")
    if not ok:
        failed.append(c["name"])
if runs < 3:
    print("\nNOTE: 1 run per arm is for grader iteration. Use --verdict before deciding anything.")
if failed:
    print(f"\ndelta below {min_delta}: {', '.join(failed)}")
    sys.exit(1)
PY
