#!/usr/bin/env bash
# Per-case spread of a run-eval.sh result JSON (_tmp/native-eval-*.json).
#   noise-summary.sh <result.json>
# One row per case and arm: case<TAB>arm<TAB>passes/runs<TAB>flag. The flag is
# computed per case across both arms, over valid runs only (error or cost-ceiling
# runs are shown as `(n invalid)`): no-headroom = both arms have valid runs and all
# passed, suspect = all failed, invalid = no arm has a valid run, else ok.
set -uo pipefail
[ $# -eq 1 ] && [ -r "$1" ] || { echo "usage: noise-summary.sh <result.json> (readable file)" >&2; exit 64; }
python3 - "$1" <<'PY'
import json, sys
def invalid(r):
    # run-eval.sh's own test: a run carrying `error`, or a grader whose
    # explanation says "cost ceiling", has a score that says nothing.
    return bool(r.get("error")) or any(
        "cost ceiling" in (g.get("explanation") or "") for g in r.get("graders", []))
def fmt(valid, bad):
    return f"{sum(valid)}/{len(valid)}" + (f" ({bad} invalid)" if bad else "")
try:
    cases = json.load(open(sys.argv[1]))["cases"]
    rows = []
    for c in cases:
        arms = {}
        for a, runs in c["arms"].items():
            for r in runs:
                if not isinstance(r["passed"], bool):
                    raise TypeError(f"passed is not a boolean in case {c['name']}")
            valid = [r["passed"] for r in runs if not invalid(r)]
            arms[a] = (valid, len(runs) - len(valid))
        # A flag needs BOTH arms present with a valid run; otherwise it is vacuous.
        if not any(v for v, _ in arms.values()):
            flag = "invalid"
        elif all(arms.get(a, ([], 0))[0] for a in ("with", "without")):
            allruns = [p for a in ("with", "without") for p in arms[a][0]]
            flag = "no-headroom" if all(allruns) else "suspect" if not any(allruns) else "ok"
        else:
            flag = "ok"
        if not arms:
            rows.append(f"{c['name']}\t-\t0/0\t{flag}")
        for a, (valid, bad) in arms.items():
            rows.append(f"{c['name']}\t{a}\t{fmt(valid, bad)}\t{flag}")
except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
    sys.exit(f"noise-summary: not a run-eval result ({type(e).__name__}: {e})")
if not rows:
    sys.exit("noise-summary: no cases or runs in the result")
print("\n".join(rows))
PY
