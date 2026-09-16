#!/usr/bin/env bash
# Run the native `claude plugin eval` suite over the aidex skills.
#
#   ./tests/native-eval/run-eval.sh                  # iterate: 1 run, both arms
#   ./tests/native-eval/run-eval.sh --verdict         # decide: 3 runs, both arms
#   ./tests/native-eval/run-eval.sh --case 'decision*'
#   ./tests/native-eval/run-eval.sh --only artifact   # every case of one skill
#
# --only <skill> is sugar for --case '<skill>--*'. collect-cases.sh names each
# collected case `<skill>--<case>` (folder AND case.yaml `name:`, which is what
# the eval's --case glob actually matches), so the DOUBLE dash is what
# keeps --only plan from also selecting plan-exec cases. Use --case for anything
# narrower.
#
# Pinned by policy, not by taste:
#   --no-publish   the HTML report must stay local (artifacts-local-first, gate 3)
#   --trust-plugin no TTY for the first-run trust prompt. This IS a trust bypass,
#                  so the runner is written so it cannot be aimed anywhere else:
#                  the target is always `$REPO`, this repo's own root, which IS
#                  the plugin (`.claude-plugin/plugin.json`, name `aidex`) — no
#                  copy is built. The trust boundary is therefore "code committed
#                  to this repo" — review a case's setup.sh in the diff like any
#                  other executable, because --scaffold runs it as you.
#   --scaffold     cases need their fixture tree; without it they run bare
#   --allow-tools  Write Edit by default. Granting Bash aborts every run on a
#                  machine whose ~/.docker holds symlinks (Docker Desktop) — the
#                  eval sandbox refuses rather than risk exposing the credential
#                  store. EVAL_BASH=1 works around it WITHOUT touching ~/.docker:
#                  the eval runs under a throwaway HOME whose .docker is an empty
#                  plain directory, and the login reaches the child through
#                  CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token`) instead of
#                  the macOS keychain the fake HOME cannot see. Run it from your
#                  own shell with the token exported; the runner never reads it.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODEL="${EVAL_MODEL:-claude-sonnet-5}"
JUDGE="${EVAL_JUDGE_MODEL:-haiku}"
MIN_DELTA="${EVAL_MIN_DELTA:-0.30}"
MAX_COST="${EVAL_MAX_COST:-8}"
JOBS="${EVAL_JOBS:-1}"
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

"$REPO/tests/native-eval/collect-cases.sh"

mkdir -p "$REPO/_tmp"
OUT="$REPO/_tmp/native-eval-$(date +%Y-%m-%dT%H-%M-%S).json"
# The plugin under test is the repo root as it ships — skills/, hooks/hooks.json
# and .claude-plugin/plugin.json all load exactly as an installed user gets them.
cd "$REPO"
TOOLS=(Write Edit)
if [ "${EVAL_BASH:-0}" = 1 ]; then
  [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || { echo "EVAL_BASH=1 needs CLAUDE_CODE_OAUTH_TOKEN exported (claude setup-token)" >&2; exit 2; }
  FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/aidex-eval-home.XXXXXX")"
  mkdir -p "$FAKE_HOME/.docker"
  export HOME="$FAKE_HOME"
  TOOLS+=(Bash)
  echo "EVAL_BASH: HOME=$FAKE_HOME (plain .docker), tools: ${TOOLS[*]}"
fi
# `claude plugin eval` exits 1 whenever any case scores below --threshold
# (default 1.0). That is an expected outcome here, not a runner failure: the
# verdict is the delta assertion below. Capture the status instead of letting
# `set -e` abort before the summary is printed.
set +e
claude plugin eval . \
  --eval-dir plugin-evals \
  --case "$CASE_GLOB" \
  --runs "$RUNS" \
  --concurrency "$JOBS" \
  --ablation with-without \
  --scaffold \
  --allow-tools "${TOOLS[@]}" \
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
# The HTML report lands under plugin-evals/results/, which collect-cases.sh
# rm -rf's on the NEXT run — a report you did not copy out is gone (lost the
# 2026-09-12 batch-2 report that way). Keep it next to the JSON.
if [ -d "$REPO/plugin-evals/results" ]; then
  cp -R "$REPO/plugin-evals/results" "${OUT%.json}-results"
  echo "Report kept: ${OUT%.json}-results/"
fi

# `--threshold` gates the with-arm score only; there is no delta flag. The
# verdict this suite cares about IS the delta, so assert it here.
#
# Two modes, because one gate cannot judge both kinds of case. A `fired-only`
# case (tagged in its case.yaml) has a delta of ~0 BY CONSTRUCTION: its fixture
# or prompt already carries what the skill would add, so the without-arm scores
# too. Gating those on delta marked 6 of 19 correct cases as failures, which is
# how an operator learns to ignore a gate. They are asserted on the fired
# indicator instead - the property they actually measure.
MIN_DELTA="$MIN_DELTA" RUNS="$RUNS" REPO="$REPO" python3 - "$OUT" <<'PY'
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
def fired_only(case):
    """Read the collected case.yaml - cp -R carries the source tags through."""
    path = os.path.join(os.environ["REPO"], case.get("dir", ""), "case.yaml")
    try:
        with open(path) as fh:
            for line in fh:
                if line.startswith("tags:") and "fired-only" in line:
                    return True
    except OSError:
        pass
    return False

failed = []
for c in d["cases"]:
    a = c["aggregates"]
    # Past --max-cost-usd the eval skips the remaining llm judges and drops
    # scoreWithout/delta from the aggregates; the affected runs show a grader
    # explanation "skipped: cost ceiling" and their 0 is not a verdict.
    without = a.get("scoreWithout", a.get("passRateWithout", 0.0))
    delta = a.get("delta", a["score"] - without)
    runs_with = c["arms"]["with"]
    indicators = {g["name"] for r in runs_with for g in r["graders"] if not g["scored"]}
    fired_counts = {
        name: sum(
            1 for r in runs_with
            for g in r["graders"]
            if g["name"] == name and not g["scored"] and g["passed"]
        )
        for name in sorted(indicators)
    }

    if fired_only(c):
        # Assert the indicator, not the delta. No indicator at all, or one that
        # misses a run, means the skill did not engage - that IS a failure here.
        ok = bool(indicators) and all(
            n == len(runs_with) for n in fired_counts.values()
        )
        mode = "fired-only"
    else:
        ok = delta >= min_delta
        mode = "delta"
    verdict = "ok" if ok else "BELOW"
    print(f"{c['name']:38} {a['score']:6.2f} {without:8.2f} {delta:7.2f}  "
          f"{verdict:5} [{mode}]")
    for name in sorted(indicators):
        print(f"    indicator {name}: fired {fired_counts[name]}/{len(runs_with)}")
    # A run that hit its budget carries `error` and its last message is a
    # mid-task sentence: the llm point it lost says nothing about the skill.
    for arm in ("with", "without"):
        for i, r in enumerate(c["arms"].get(arm, [])):
            if r.get("error"):
                print(f"    {arm} run {i}: {r['error']} ({r['turns']} turns) -- score invalid")
            elif any("cost ceiling" in (g.get("explanation") or "") for g in r["graders"]):
                print(f"    {arm} run {i}: judge skipped at the cost ceiling -- score invalid")
    if not ok:
        failed.append(c["name"])
if runs < 3:
    print("\nNOTE: 1 run per arm is for grader iteration. Use --verdict before deciding anything.")
if failed:
    print(f"\nFAILED: {', '.join(failed)}")
    print(f"(delta cases need delta >= {min_delta}; fired-only cases need "
          f"their indicator to fire in every run)")
    sys.exit(1)
PY
