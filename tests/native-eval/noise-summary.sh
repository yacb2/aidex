#!/usr/bin/env bash
# Per-case spread of a run-eval.sh result JSON (_tmp/native-eval-*.json).
#   noise-summary.sh <result.json>
# One row per case and arm: case<TAB>arm<TAB>passes/runs<TAB>flag. The flag is
# computed per case across both arms, over valid runs only (error or cost-ceiling
# runs are shown as `(n invalid)`): no-headroom = both arms have valid runs and all
# passed, suspect = all failed, invalid = no arm has a valid run, else ok.
# Fifth column `A/B`, per arm over valid runs: A = runs where the llm grader passed
# while a regex/file_exists grader failed, B = runs where it failed while every
# regex/file_exists grader passed. High A or B means the judge and the mechanics
# disagree about the same output. Needs case-level `graders` types; tool_used and
# unscored indicators never count. Without them the column reads 0/0.
set -uo pipefail
[ $# -eq 1 ] && [ -r "$1" ] || { echo "usage: noise-summary.sh <result.json> (readable file)" >&2; exit 64; }
python3 - "$1" <<'PY'
import json, sys
def invalid(r):
    # run-eval.sh's own test: a run carrying `error`, or a grader whose
    # explanation says "cost ceiling", or a run that skipped its paid judges, has
    # a score that says nothing. Keep identical to run_invalid() in run-eval.sh.
    return bool(r.get("error")) or bool(r.get("skippedPaidGraders")) or any(
        "cost ceiling" in (g.get("explanation") or "") for g in r.get("graders", []))
def disagree(runs, types):
    """(llm pass / mechanical fail, llm fail / mechanical pass) over scored graders."""
    a = b = 0
    for r in runs:
        gs = [g for g in r.get("graders", []) if g.get("scored")]
        llm = [g["passed"] for g in gs if types.get(g.get("name")) == "llm"]
        mech = [g["passed"] for g in gs if types.get(g.get("name")) in ("regex", "file_exists")]
        if not llm or not mech:
            continue
        # The llm verdict of a run is "passed" only if every scored llm grader passed.
        a += all(llm) and not all(mech)
        b += not all(llm) and all(mech)
    return f"{a}/{b}"
def fmt(valid, bad):
    return f"{sum(valid)}/{len(valid)}" + (f" ({bad} invalid)" if bad else "")
try:
    doc = json.load(open(sys.argv[1]))
    cases = doc["cases"]
    partial = bool(doc.get("partial"))
    rows = []
    for c in cases:
        arms = {}
        types = {g.get("name"): g.get("type") for g in c.get("graders", [])}
        for a, runs in c["arms"].items():
            for r in runs:
                if not isinstance(r["passed"], bool):
                    raise TypeError(f"passed is not a boolean in case {c['name']}")
            valid = [r["passed"] for r in runs if not invalid(r)]
            arms[a] = (valid, len(runs) - len(valid), disagree([r for r in runs if not invalid(r)], types))
        # A flag needs BOTH arms present with a valid run; otherwise it is vacuous.
        if not any(v for v, _, _ in arms.values()):
            flag = "invalid"
        elif all(arms.get(a, ([], 0))[0] for a in ("with", "without")):
            allruns = [p for a in ("with", "without") for p in arms[a][0]]
            flag = "no-headroom" if all(allruns) else "suspect" if not any(allruns) else "ok"
        else:
            flag = "ok"
        if not arms:
            rows.append(f"{c['name']}\t-\t0/0\t{flag}\t0/0")
        for a, (valid, bad, dis) in arms.items():
            rows.append(f"{c['name']}\t{a}\t{fmt(valid, bad)}\t{flag}\t{dis}")
except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
    sys.exit(f"noise-summary: not a run-eval result ({type(e).__name__}: {e})")
if partial:  # cases are missing or unjudged: no row of this file is a verdict
    rows = ["\t".join(f[:3] + ["partial"] + f[4:]) for f in (r.split("\t") for r in rows)]
if not rows:
    sys.exit("noise-summary: no cases or runs in the result")
print("\n".join(rows))
PY
