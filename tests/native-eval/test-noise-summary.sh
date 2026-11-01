#!/usr/bin/env bash
# noise-summary.sh flags each case from its per-run `passed` across both arms:
# no-headroom = passed every run in every arm, suspect = failed every run in
# every arm, else ok. Also tests run-eval.sh (stub claude, scratch repo) for gate
# honesty and the sidecar. Layer: shell, the scripts are the boundary. Fixture follows
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
want=$'easy\twith\t3/3\tno-headroom\t0/0\neasy\twithout\t3/3\tno-headroom\t0/0\ndead\twith\t0/3\tsuspect\t0/0\ndead\twithout\t0/3\tsuspect\t0/0\nmixed\twith\t2/3\tok\t0/0\nmixed\twithout\t0/3\tok\t0/0\nworks\twith\t3/3\tok\t0/0\nworks\twithout\t0/3\tok\t0/0'
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
want=$'errored\twith\t0/0 (3 invalid)\tok\t0/0\nerrored\twithout\t0/3\tok\t0/0\nceiling\twith\t0/0 (1 invalid)\tok\t0/0\nceiling\twithout\t1/1\tok\t0/0\nzerorun\twith\t3/3\tok\t0/0\nzerorun\twithout\t0/0\tok\t0/0\nsingle\twith\t2/2\tok\t0/0\nnoarms\t-\t0/0\tinvalid\t0/0\nbothempty\twith\t0/0\tinvalid\t0/0\nbothempty\twithout\t0/0\tinvalid\t0/0'
check "invalid runs and vacuous arms" "$(bash "$S" "$T/edge.json" 2>&1)" "$want"
cat > "$T/allinv.json" <<'J'
{"cases": [{"name": "dead", "arms": {"with": [{"passed": false, "error": "x", "graders": []}], "without": [{"passed": false, "error": "x", "graders": []}]}}]}
J
check "all runs invalid is invalid, not suspect" "$(bash "$S" "$T/allinv.json" 2>&1)" $'dead\twith\t0/0 (1 invalid)\tinvalid\t0/0\ndead\twithout\t0/0 (1 invalid)\tinvalid\t0/0'
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

# ---- disagreement column (task 2.3) ------------------------------------------
# Last column = llm-passed-while-mechanical-failed / llm-failed-while-mechanical-
# passed, in runs. "Mechanical" = scored regex and file_exists graders only (the
# llm grader judges content, they judge mechanics); tool_used and unscored
# indicators never count; invalid runs are excluded.
python3 - "$T/dis.json" <<'PYD'
import json, sys
def g(name, passed, scored=True): return {"name": name, "passed": passed, "scored": scored}
def run(passed, *gs, **kw): return dict({"passed": passed, "graders": list(gs)}, **kw)
spec = [{"name": "l", "type": "llm"}, {"name": "r", "type": "regex"},
        {"name": "f", "type": "file_exists"}, {"name": "t", "type": "tool_used"}]
case = {"name": "dis", "graders": spec, "arms": {
  "with": [
    run(False, g("l", True),  g("r", False), g("f", True)),    # llm pass, regex fail  -> A
    run(False, g("l", False), g("r", True),  g("f", True)),    # llm fail, mech pass   -> B
    run(True,  g("l", True),  g("r", True),  g("f", True)),    # agree
    run(False, g("l", False), g("r", False), g("f", False)),   # agree
    run(False, g("l", True),  g("r", True),  g("f", False)),   # llm pass, file fail   -> A
    run(False, g("l", False), g("r", True),  g("f", False)),   # llm fail, mech mixed  -> neither
    run(False, g("l", True),  g("r", False), error="timed out after 900s"),  # invalid, excluded
  ],
  "without": [
    run(False, g("l", True),  g("t", False)),                  # tool_used is not mechanical
    run(False, g("l", True),  g("r", False, scored=False)),    # unscored indicator does not count
  ]}}
nomech = {"name": "nomech", "graders": spec[:1], "arms": {"with": [run(True, g("l", True)), run(False, g("l", False))]}}
json.dump({"cases": [case, nomech]}, open(sys.argv[1], "w"))
PYD
cat > "$T/skip.json" <<'J'
{"cases": [{"name": "sk", "graders": [{"name": "l", "type": "llm"}, {"name": "r", "type": "regex"}],
  "arms": {"with": [{"passed": false, "error": null, "skippedPaidGraders": true,
                      "graders": [{"name": "l", "passed": false, "scored": true}, {"name": "r", "passed": true, "scored": true}]}]}}]}
J
check "skippedPaidGraders run is invalid and outside A/B" "$(bash "$S" "$T/skip.json" 2>&1)" $'sk\twith\t0/0 (1 invalid)\tinvalid\t0/0'
# Rule: a run's llm verdict is "passed" only if EVERY scored llm grader passed.
cat > "$T/twollm.json" <<'J'
{"cases": [{"name": "two", "graders": [{"name": "l1", "type": "llm"}, {"name": "l2", "type": "llm"}, {"name": "r", "type": "regex"}],
  "arms": {"with": [{"passed": false, "graders": [{"name": "l1", "passed": true, "scored": true}, {"name": "l2", "passed": false, "scored": true}, {"name": "r", "passed": true, "scored": true}]},
                    {"passed": false, "graders": [{"name": "l1", "passed": true, "scored": true}, {"name": "l2", "passed": false, "scored": true}, {"name": "r", "passed": false, "scored": true}]}]}}]}
J
check "two llm graders: llm passes only if all pass" "$(bash "$S" "$T/twollm.json" 2>&1)" $'two\twith\t0/2\tok\t0/1'
python3 -c "
import json,sys
d=json.load(open('$T/dis.json')); d['partial']=True; json.dump(d,open('$T/part.json','w'))"
check "partial result marks every row" "$(bash "$S" "$T/part.json" 2>&1 | cut -f4 | sort -u)" "partial"
check "partial keeps the disagreement column" "$(bash "$S" "$T/part.json" 2>&1 | cut -f5 | sed -n 1p)" "2/1"
check "disagreement column" "$(bash "$S" "$T/dis.json" 2>&1)" $'dis\twith\t1/6 (1 invalid)\tok\t2/1\ndis\twithout\t0/2\tok\t0/0\nnomech\twith\t1/2\tok\t0/0'

# ---- run-eval.sh gate honesty (task 2.1) -------------------------------------
# An invalid run (timeout, cost ceiling, skipped judges, partial result, eval
# exit 2) must be INVALID, listed under FAILED, and make run-eval.sh exit
# non-zero. Layer: shell, run-eval.sh is the boundary; a stub `claude` replaces
# the paid eval and a scratch repo replaces $REPO so nothing real is touched.
R="$T/repo"; mkdir -p "$R/tests/native-eval" "$R/bin"
cp "$HERE/run-eval.sh" "$R/tests/native-eval/run-eval.sh"
printf '#!/usr/bin/env bash\necho "cases:     1"\n' > "$R/tests/native-eval/collect-cases.sh"
cat > "$R/bin/claude" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then echo "9.9.9 (Claude Code)"; exit 0; fi
printf '%s\n' "$*" > "$STUB_ARGS"
while [ $# -gt 0 ]; do [ "$1" = "--json" ] && out="$2"; shift; done
[ -f "$STUB_JSON" ] && cp "$STUB_JSON" "$out"; exit "${STUB_STATUS:-0}"
STUB
chmod +x "$R/bin/claude" "$R/tests/native-eval/"*.sh
printf '_tmp/\n' > "$R/.gitignore"   # as in the real repo: result files must not read as dirt
(cd "$R" && git init -q && git add -A && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init)
python3 - "$T" <<'PYF'
import json, sys
t = sys.argv[1]
def run(**kw):
    r = {"passed": True, "turns": 3, "error": None, "skippedPaidGraders": False,
         "graders": [{"name": "g", "scored": True, "passed": True, "explanation": "ok"}]}
    r.update(kw); return r
def doc(with_run, partial=False):
    return {"costUsd": 1.0, "durationSeconds": 5, "partial": partial, "claudeVersion": "9.9.9",
            "cases": [{"name": "c1", "dir": "none",
                       "aggregates": {"score": 1.0, "scoreWithout": 0.0, "delta": 1.0},
                       "arms": {"with": [with_run], "without": [run(passed=False)]}}]}
docs = {
  "valid": doc(run()),
  "timeout": doc(run(passed=False, error="timed out after 900s")),
  "ceiling": doc(run(graders=[{"name": "g", "scored": True, "passed": False, "explanation": "skipped: cost ceiling"}])),
  "skipped": doc(run(skippedPaidGraders=True)),
  "partial": doc(run(), partial=True),
  "emptyerr": doc(run(error="")),
}
mixed = doc(run())
mixed["cases"][0]["arms"]["without"] = [run(passed=False), run(passed=False, error="timed out after 900s")]
docs["mixed"] = mixed
for k, v in docs.items(): json.dump(v, open(f"{t}/eval-{k}.json", "w"))
PYF
runeval() { # runeval <fixture> <stub-status> -> output in $RE_OUT, status in $RE_RC
  rm -rf "$R/_tmp"
  RE_OUT="$(cd "$R" && env -u EVAL_MODEL -u EVAL_JUDGE_MODEL -u EVAL_MIN_DELTA -u EVAL_BASH PATH="$R/bin:$PATH" STUB_JSON="$T/eval-$1.json" STUB_STATUS="$2" STUB_ARGS="$T/args.txt" \
    bash tests/native-eval/run-eval.sh 2>&1)"; RE_RC=$?
}
runeval valid 0
check "valid result exits 0" "$RE_RC" "0"
check "valid result is not INVALID" "$(printf '%s\n' "$RE_OUT" | grep -c INVALID)" "0"
for k in timeout ceiling skipped; do
  runeval $k 0
  check "$k run exits non-zero" "$([ $RE_RC -ne 0 ] && echo yes)" "yes"
  check "$k run is INVALID" "$(printf '%s\n' "$RE_OUT" | grep -c '^    INVALID:')" "1"
  check "$k run is listed under FAILED" "$(printf '%s\n' "$RE_OUT" | grep -c '^FAILED: c1')" "1"
done
runeval valid 1
check "claude exit 1 (a case below threshold) with a clean result exits 0" "$RE_RC" "0"
check "claude exit 1 is not INVALID" "$(printf '%s\n' "$RE_OUT" | grep -c INVALID)" "0"
runeval emptyerr 0
check "error empty string reads as valid" "$RE_RC" "0"
runeval mixed 0
check "one timed-out run in the without arm exits non-zero" "$([ $RE_RC -ne 0 ] && echo yes)" "yes"
check "mixed: INVALID: 1 run" "$(printf '%s\n' "$RE_OUT" | grep -c '^    INVALID: 1 run')" "1"
check "mixed: FAILED names the case" "$(printf '%s\n' "$RE_OUT" | grep -c '^FAILED: c1 (INVALID)')" "1"
runeval nojson 0
check "exit 0 with no JSON exits non-zero" "$([ $RE_RC -ne 0 ] && echo yes)" "yes"
runeval valid 3
check "unknown claude exit code 3 exits non-zero" "$([ $RE_RC -ne 0 ] && echo yes)" "yes"
check "unknown claude exit code 3 says INVALID RUN" "$(printf '%s\n' "$RE_OUT" | grep -c '^INVALID RUN:')" "1"
runeval partial 0
check "partial result has one FAILED line" "$(printf '%s\n' "$RE_OUT" | grep -c '^FAILED:')" "1"
check "partial result exits non-zero" "$([ $RE_RC -ne 0 ] && echo yes)" "yes"
check "partial result says INVALID" "$(printf '%s\n' "$RE_OUT" | grep -c '^INVALID RUN:')" "1"
runeval valid 2
check "eval exit 2 has one FAILED line" "$(printf '%s\n' "$RE_OUT" | grep -c '^FAILED:')" "1"
check "eval exit 2 exits non-zero even with a clean JSON" "$([ $RE_RC -ne 0 ] && echo yes)" "yes"
check "eval exit 2 says INVALID" "$(printf '%s\n' "$RE_OUT" | grep -c '^INVALID RUN:')" "1"

# Sidecar: git SHA, dirty flag, claude version, model, judge (full ID, not an alias).
runeval valid 0
meta="$(ls "$R"/_tmp/native-eval-*.meta.json 2>/dev/null | sed -n 1p)"
sha="$(git -C "$R" rev-parse HEAD)"
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]))' "$meta" "$1" 2>&1; }
check "sidecar exists" "$([ -n "$meta" ] && echo yes)" "yes"
check "sidecar git_sha" "$(field git_sha)" "$sha"
check "sidecar dirty clean tree" "$(field dirty)" "False"
check "sidecar claude_version" "$(field claude_version)" "9.9.9 (Claude Code)"
check "sidecar model" "$(field model)" "claude-sonnet-5"
check "sidecar judge_model" "$(field judge_model)" "claude-haiku-5-5"
check "judge pinned in the claude call" "$(grep -c -e '--judge-model claude-haiku-5-5 ' "$T/args.txt")" "1"
echo dirty > "$R/untracked.txt"
runeval valid 0
meta="$(ls "$R"/_tmp/native-eval-*.meta.json | sed -n 1p)"
check "sidecar dirty with an untracked file" "$(field dirty)" "True"
rm "$R/untracked.txt"

echo "noise-summary: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
