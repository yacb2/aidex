#!/usr/bin/env bash
# noise-summary.sh flags each case from its per-run `passed` across both arms:
# no-headroom = passed every run in every arm, suspect = failed every run in
# every arm, else ok. Layer: shell, the script is the boundary. Fixture follows
# the run-eval.sh result shape (cases[].arms.{with,without}[].passed).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/noise-summary.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; echo "  want: $3"; echo "  got:  $2"; fi; }

python3 - "$T/r.json" <<'PY'
import json, sys
def arm(*p): return [{"passed": x, "graders": []} for x in p]
cases = [
  {"name": "easy",  "arms": {"with": arm(True, True, True),    "without": arm(True, True, True)}},
  {"name": "dead",  "arms": {"with": arm(False, False, False), "without": arm(False, False, False)}},
  {"name": "mixed", "arms": {"with": arm(True, True, False),    "without": arm(False, False, False)}},
  {"name": "works", "arms": {"with": arm(True, True, True),     "without": arm(False, False, False)}},
]
json.dump({"cases": cases}, open(sys.argv[1], "w"))
PY
want=$'easy\twith\t3/3\tno-headroom\neasy\twithout\t3/3\tno-headroom\ndead\twith\t0/3\tsuspect\ndead\twithout\t0/3\tsuspect\nmixed\twith\t2/3\tok\nmixed\twithout\t0/3\tok\nworks\twith\t3/3\tok\nworks\twithout\t0/3\tok'
check "rows and flags" "$(bash "$S" "$T/r.json" 2>&1)" "$want"

# Invalid runs (error set, or judge skipped at the cost ceiling, as run-eval.sh
# marks them) are shown, not counted; flags need every arm to have valid runs.
cat > "$T/edge.json" <<'J'
{"cases": [
 {"name": "errored", "arms": {"with": [{"passed": false, "error": "max turns", "graders": []},
                                       {"passed": false, "error": "max turns", "graders": []},
                                       {"passed": false, "error": "max turns", "graders": []}],
                              "without": [{"passed": false, "graders": []},{"passed": false, "graders": []},{"passed": false, "graders": []}]}},
 {"name": "ceiling", "arms": {"with": [{"passed": false, "graders": [{"explanation": "skipped: cost ceiling"}]}],
                               "without": [{"passed": true, "graders": []}]}},
 {"name": "zerorun", "arms": {"with": [{"passed": true, "graders": []},{"passed": true, "graders": []},{"passed": true, "graders": []}], "without": []}},
 {"name": "single", "arms": {"with": [{"passed": true, "graders": []},{"passed": true, "graders": []}]}},
 {"name": "noarms", "arms": {}},
 {"name": "bothempty", "arms": {"with": [], "without": []}}
]}
J
want=$'errored\twith\t0/0 (3 invalid)\tok\nerrored\twithout\t0/3\tok\nceiling\twith\t0/0 (1 invalid)\tok\nceiling\twithout\t1/1\tok\nzerorun\twith\t3/3\tok\nzerorun\twithout\t0/0\tok\nsingle\twith\t2/2\tok\nnoarms\t-\t0/0\tinvalid\nbothempty\twith\t0/0\tinvalid\nbothempty\twithout\t0/0\tinvalid'
check "invalid runs and vacuous arms" "$(bash "$S" "$T/edge.json" 2>&1)" "$want"
cat > "$T/allinv.json" <<'J'
{"cases": [{"name": "dead", "arms": {"with": [{"passed": false, "error": "x", "graders": []}], "without": [{"passed": false, "error": "x", "graders": []}]}}]}
J
check "all runs invalid is invalid, not suspect" "$(bash "$S" "$T/allinv.json" 2>&1)" $'dead\twith\t0/0 (1 invalid)\tinvalid\ndead\twithout\t0/0 (1 invalid)\tinvalid'
echo '{"cases": [{"name": "n", "arms": {"with": [{"passed": 1, "graders": []}]}}]}' > "$T/int.json"
out="$(bash "$S" "$T/int.json" 2>&1)"; rc=$?
check "non-boolean passed exits non-zero" "$([ $rc -ne 0 ] && echo yes)" "yes"
check "non-boolean passed is one line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"

echo '{"cases": []}' > "$T/empty.json"
out="$(bash "$S" "$T/empty.json" 2>&1)"; rc=$?
check "empty exits non-zero" "$([ $rc -ne 0 ] && echo yes)" "yes"
check "empty is one line" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"

echo 'not json' > "$T/bad.json"
out="$(bash "$S" "$T/bad.json" 2>&1)"; rc=$?
check "malformed exits non-zero" "$([ $rc -ne 0 ] && echo yes)" "yes"
check "malformed is one line, no traceback" "$(printf '%s\n' "$out" | grep -c -e Traceback -e '^  File')$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "01"

echo "noise-summary: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
