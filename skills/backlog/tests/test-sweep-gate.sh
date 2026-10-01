#!/usr/bin/env bash
# test-sweep-gate.sh — the boundary gate cannot report green for a leg that ran nothing.
#
# Case 3 is the point of the file: on 2026-08-26 a `pytest | tail` pipeline returned exit 0
# over five real failures, and a runner that bails early exits 0 having run nothing. A gate
# that passes an exit-0-prints-nothing leg is the gate we already had. The case carries an
# appearance-style mutation — the same stub made to print `12 passed` must flip the run to
# PASS — because a pass-only assertion cannot tell "detected countless" from "detected nothing".
#
# Isolated temp project; stub commands; no real suite runs.
set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
GATE="$SCRIPTS/sweep-gate.sh"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/.context" "$P/bin"
stub() {  # stub <name> <exit> <stdout>
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\nexit %s\n' "$3" "$2" > "$P/bin/$1"; chmod +x "$P/bin/$1"
}
profile() {  # profile <extra front-matter lines...>
  { echo '---'; echo 'title: Testing profile'; echo 'status: open'; echo 'created: 2026-08-27'; echo 'updated: 2026-08-27'
    for l in "$@"; do echo "$l"; done; echo '---'; } > "$P/.context/testing-profile.md"
}
run() { ( cd "${RUN_DIR:-$P}" && NO_COLOR=1 bash "$GATE" "$@" 2>"$TMP/err" ); }  # RUN_DIR: run from a subdirectory

echo "sweep-gate.sh:"

# ── 1 · every leg passes with a count → PASS, exit 0 ─────────────────────────
stub be 0 "== 1284 passed in 40.1s =="
stub fe 0 "Tests  133 passed (133)"
stub bd 0 "built in 3.2s"
stub e2 0 "  12 passed (1.2m)"
profile "backend_suite_cmd: bin/be" "frontend_suite_cmd: bin/fe" "build_cmd: bin/bd" "e2e_suite_cmd: bin/e2" "e2e_detached: false"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "1 all green exits 0" || bad "1 exit $RC: $OUT"
[[ "$OUT" == *"leg=backend exit=0 count=1284 secs="* ]] && ok "1 backend count parsed (pytest)" || bad "1 backend row: $OUT"
[[ "$OUT" == *"leg=frontend exit=0 count=133 secs="* ]] && ok "1 frontend count parsed (vitest)" || bad "1 frontend row: $OUT"
[[ "$OUT" == *"leg=build exit=0 count=- secs="* ]] && ok "1 build has no count and is not countless" || bad "1 build row: $OUT"
[[ "$OUT" == *"leg=e2e exit=0 count=12 secs="* ]] && ok "1 e2e count parsed (playwright)" || bad "1 e2e row: $OUT"
[[ "$OUT" == *"verdict=PASS legs=4 failed=0"* ]] && ok "1 verdict PASS" || bad "1 verdict: $OUT"
JS="$(run --json)"
python3 -c 'import json,sys; r=json.loads(sys.argv[1]); assert r[0]["leg"]=="backend" and r[0]["count"]=="1284" and r[0]["secs"].isdigit(); assert r[-1]["verdict"]=="PASS"' "$JS" \
  && ok "1 --json emits the same rows" || bad "1 --json: $JS"
[[ "$(grep -c . "$P/.context/proofs/sweep-gate/gate-history.jsonl")" == "2" ]] && ok "1 every run appends one line to gate-history.jsonl" || bad "1 history: $(cat "$P/.context/proofs/sweep-gate/gate-history.jsonl")"

# ── 2 · one leg exits non-zero → FAIL, non-zero; the raw code, not a pipeline's ──
stub fe 3 "Tests  130 passed | 3 failed"
OUT="$(run)"; RC=$?
[[ $RC -ne 0 ]] && ok "2 a failing leg fails the gate" || bad "2 exited 0 over a failing leg"
[[ "$OUT" == *"leg=frontend exit=3 count=130 secs="* ]] && ok "2 raw exit code reported (3, not 0 from a tail)" || bad "2 frontend row: $OUT"
[[ "$OUT" == *"verdict=FAIL legs=4 failed=1"* ]] && ok "2 verdict FAIL" || bad "2 verdict: $OUT"

# ── 3 · exit 0 and prints NOTHING → count=? and FAIL (the 08-26 incident) ───────
stub fe 0 ""
OUT="$(run)"; RC=$?
[[ $RC -ne 0 ]] && ok "3 exit-0-prints-nothing is not green" || bad "3 a countless leg passed the gate"
[[ "$OUT" == *"leg=frontend exit=0 count=? secs="* ]] && ok "3 countless leg reported count=?" || bad "3 frontend row: $OUT"
[[ "$OUT" == *"verdict=FAIL"* ]] && ok "3 verdict FAIL on countless" || bad "3 verdict: $OUT"
stub fe 0 "Tests  0 passed (0)"
OUT="$(run)"; RC=$?
[[ $RC -ne 0 && "$OUT" == *"leg=frontend exit=0 count=? secs="* ]] && ok "3 '0 passed' is countless too (ran nothing, politely)" || bad "3 zero count passed: $OUT"
# the mutation: the same stub made to print a count flips the SAME run to PASS
stub fe 0 "12 passed"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"verdict=PASS"* ]] && ok "3 mutation: printing '12 passed' flips the run to PASS (detected countless, not nothing)" \
  || bad "3 mutation did not flip to PASS: $OUT"

# ── 4 · a missing profile key → exit 2 naming the key, nothing runs ─────────────
profile "backend_suite_cmd: bin/be" "frontend_suite_cmd: bin/fe" "e2e_suite_cmd: bin/e2"
: > "$P/ran"; printf '#!/usr/bin/env bash\necho ran >> %q\necho "1 passed"\n' "$P/ran" > "$P/bin/be"; chmod +x "$P/bin/be"
OUT="$(run)"; RC=$?
[[ $RC -eq 2 ]] && ok "4 missing key exits 2" || bad "4 exit $RC"
grep -q 'build_cmd' "$TMP/err" && ok "4 names the missing key (build_cmd)" || bad "4 did not name the key: $(cat "$TMP/err")"
[[ ! -s "$P/ran" ]] && ok "4 no leg ran before the refusal" || bad "4 a leg ran with the gate unbound"
# --only limits the binding check to the legs that run
OUT="$(run --only backend)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"verdict=PASS legs=1"* ]] && ok "4 --only backend runs with build_cmd unbound" || bad "4 --only: rc=$RC $OUT"

# ── 5 · detached e2e is printed, not run; PENDING until --from-log scores it ────
stub e2 0 "should not run inline"
profile "backend_suite_cmd: bin/be" "frontend_suite_cmd: bin/fe" "build_cmd: bin/bd" "e2e_suite_cmd: bin/e2" "e2e_detached: true"
OUT="$(run)"; RC=$?
[[ $RC -eq 3 ]] && ok "5 detached leg leaves the verdict PENDING (exit 3), never PASS" || bad "5 exit $RC: $OUT"
[[ "$OUT" == *"leg=e2e exit=pending count=- secs=-"* && "$OUT" == *"verdict=PENDING"* ]] && ok "5 pending row + verdict" || bad "5 rows: $OUT"
grep -q 'run_in_background' "$TMP/err" && grep -q 'sweep-gate-exit' "$TMP/err" && ok "5 prints the detached invocation with the exit marker" || bad "5 invocation: $(cat "$TMP/err")"
grep -q 'should not run inline' "$P/_tmp/sweep-gate/e2e.log" 2>/dev/null && bad "5 the detached leg ran inline" || ok "5 the detached leg did not run inline"
[[ ! -s "$P/_tmp/sweep-gate/e2e.log" ]] && ok "5 the detached log is cleared, so a stale marker cannot score" || bad "5 stale e2e.log kept"
run --only >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "5 --only with no leg is a usage error, not an unbound-variable crash" || bad "5 --only bare"
printf '  7 passed (2.0m)\nsweep-gate-exit=0\n' > "$TMP/e2e.log"
OUT="$(run --only e2e --from-log "$TMP/e2e.log")"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=e2e exit=0 count=7 secs=-"* ]] && ok "5 --from-log scores the detached log" || bad "5 from-log: rc=$RC $OUT"
printf '  7 passed (2.0m)\n' > "$TMP/e2e.log"
OUT="$(run --only e2e --from-log "$TMP/e2e.log")"; RC=$?
[[ $RC -eq 2 ]] && ok "5 a log with no exit marker is refused (the run has not finished)" || bad "5 unmarked log rc=$RC"

# ── 6 · a log written by hand (rerun on a quiet host) is scored with --exit; the count
#        still comes from the log, so an empty rerun cannot be passed by hand (BL-254) ──
printf '  15 passed (2.2m)\n' > "$TMP/rerun.log"
OUT="$(run --only e2e --from-log "$TMP/rerun.log" --exit 0)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=e2e exit=0 count=15"* ]] && ok "6 --exit 0 scores an unmarked rerun log from its count" || bad "6 rc=$RC $OUT"
: > "$TMP/empty.log"
OUT="$(run --only e2e --from-log "$TMP/empty.log" --exit 0)"; RC=$?
[[ $RC -eq 1 && "$OUT" == *"count=?"* ]] && ok "6 --exit 0 over a log that ran nothing still FAILs (countless)" || bad "6 empty rc=$RC $OUT"
run --only e2e --exit 0 >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "6 --exit without --from-log is a usage error" || bad "6 --exit alone accepted"
[[ -s "$P/.context/proofs/sweep-gate/gate-history.jsonl" && ! -e "$P/_tmp/sweep-gate/gate-history.jsonl" ]] \
  && ok "6 history lives under .context/proofs/, not _tmp/ (deletable without asking)" || bad "6 history location"

# ── 7 · --from-log --exit is per leg, not e2e-only: a backend rerun on a quiet host (BL-264)
printf '== 42 passed in 3.1s ==\n' > "$TMP/be-rerun.log"
OUT="$(run --only backend --from-log "$TMP/be-rerun.log" --exit 0)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=backend exit=0 count=42"* ]] && ok "7 a backend rerun log is scored the same way as e2e" || bad "7 rc=$RC $OUT"

# ── 8 · <leg>_pre_cmd (BL-265): a fresh worktree carried stale __pycache__ into the
#        first backend run and xdist workers disagreed, so run 1 came back count=?
#        and read as a flake. The gate stays free of Python knowledge; the profile
#        declares what to clear, and the gate runs it before the leg. ────────────
stub be 0 '12 passed'
printf '#!/usr/bin/env bash\ntouch %q\nexit 0\n' "$TMP/pre-ran" > "$P/bin/pre"; chmod +x "$P/bin/pre"
printf '#!/usr/bin/env bash\necho "cache could not be cleared" >&2\nexit 3\n' > "$P/bin/prefail"; chmod +x "$P/bin/prefail"

rm -f "$TMP/pre-ran"
profile "backend_suite_cmd: bin/be" "backend_pre_cmd: bin/pre"
OUT="$(run --only backend)"; RC=$?
[[ -e "$TMP/pre-ran" ]] && ok "8 a declared backend_pre_cmd runs" || bad "8 backend_pre_cmd was never run: $OUT"
[[ $RC -eq 0 && "$OUT" == *"leg=backend exit=0 count=12"* ]] \
  && ok "8 the leg still runs and is scored after the pre-command" || bad "8 rc=$RC $OUT"
grep -q 'bin/pre' "$P/_tmp/sweep-gate/backend.log" \
  && ok "8 the pre-command is in the leg's log, like the leg itself" \
  || bad "8 the pre-command left no trace in the log: $(cat "$P/_tmp/sweep-gate/backend.log" 2>/dev/null)"
grep -q '12 passed' "$P/_tmp/sweep-gate/backend.log" \
  && ok "8 the pre-command did not truncate the leg's own output" \
  || bad "8 the leg's output is missing from the log"

# absent → nothing changes. The same profile without the key must behave exactly
# as it did before this feature existed.
rm -f "$TMP/pre-ran"
profile "backend_suite_cmd: bin/be"
OUT="$(run --only backend)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=backend exit=0 count=12"* ]] \
  && ok "8 no pre_cmd declared: the leg runs unchanged" || bad "8 absent rc=$RC $OUT"
[[ ! -e "$TMP/pre-ran" ]] || bad "8 a pre-command ran with no key declaring it"

# a failing pre-command FAILS the leg. Skipping it silently would hide exactly the
# flake this exists to remove — the suite would run against the stale cache anyway.
profile "backend_suite_cmd: bin/be" "backend_pre_cmd: bin/prefail"
OUT="$(run --only backend)"; RC=$?
[[ $RC -eq 1 ]] && ok "8 a failing pre-command fails the leg" || bad "8 a failing pre-command was ignored: rc=$RC $OUT"
[[ "$OUT" == *"leg=backend exit=3"* ]] \
  && ok "8 the leg carries the pre-command's own exit code" || bad "8 pre-command exit code lost: $OUT"
grep -q 'cache could not be cleared' "$P/_tmp/sweep-gate/backend.log" \
  && ok "8 the pre-command's stderr is in the log" || bad "8 the pre-command's failure left no trace"
grep -q '12 passed' "$P/_tmp/sweep-gate/backend.log" \
  && bad "8 the leg ran anyway after its pre-command failed" \
  || ok "8 the leg does not run after its pre-command fails"

# The observable the item is written on: a leg whose FIRST run is countless because
# stale state reached the checkout. The stub stands in for the collection disagreement
# — with the cache present it prints nothing and exits 0, which is exactly what a
# pytest-xdist worker mismatch looked like. Without a pre_cmd the gate reports count=?
# and FAILs; with one that clears the cache, run 1 reports a real count.
printf '#!/usr/bin/env bash\nif [[ -e .stale-cache ]]; then exit 0; fi\nprintf "12 passed\\n"\nexit 0\n' > "$P/bin/be-cache"; chmod +x "$P/bin/be-cache"
printf '#!/usr/bin/env bash\nrm -f .stale-cache\n' > "$P/bin/clearcache"; chmod +x "$P/bin/clearcache"

touch "$P/.stale-cache"
profile "backend_suite_cmd: bin/be-cache"
OUT="$(run --only backend)"; RC=$?
[[ $RC -eq 1 && "$OUT" == *"count=?"* ]] \
  && ok "8 baseline: the stale cache makes run 1 countless (the reported flake)" \
  || bad "8 the flake was not reproduced: rc=$RC $OUT"

touch "$P/.stale-cache"
profile "backend_suite_cmd: bin/be-cache" "backend_pre_cmd: bin/clearcache"
OUT="$(run --only backend)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=backend exit=0 count=12"* ]] \
  && ok "8 with the pre_cmd declared, run 1 reports a real count" \
  || bad "8 run 1 is still countless with a pre_cmd: rc=$RC $OUT"

# a detached leg must carry it too, or the one leg that runs elsewhere is the one
# that keeps the stale cache.
profile "e2e_suite_cmd: bin/e2" "e2e_pre_cmd: bin/pre" "e2e_detached: true"
# `run` sends stderr to $TMP/err, and the detached invocation is printed there.
run --only e2e >/dev/null
grep -q 'bin/pre' "$TMP/err" \
  && ok "8 the printed detached invocation carries the pre-command" \
  || bad "8 a detached leg silently drops its pre-command: $(cat "$TMP/err")"

# the pre-command shares the leg's log, but only the LEG's output is its count (BL-559):
# a leg that printed nothing after a pre-command printing `5 passed` scored count=5 PASS.
stub pre5 0 "5 passed"; stub silent 0 ""; stub three 0 "3 passed"
profile "backend_suite_cmd: bin/silent" "backend_pre_cmd: bin/pre5"
OUT="$(run --only backend)"; RC=$?
[[ $RC -eq 1 && "$OUT" == *"leg=backend exit=0 count=? "* ]] \
  && ok "8 a silent leg after a pre-command printing '5 passed' is countless (FAIL)" || bad "8 the pre-command's count scored the leg: rc=$RC $OUT"
profile "backend_suite_cmd: bin/three" "backend_pre_cmd: bin/pre5"
OUT="$(run --only backend)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=backend exit=0 count=3 "* ]] \
  && ok "8 over-trimming guard: the leg printing '3 passed' still scores 3 (the pre-command's 5 is not it)" || bad "8 leg count: rc=$RC $OUT"
# the same through the detached path: run the printed invocation, then score its log
profile "e2e_suite_cmd: bin/silent" "e2e_pre_cmd: bin/pre5" "e2e_detached: true"
run --only e2e >/dev/null
( cd "$P" && bash -c "$(sed -n 's/^  cd /cd /p' "$TMP/err")" )
OUT="$(run --only e2e --from-log "$P/_tmp/sweep-gate/e2e.log")"; RC=$?
[[ $RC -eq 1 && "$OUT" == *"leg=e2e exit=0 count=? "* ]] \
  && ok "8 a detached silent leg after a counting pre-command is countless" || bad "8 detached pre count scored the leg: rc=$RC $OUT"
# a pre-command whose output has no trailing newline glued `5 passed` onto the marker, the
# marker was not found, and the whole log scored the leg again (review of BL-559). A leg
# that DOES count must still be found after the marker (fail-closed alone would say ?).
printf '#!/usr/bin/env bash\nprintf "5 passed"\n' > "$P/bin/pre5nl"; chmod +x "$P/bin/pre5nl"
profile "backend_suite_cmd: bin/three" "backend_pre_cmd: bin/pre5nl"
OUT="$(run --only backend)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=backend exit=0 count=3 "* ]] \
  && ok "8 a pre-command with no trailing newline cannot swallow the marker" || bad "8 newline-less pre: rc=$RC $OUT"
profile "e2e_suite_cmd: bin/three" "e2e_pre_cmd: bin/pre5nl" "e2e_detached: true"
run --only e2e >/dev/null
( cd "$P" && bash -c "$(sed -n 's/^  cd /cd /p' "$TMP/err")" )
OUT="$(run --only e2e --from-log "$P/_tmp/sweep-gate/e2e.log")"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=e2e exit=0 count=3 "* ]] \
  && ok "8 detached: a newline-less pre-command cannot swallow the marker" || bad "8 detached newline-less pre: rc=$RC $OUT"
# fail closed: a pre-bound leg's log with no marker (a command printed before the marker
# existed) is countless
profile "e2e_suite_cmd: bin/silent" "e2e_pre_cmd: bin/pre5" "e2e_detached: true"
printf '5 passed\nsweep-gate-exit=0\n' > "$TMP/nomark.log"
OUT="$(run --only e2e --from-log "$TMP/nomark.log")"; RC=$?
[[ $RC -eq 1 && "$OUT" == *"leg=e2e exit=0 count=? "* ]] \
  && ok "8 a pre-bound leg's log with no marker is countless (fail closed)" || bad "8 marker-less log scored: rc=$RC $OUT"

echo
# ── 9 · a shell-only project binds the gate without misnaming its suite ──────
# The leg vocabulary was backend|frontend|build|e2e, which has no name for a project
# whose whole test surface is one suite. aidex mapped tests/run-all.sh onto `backend`
# — a lie that happened to work because the count regex matched. `suite` is a valid
# leg but NOT in the default set, so a bare run still binds exactly four legs and no
# existing project is asked for a fifth key (BL-289).
stub sh 0 "133/133 passed"
profile "suite_cmd: bin/sh"
OUT="$(run --only suite)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=suite exit=0 count=133"* ]] \
  && ok "9 --only suite binds suite_cmd and counts" || bad "9 suite leg: rc=$RC $OUT $(cat "$TMP/err")"
[[ "$OUT" == *"verdict=PASS legs=1"* ]] && ok "9 one leg ran" || bad "9 legs: $OUT"

# countless must still FAIL on the new leg — a leg added without this is a leg that
# can report green over a runner that ran nothing, which is the whole point of the file
stub sh 0 "done."
OUT="$(run --only suite)"; RC=$?
[[ $RC -ne 0 && "$OUT" == *"count=?"* ]] \
  && ok "9 a countless suite leg FAILS like every other leg" || bad "9 countless suite: rc=$RC $OUT"

# ── 10 · the profile may be tracked, so a gitignored .context/ is not a dead end ──
# aidex gitignores .context/ by policy, so the profile it needs could never travel with
# a checkout and its own boundary gate was unrunnable. A repo-level testing-profile.md
# is the tracked fallback; .context/ still wins when both exist (BL-289).
stub sh 0 "133/133 passed"
rm -f "$P/.context/testing-profile.md"
{ echo '---'; echo 'title: Testing profile'; echo 'status: open'
  echo 'created: 2026-09-01'; echo 'updated: 2026-09-01'
  echo 'suite_cmd: bin/sh'; echo '---'; } > "$P/testing-profile.md"
OUT="$(run --only suite)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=suite exit=0 count=133"* ]] \
  && ok "10 a tracked repo-level profile binds the gate" || bad "10 tracked profile: rc=$RC $OUT $(cat "$TMP/err")"

profile "suite_cmd: bin/nope"
OUT="$(run --only suite)" || true
[[ "$OUT" == *"count=133"* ]] || ok "10 .context/ wins when both exist"
[[ "$OUT" == *"count=133"* ]] && bad "10 the tracked file shadowed .context/"

rm -f "$P/.context/testing-profile.md" "$P/testing-profile.md"
run --only suite >/dev/null 2>&1
grep -q "testing-profile.md" "$TMP/err" && grep -q "$P/testing-profile.md" "$TMP/err" \
  && ok "10 the refusal names BOTH paths it looked in" \
  || bad "10 refusal message: $(cat "$TMP/err")"

# ── 11 · a profile that pins ONLY suite_cmd binds without --only (BL-424) ────
# The gate documents itself as reading the profile's `*_suite_cmd`/`build_cmd`, but the
# default leg set was hard-coded to backend|frontend|build|e2e, so a project whose whole
# surface is one suite had to pass `--only suite` every time or be refused for a
# `backend_suite_cmd` it will never have. A bare `suite_cmd` is the profile's whole
# answer: it binds the one leg.
stub sh 0 "133/133 passed"
profile "suite_cmd: bin/sh"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=suite exit=0 count=133"* ]] \
  && ok "11 a bare suite_cmd binds without --only" || bad "11 bare suite_cmd: rc=$RC $OUT $(cat "$TMP/err")"
[[ "$OUT" == *"verdict=PASS legs=1"* ]] && ok "11 exactly one leg ran" || bad "11 legs: $OUT"

# the mutation that keeps this honest: a profile with NO suite key of any kind must
# still be refused. An unbound gate that defaults to "nothing to run" is a green tick
# over zero suites — the same failure as a countless leg.
profile "e2e_detached: false"
OUT="$(run)"; RC=$?
[[ $RC -eq 2 ]] && ok "11 mutation: a profile with no suite key at all is still refused" \
  || bad "11 a keyless profile was not refused: rc=$RC $OUT"
[[ "$OUT" != *"verdict=PASS"* ]] && ok "11 mutation: a keyless profile never reports PASS" || bad "11 keyless PASS: $OUT"

# a leg key that is PRESENT but empty is a half-filled profile, not a suite-only one:
# the default must test the key's presence, never its value, or the placeholder is
# silently dropped and the gate goes green over one leg.
profile "backend_suite_cmd:" "suite_cmd: bin/sh"
OUT="$(run)"; RC=$?
[[ $RC -eq 2 && "$OUT" != *"verdict=PASS"* ]] && ok "11 an empty leg key is still refused, not reduced to the suite leg" \
  || bad "11 an empty backend_suite_cmd was reduced to one leg: rc=$RC $OUT"

# a profile carrying the four leg keys is untouched, even when suite_cmd is also there.
stub be 0 "== 1284 passed in 40.1s =="
stub fe 0 "Tests  133 passed (133)"
stub bd 0 "built in 3.2s"
stub e2 0 "  12 passed (1.2m)"
profile "backend_suite_cmd: bin/be" "frontend_suite_cmd: bin/fe" "build_cmd: bin/bd" \
        "e2e_suite_cmd: bin/e2" "e2e_detached: false" "suite_cmd: bin/sh"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"verdict=PASS legs=4"* && "$OUT" != *"leg=suite"* ]] \
  && ok "11 the four-leg default is unchanged when the leg keys are present" || bad "11 four-leg: rc=$RC $OUT"

# ── 12 · BL-489: the run is stamped with its work-list, so a report can claim only its own ──
stub be 0 "== 1284 passed in 40.1s =="
profile "suite_cmd: bin/be"
H="$P/.context/proofs/sweep-gate/gate-history.jsonl"
stamp() { tail -1 "$H" | python3 -c 'import json,sys; print(json.load(sys.stdin)[-1].get("worklist",""))'; }
appended() {  # appended <args...>: one gate run -> rc 0 and exactly one new history line
  local n0 n1 rc; n0="$(grep -c . "$H")"; run "$@" >/dev/null; rc=$?; n1="$(grep -c . "$H")"
  [[ $rc -eq 0 && $((n1 - n0)) -eq 1 ]] || { bad "12 run $*: rc=$rc, history lines $n0 -> $n1"; return 1; }
}
appended
[[ -z "$(stamp)" ]] && ok "12 no work-list anywhere -> no stamp (legacy shape)" || bad "12 stamped with nothing to stamp: $(tail -1 "$H")"
mkdir -p "$P/.context/worklists/_archive"
printf -- '---\nstatus: doing\n---\n' > "$P/.context/worklists/2026-09-30-only-one.md"
printf -- '---\nstatus: done\n---\n' > "$P/.context/worklists/2026-09-29-finished.md"
appended
[[ "$(stamp)" == "2026-09-30-only-one.md" ]] && ok "12 the sole running work-list is stamped by basename" || bad "12 auto stamp: [$(stamp)] $(tail -1 "$H")"
# a quoted status is valid front matter (validate-worklist.py strips the quotes)
printf -- '---\nstatus: "doing"\n---\n' > "$P/.context/worklists/2026-09-30-only-one.md"
appended
[[ "$(stamp)" == "2026-09-30-only-one.md" ]] && ok "12 a quoted status: \"doing\" is detected as running too" || bad "12 quoted status not detected: [$(stamp)]"
printf -- '---\nstatus: doing\n---\n' > "$P/.context/worklists/2026-09-30-only-one.md"
printf -- '---\nstatus: doing\n---\n' > "$P/.context/worklists/2026-09-30-second.md"
appended
[[ -z "$(stamp)" ]] && ok "12 two running work-lists -> ambiguous, no guess" || bad "12 guessed between two: [$(stamp)]"
appended --worklist .context/worklists/2026-09-30-second.md
[[ "$(stamp)" == "2026-09-30-second.md" ]] && ok "12 --worklist <path> names the work-list explicitly" || bad "12 --worklist: [$(stamp)]"
# an archived work-list sits beside its companions; `<wl>-report.spec.md` sorts before `<wl>.md`
# and the slug must still resolve to the work-list (F1: it resolved to the spec)
A="$P/.context/worklists/_archive"
printf -- '---\nstatus: done\n---\n' > "$A/2026-09-29-third.md"
printf 'report\n' > "$A/2026-09-29-third-report.md"; printf 'spec\n' > "$A/2026-09-29-third-report.spec.md"
appended --worklist third
[[ "$(stamp)" == "2026-09-29-third.md" ]] && ok "12 --worklist <slug> skips the -report.md and -report.spec.md companions" || bad "12 slug resolved to a companion: [$(stamp)]"
appended --worklist second
[[ "$(stamp)" == "2026-09-30-second.md" ]] && ok "12 --worklist <slug> resolves to the file" || bad "12 --worklist slug: [$(stamp)]"
# BL-551: a same-named file in the CWD is not the work-list; the gate's own `[[ -f ]]` took
# ./second as a path and died "not under a worklists/ directory"
printf 'not a work-list\n' > "$P/second"
appended --worklist second && [[ "$(stamp)" == "2026-09-30-second.md" ]] \
  && ok "12 --worklist <slug> with ./<slug> in the CWD stamps the work-list" || bad "12 CWD stray: [$(stamp)] $(cat "$TMP/err")"
rm -f "$P/second"
n0="$(grep -c . "$H")"; printf -- '---\nstatus: done\n---\n' > "$A/2026-09-30-second-old.md"
run --worklist second >/dev/null; RC=$?
[[ $RC -eq 0 && "$(grep -c . "$H")" -gt "$n0" ]] && ok "12 an exact slug wins over a longer work-list name containing it" || bad "12 exact slug: rc=$RC"
n0="$(grep -c . "$H")"
run --worklist econd >/dev/null; RC=$?
[[ $RC -eq 2 && "$(grep -c . "$H")" -eq "$n0" ]] && ok "12 a slug matching two work-lists exits 2 and runs nothing (never head -1)" || bad "12 ambiguous slug: rc=$RC"
rm -f "$A/2026-09-30-second-old.md"
run --worklist no-such-run >/dev/null; [[ $? -eq 2 ]] && ok "12 unknown --worklist exits 2" || bad "12 unknown --worklist accepted"
# F7: a path must be a file under a worklists/ directory, so the stamp is a plain basename
printf -- '---\nstatus: doing\n---\n' > "$P/elsewhere.md"
run --worklist "$P/elsewhere.md" >/dev/null; RC=$?
[[ $RC -eq 2 ]] && ok "12 --worklist <path> outside worklists/ exits 2" || bad "12 outside path accepted: rc=$RC"
appended --worklist "$A/2026-09-29-third.md"
[[ "$(stamp)" == "2026-09-29-third.md" ]] && ok "12 --worklist <path> under worklists/_archive/ is accepted" || bad "12 archived path: [$(stamp)]"
# a detached leg is scored by a second run; with two running work-lists that run cannot
# detect one, so the printed follow-up must carry the work-list this run was given. It is
# run as printed, from a subdirectory, through `appended` (rc 0, exactly one new record).
WLD="$P/.context/worklists"
follow() { sed -n 's/^detached: then score it: sweep-gate\.sh //p' "$TMP/err"; }
verdict() { tail -1 "$H" | python3 -c 'import json,sys; print(json.load(sys.stdin)[-1].get("verdict",""))'; }
score_follow() {  # score_follow <cell>: finish the detached log, run the printed follow-up
  FOLLOW="$(follow)"  # kept: the follow-up run rewrites $TMP/err
  [[ -n "$FOLLOW" ]] || { bad "$1 no follow-up line printed: $(cat "$TMP/err")"; return 1; }
  printf '  7 passed (2.0m)\nsweep-gate-exit=0\n' > "$P/_tmp/sweep-gate/e2e.log"
  eval "set -- $FOLLOW"; RUN_DIR="$P/bin" appended "$@"
}
profile "e2e_suite_cmd: bin/e2" "e2e_detached: true"
run --only e2e --worklist .context/worklists/2026-09-30-second.md >/dev/null
score_follow 12 && [[ "$(verdict)" == "PASS" && "$(stamp)" == "2026-09-30-second.md" ]] \
  && ok "12 the printed --from-log follow-up appends a PASS stamped with the same work-list" \
  || bad "12 follow-up [$FOLLOW]: verdict [$(verdict)] stamp [$(stamp)]"
# (A) the auto-detected sole running list is carried too, as its stem
printf -- '---\nstatus: done\n---\n' > "$WLD/2026-09-30-second.md"
run --only e2e >/dev/null
[[ "$(follow)" == *" --worklist 2026-09-30-only-one" ]] && ok "12 A the sole running work-list goes into the follow-up as its stem" \
  || bad "12 A follow-up: [$(follow)]"
# (B) no running list, no stamp -> no --worklist to carry
printf -- '---\nstatus: done\n---\n' > "$WLD/2026-09-30-only-one.md"
run --only e2e >/dev/null
[[ -n "$(follow)" && "$(follow)" != *"--worklist"* ]] && ok "12 B no running work-list -> the follow-up carries no --worklist" \
  || bad "12 B follow-up: [$(follow)]"
# (C) the list is archived between launch and scoring: the follow-up still resolves it
run --only e2e --worklist .context/worklists/2026-09-30-only-one.md >/dev/null
mv "$WLD/2026-09-30-only-one.md" "$A/"
score_follow "12 C" && [[ "$(verdict)" == "PASS" && "$(stamp)" == "2026-09-30-only-one.md" ]] \
  && ok "12 C a work-list archived before scoring still stamps the follow-up's PASS" \
  || bad "12 C follow-up [$FOLLOW]: verdict [$(verdict)] stamp [$(stamp)]"
# (D) the --worklist path check cds into the path's directory: an exported CDPATH naming another
# project, whose `notwl` is a worklists/ directory, would make a path outside worklists/ stamp the
# run. Pins BL-558's global `unset CDPATH` for this call site; it is a guard, not a regression
# test for a change of its own (it passes on the code before it was added).
Q="$TMP/qproj"; Q2="$TMP/qother"; mkdir -p "$Q/.context/worklists" "$Q/notwl" "$Q2/.context/worklists"
printf -- '---\nsuite_cmd: true\n---\n' > "$Q/.context/testing-profile.md"
printf -- '---\nstatus: doing\n---\n' > "$Q/notwl/b.md"; ln -s "$Q2/.context/worklists" "$Q2/notwl"
OUT="$(CDPATH="$Q2" RUN_DIR="$Q" run --only suite --worklist notwl/b.md)"; RC=$?
[[ $RC -eq 2 && ! -e "$Q/.context/proofs/sweep-gate/gate-history.jsonl" ]] && grep -q 'is not under a worklists/ directory' "$TMP/err" \
  && ok "12 D an exported CDPATH cannot turn a path outside worklists/ into a stamp" || bad "12 D CDPATH stamp: rc=$RC $OUT $(cat "$TMP/err")"

# ── 13 · the gate runs the suite of the checkout it is invoked in (BL-548) ─────────
#        2026-10-01: launched from a linked worktree, the gate resolved ROOT to the main
#        project (for .context/ writes, correctly) and then ran the legs there too, so a
#        merge was gated on main's suite, not the branch's. ROOT still owns the profile,
#        _tmp/ and the history; the legs run in the invoking worktree, or the gate refuses.
gcommit() { git -C "$1" -c user.email=t@t -c user.name=t commit -qam "$2"; }
G="$TMP/gproj"; mkdir -p "$G"; G="$(cd "$G" && pwd -P)"
git -C "$G" init -q -b main
printf '.context/\n_tmp/\n_wt/\n' > "$G/.gitignore"
printf 'echo "1 passed"\n' > "$G/t.sh"
git -C "$G" add -A; gcommit "$G" main
mkdir -p "$G/.context"
{ echo '---'; echo 'suite_cmd: bash t.sh'; echo 'e2e_suite_cmd: bash t.sh'; echo 'e2e_detached: true'; echo '---'; } > "$G/.context/testing-profile.md"
GW="$G/_wt/w"; git -C "$G" worktree add -q -b br "$GW" 2>/dev/null
printf 'echo "2 passed"\n' > "$GW/t.sh"; gcommit "$GW" branch-only
GS="$TMP/gsib"; git -C "$G" worktree add -q -b br2 "$GS" 2>/dev/null; GS="$(cd "$GS" && pwd -P)"
printf 'echo "3 passed"\n' > "$GS/t.sh"; gcommit "$GS" sibling-only
OUT="$(RUN_DIR="$GW" run --only suite)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=suite exit=0 count=2 "* ]] && ok "13 a worktree inside the project runs the branch's suite, not main's" || bad "13 worktree ran: rc=$RC $OUT"
IFS= read -r HDR < "$G/_tmp/sweep-gate/suite.log"
[[ "$HDR" == *"$(git -C "$GW" rev-parse HEAD)"* && "$HDR" != *"$(git -C "$G" rev-parse HEAD)"* ]] \
  && ok "13 the leg log names the branch commit it tested, not main's" || bad "13 log header: $HDR"
[[ -s "$G/.context/proofs/sweep-gate/gate-history.jsonl" && ! -e "$GW/_tmp" && ! -e "$GW/.context" ]] \
  && ok "13 _tmp/ and the history stay at the project root" || bad "13 artifacts moved into the worktree"
OUT="$(RUN_DIR="$GS" run --only suite)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"count=3 "* ]] && ok "13 a sibling worktree (the find_project_root hop) runs its own suite" || bad "13 sibling ran: rc=$RC $OUT"
OUT="$(RUN_DIR="$G" run --only suite)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"count=1 "* ]] && ok "13 the main checkout still runs its own suite" || bad "13 main ran: rc=$RC $OUT"
RUN_DIR="$GW" run --only e2e >/dev/null
grep -q "^  cd $GW " "$TMP/err" && ok "13 the printed detached invocation cds into the worktree too" || bad "13 detached cd: $(cat "$TMP/err")"
# BL-557: --from-log tied nothing to the worktree, so a hand-written log scored PASS and wrote
# a history row. A log is scored only when its header names this worktree's checkout and HEAD.
DETACHED="$(sed -n 's/^  cd /cd /p' "$TMP/err")"  # kept: the runs below rewrite $TMP/err
GH="$G/.context/proofs/sweep-gate/gate-history.jsonl"; n0="$(grep -c . "$GH")"
printf '1 passed\nsweep-gate-exit=0\n' > "$TMP/forged.log"
OUT="$(RUN_DIR="$GW" run --only e2e --from-log "$TMP/forged.log")"; RC=$?
[[ $RC -eq 2 && "$(grep -c . "$GH")" -eq "$n0" ]] && grep -q "was not written for this worktree at its HEAD" "$TMP/err" \
  && ok "13 a hand-written log with no provenance header is refused, no history row" || bad "13 forged log scored: rc=$RC $OUT $(cat "$TMP/err")"
OUT="$(RUN_DIR="$GW" run --only e2e --from-log "$TMP/forged.log" --exit 0)"; RC=$?
[[ $RC -eq 2 && "$(grep -c . "$GH")" -eq "$n0" ]] && grep -q "was not written for this worktree at its HEAD" "$TMP/err" \
  && ok "13 --exit does not waive the provenance header" || bad "13 forged --exit log scored: rc=$RC $OUT $(cat "$TMP/err")"
# a forged "commit unknown" header is refused where the gate CAN name the commit
printf '# sweep-gate: leg=e2e; run in %s; commit unknown\n1 passed\nsweep-gate-exit=0\n' "$GW" > "$TMP/cu.log"
OUT="$(RUN_DIR="$GW" run --only e2e --from-log "$TMP/cu.log")"; RC=$?
[[ $RC -eq 2 && "$(grep -c . "$GH")" -eq "$n0" ]] && grep -q "was not written for this worktree at its HEAD" "$TMP/err" \
  && ok "13 a forged commit-unknown header is refused where the commit can be named" || bad "13 forged commit-unknown scored: rc=$RC $OUT $(cat "$TMP/err")"
( cd "$GW" && bash -c "$DETACHED" )
OUT="$(RUN_DIR="$GW" run --only e2e --from-log "$G/_tmp/sweep-gate/e2e.log")"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=e2e exit=0 count=2 "* ]] \
  && ok "13 the printed detached invocation writes a header its own --from-log accepts" || bad "13 detached log refused: rc=$RC $OUT $(cat "$TMP/err")"
# a commit after the run invalidates its log: the header pins the sha, not only the checkout
printf '# moved\n' >> "$GW/t.sh"; gcommit "$GW" moved
OUT="$(RUN_DIR="$GW" run --only e2e --from-log "$G/_tmp/sweep-gate/e2e.log")"; RC=$?
[[ $RC -eq 2 ]] && grep -q "was not written for this worktree at its HEAD" "$TMP/err" \
  && ok "13 a commit after the detached run makes its log refused" || bad "13 stale-HEAD log scored: rc=$RC $OUT $(cat "$TMP/err")"
OUT="$(RUN_DIR="$GS" run --only e2e --from-log "$G/_tmp/sweep-gate/e2e.log")"; RC=$?
[[ $RC -eq 2 ]] && grep -q "was not written for this worktree at its HEAD" "$TMP/err" \
  && ok "13 another worktree's detached log is refused" || bad "13 sibling scored the branch log: rc=$RC $OUT $(cat "$TMP/err")"
RUN_DIR="$GW" run --only suite >/dev/null
OUT="$(RUN_DIR="$GW" run --only suite --from-log "$G/_tmp/sweep-gate/suite.log" --exit 0)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=suite exit=0 count=2 "* ]] \
  && ok "13 a log the gate wrote in-process for this worktree and HEAD is accepted" || bad "13 own log refused: rc=$RC $OUT $(cat "$TMP/err")"
# the header names the leg: the suite leg's log scored as e2e passed (same command, same HEAD)
OUT="$(RUN_DIR="$GW" run --only e2e --from-log "$G/_tmp/sweep-gate/suite.log" --exit 0)"; RC=$?
[[ $RC -eq 2 ]] && grep -q "was not written for this worktree at its HEAD" "$TMP/err" \
  && ok "13 another leg's log is refused" || bad "13 suite log scored as e2e: rc=$RC $OUT $(cat "$TMP/err")"
# nested: the profile lives in a workspace and reaches the repo as `cd repo`, a path the
# worktree does not have — refused loudly instead of testing main
N="$TMP/ws"; mkdir -p "$N/.context" "$N/repo"; N="$(cd "$N" && pwd -P)"
git -C "$N/repo" init -q -b main; printf 'echo "1 passed"\n' > "$N/repo/t.sh"; git -C "$N/repo" add -A; gcommit "$N/repo" main
{ echo '---'; echo 'suite_cmd: cd repo && bash t.sh'; echo '---'; } > "$N/.context/testing-profile.md"
NW="$N/_wt/w"; git -C "$N/repo" worktree add -q -b br "$NW" 2>/dev/null
OUT="$(RUN_DIR="$NW" run --only suite)"; RC=$?
[[ $RC -eq 2 ]] && grep -q "$NW" "$TMP/err" && ok "13 a worktree of a repo nested under the profile's root is refused, naming it" || bad "13 nested: rc=$RC $OUT $(cat "$TMP/err")"
[[ ! -e "$N/_tmp" && ! -e "$N/.context/proofs/sweep-gate/gate-history.jsonl" ]] \
  && ok "13 the refusal writes no log and no history" || bad "13 the refused run left _tmp/ or a history line"
OUT="$(RUN_DIR="$N/repo" run --only suite)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"count=1 "* ]] && ok "13 the nested repo's main checkout still runs through the profile's cd" || bad "13 nested main: rc=$RC $OUT"

# monorepo: the profile lives in a SUBDIRECTORY of the repo, so ROOT sits under the main
# checkout; the worktree's copy of that subdirectory is what must run (review of BL-548)
MR="$TMP/mono"; mkdir -p "$MR/pkg"; MR="$(cd "$MR" && pwd -P)"
git -C "$MR" init -q -b main; printf '.context/\n_tmp/\n_wt/\n' > "$MR/.gitignore"
printf 'echo "1 passed"\n' > "$MR/pkg/t.sh"; git -C "$MR" add -A; gcommit "$MR" main
mkdir -p "$MR/pkg/.context"; { echo '---'; echo 'suite_cmd: bash t.sh'; echo '---'; } > "$MR/pkg/.context/testing-profile.md"
MW="$MR/pkg/_wt/w"; git -C "$MR" worktree add -q -b br "$MW" 2>/dev/null
printf 'echo "2 passed"\n' > "$MW/pkg/t.sh"; gcommit "$MW" branch-only
OUT="$(RUN_DIR="$MW/pkg" run --only suite)"; RC=$?
IFS= read -r HDR < "$MR/pkg/_tmp/sweep-gate/suite.log"
[[ $RC -eq 0 && "$OUT" == *"count=2 "* && "$HDR" == *"$(git -C "$MW" rev-parse HEAD)"* ]] \
  && ok "13 a profile in a repo subdirectory runs the worktree's copy of that subdirectory" || bad "13 monorepo: rc=$RC $OUT | $HDR"
# provenance: run from a git WORKSPACE whose profile reaches an untracked nested repo by
# `cd repo &&` — the header names the repo's commit, not the workspace's
WS="$TMP/gws"; mkdir -p "$WS/repo"; WS="$(cd "$WS" && pwd -P)"
git -C "$WS" init -q -b main; printf 'repo/\n.context/\n_tmp/\n' > "$WS/.gitignore"; git -C "$WS" add -A; gcommit "$WS" ws
git -C "$WS/repo" init -q -b main; printf 'echo "1 passed"\n' > "$WS/repo/t.sh"; git -C "$WS/repo" add -A; gcommit "$WS/repo" repo
mkdir -p "$WS/.context"; { echo '---'; echo 'suite_cmd: cd repo && bash t.sh'; echo '---'; } > "$WS/.context/testing-profile.md"
OUT="$(RUN_DIR="$WS" run --only suite)"; RC=$?
IFS= read -r HDR < "$WS/_tmp/sweep-gate/suite.log"
[[ $RC -eq 0 && "$HDR" == *"$(git -C "$WS/repo" rev-parse HEAD)"* && "$HDR" != *"$(git -C "$WS" rev-parse HEAD)"* ]] \
  && ok "13 the header names the commit of the repo the leg's cd lands in" || bad "13 provenance: rc=$RC | $HDR"
# a submodule is not a linked worktree: run from inside one, the gate behaves as before
SS="$TMP/subsrc"; mkdir -p "$SS"; git -C "$SS" init -q -b main
printf 'echo "5 passed"\n' > "$SS/t.sh"; git -C "$SS" add -A; gcommit "$SS" sub
SP="$TMP/super"; mkdir -p "$SP"; SP="$(cd "$SP" && pwd -P)"; git -C "$SP" init -q -b main
printf '.context/\n_tmp/\n' > "$SP/.gitignore"; printf 'echo "1 passed"\n' > "$SP/t.sh"
git -C "$SP" -c protocol.file.allow=always submodule add -q "$SS" sub >/dev/null 2>&1
git -C "$SP" add -A; gcommit "$SP" super
mkdir -p "$SP/.context"; { echo '---'; echo 'suite_cmd: bash t.sh'; echo '---'; } > "$SP/.context/testing-profile.md"
OUT="$(RUN_DIR="$SP/sub" run --only suite)"; RC=$?
[[ -f "$SP/sub/t.sh" && $RC -eq 0 && "$OUT" == *"count=1 "* ]] \
  && ok "13 run from inside a submodule, the gate runs the project root's suite as before" || bad "13 submodule: rc=$RC $OUT $(cat "$TMP/err")"

# round 3 of the BL-548 review: every layout maps to a row, and a layout no row knows is refused
hdr() { IFS= read -r HDR < "$1/_tmp/sweep-gate/suite.log"; }
# a dirty worktree is named as such: the sha alone would claim a commit that did not run
printf 'echo "2 passed"\n# uncommitted\n' > "$GW/t.sh"
OUT="$(RUN_DIR="$GW" run --only suite)"; RC=$?; hdr "$G"
[[ $RC -eq 0 && "$HDR" == *"(dirty)"* ]] && ok "13 a dirty worktree's header says dirty" || bad "13 dirty: rc=$RC | $HDR"
printf 'echo "2 passed"\n' > "$GW/t.sh"
# a submodule INSIDE the linked worktree: climb to the superproject, which is the worktree
git -C "$GW" -c protocol.file.allow=always submodule add -q "$SS" sub >/dev/null 2>&1; gcommit "$GW" add-sub
OUT="$(RUN_DIR="$GW/sub" run --only suite)"; RC=$?
[[ -f "$GW/sub/t.sh" && $RC -eq 0 && "$OUT" == *"count=2 "* ]] && ok "13 run from a submodule inside a linked worktree, the worktree's suite runs" || bad "13 submodule in worktree: rc=$RC $OUT $(cat "$TMP/err")"
# separate-git-dir: the common dir's dirname is not the main checkout
B="$TMP/gdb"; mkdir -p "$B"; B="$(cd "$B" && pwd -P)"
git init -q -b main --separate-git-dir="$TMP/gdb.git" "$B"; printf '.context/\n_tmp/\n_wt/\n' > "$B/.gitignore"
printf 'echo "1 passed"\n' > "$B/t.sh"; git -C "$B" add -A; gcommit "$B" main
mkdir -p "$B/.context"; { echo '---'; echo 'suite_cmd: bash t.sh'; echo '---'; } > "$B/.context/testing-profile.md"
BW="$B/_wt/w"; git -C "$B" worktree add -q -b br "$BW" 2>/dev/null
printf 'echo "2 passed"\n' > "$BW/t.sh"; gcommit "$BW" branch-only
OUT="$(RUN_DIR="$BW" run --only suite)"; RC=$?; HDR=""; [[ -f "$B/_tmp/sweep-gate/suite.log" ]] && hdr "$B"
[[ $RC -eq 0 && "$OUT" == *"count=2 "* && "$HDR" != *"$(git -C "$B" rev-parse HEAD)"* ]] \
  && ok "13 a worktree of a separate-git-dir repo runs the branch's suite" || bad "13 separate-git-dir: rc=$RC $OUT | $HDR $(cat "$TMP/err")"
# separate-git-dir kept inside the main checkout, worktree a sibling (reached by the hop)
A="$TMP/agd"; mkdir -p "$A"; A="$(cd "$A" && pwd -P)"
git init -q -b main --separate-git-dir="$A/.gd" "$A"; printf '.gd/\n.context/\n_tmp/\n' > "$A/.gitignore"
printf 'echo "1 passed"\n' > "$A/t.sh"; git -C "$A" add -A; gcommit "$A" main
mkdir -p "$A/.context"; { echo '---'; echo 'suite_cmd: bash t.sh'; echo '---'; } > "$A/.context/testing-profile.md"
AW="$TMP/agd-sib"; git -C "$A" worktree add -q -b br "$AW" 2>/dev/null
printf 'echo "2 passed"\n' > "$AW/t.sh"; gcommit "$AW" branch-only
OUT="$(RUN_DIR="$AW" run --only suite)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"count=2 "* ]] && ok "13 a sibling worktree of a separate-git-dir repo runs the branch's suite" || bad "13 A-gd: rc=$RC $OUT $(cat "$TMP/err")"
# worktree.sh DEST: the profile's root mirrors the workspace and holds the worktree as `repo`
R="$TMP/rmain"; mkdir -p "$R"; git -C "$R" init -q -b main
printf 'echo "1 passed"\n' > "$R/t.sh"; git -C "$R" add -A; gcommit "$R" main
D="$TMP/dest"; mkdir -p "$D/.context"; D="$(cd "$D" && pwd -P)"
{ echo '---'; echo 'suite_cmd: cd repo && bash t.sh'; echo '---'; } > "$D/.context/testing-profile.md"
git -C "$R" worktree add -q -b br "$D/repo" 2>/dev/null
printf 'echo "2 passed"\n' > "$D/repo/t.sh"; gcommit "$D/repo" branch-only
OUT="$(RUN_DIR="$D/repo" run --only suite)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"count=2 "* ]] && ok "13 a worktree.sh DEST runs its worktree through the profile's cd" || bad "13 DEST: rc=$RC $OUT $(cat "$TMP/err")"

# round 4: no layout table can be complete, so the verdict is one invariant — from a linked
# worktree, every leg must land in a checkout inside that worktree. Each layout below
# passed the table and ran main; each must now be refused with nothing written.
refused() {  # refused <label> <W> <run dir> <gate args...>
  local label="$1" w="$2" d="$3"; shift 3
  OUT="$(RUN_DIR="$d" run "$@")"; RC=$?
  [[ $RC -eq 2 && ! -e "$w/_tmp" && ! -e "$w/.context/proofs/sweep-gate/gate-history.jsonl" ]] \
    && ok "13 $label is refused, nothing written" || bad "13 $label: rc=$RC $OUT $(cat "$TMP/err")"
}
wprofile() {  # wprofile <W> <front-matter lines...>
  local w="$1"; shift; mkdir -p "$w/.context"
  { echo '---'; for l in "$@"; do echo "$l"; done; echo '---'; } > "$w/.context/testing-profile.md"
}
sgd_layout() {  # sgd_layout <W>: W/repo is main with its git dir elsewhere, W/_wt/feat its worktree
  local w="$1"; mkdir -p "$w"
  git init -q -b main --separate-git-dir="$w.git" "$w/repo"; printf 'echo "1 passed"\n' > "$w/repo/t.sh"
  git -C "$w/repo" add -A; gcommit "$w/repo" main
  git -C "$w/repo" worktree add -q -b feat "$w/_wt/feat" 2>/dev/null
  printf 'echo "2 passed"\n' > "$w/_wt/feat/t.sh"; gcommit "$w/_wt/feat" branch-only
}
W1="$TMP/r4sgd"; sgd_layout "$W1"; wprofile "$W1" 'suite_cmd: cd repo && bash t.sh'
refused "a separate-git-dir main nested under the profile's root" "$W1" "$W1/_wt/feat" --only suite
W2="$TMP/r4bare"; mkdir -p "$W2" "$TMP/r4seed"; git -C "$TMP/r4seed" init -q -b main
printf 'echo "1 passed"\n' > "$TMP/r4seed/t.sh"; git -C "$TMP/r4seed" add -A; gcommit "$TMP/r4seed" main
git clone -q --bare "$TMP/r4seed" "$TMP/r4bare.git"
git -C "$TMP/r4bare.git" worktree add -q "$W2/repo" main 2>/dev/null
git -C "$TMP/r4bare.git" worktree add -q -b feat "$W2/_wt/feat" 2>/dev/null
printf 'echo "2 passed"\n' > "$W2/_wt/feat/t.sh"; gcommit "$W2/_wt/feat" branch-only
wprofile "$W2" 'suite_cmd: cd repo && bash t.sh'
refused "a bare repo whose other worktree is the profile's repo" "$W2" "$W2/_wt/feat" --only suite
M3="$TMP/r4lmain"; mkdir -p "$M3"; git -C "$M3" init -q -b main
printf 'echo "1 passed"\n' > "$M3/t.sh"; git -C "$M3" add -A; gcommit "$M3" main
W3="$TMP/r4link"; mkdir -p "$W3"; ln -s "$M3" "$W3/repo"
git -C "$M3" worktree add -q -b feat "$W3/_wt/feat" 2>/dev/null
printf 'echo "2 passed"\n' > "$W3/_wt/feat/t.sh"; gcommit "$W3/_wt/feat" branch-only
wprofile "$W3" 'suite_cmd: cd repo && bash t.sh'
refused "a profile repo that is a symlink to main" "$W3" "$W3/_wt/feat" --only suite
W4="$TMP/r4abs"; mkdir -p "$W4"; W4="$(cd "$W4" && pwd -P)"; git -C "$W4" init -q -b main
printf '.context/\n_tmp/\n_wt/\n' > "$W4/.gitignore"; printf 'echo "1 passed"\n' > "$W4/t.sh"; git -C "$W4" add -A; gcommit "$W4" main
git -C "$W4" worktree add -q -b feat "$W4/_wt/feat" 2>/dev/null
printf 'echo "2 passed"\n' > "$W4/_wt/feat/t.sh"; gcommit "$W4/_wt/feat" branch-only
wprofile "$W4" "suite_cmd: cd $W4 && bash t.sh"
refused "a profile that cds to main's absolute path" "$W4" "$W4/_wt/feat" --only suite
grep -q 'not in the linked worktree' "$TMP/err" && ok "13 the absolute cd is refused by the landing invariant" || bad "13 absolute cd reason: $(cat "$TMP/err")"
W5="$TMP/r4det"; sgd_layout "$W5"; wprofile "$W5" 'e2e_suite_cmd: cd repo && bash t.sh' 'e2e_detached: true'
refused "a detached e2e leg landing in main" "$W5" "$W5/_wt/feat" --only e2e
grep -q 'run_in_background' "$TMP/err" && bad "13 the refused detached leg still printed its command" || ok "13 the refused detached leg prints no command"
# a detached leg whose commit the gate cannot name (a nested repo, no cd) is still printed
# (owner 2026-10-01, option a): its header ties the log to the leg and `run in` only
W6="$TMP/r4nest"; mkdir -p "$W6"; W6="$(cd "$W6" && pwd -P)"; git -C "$W6" init -q -b main
printf '.context/\n_tmp/\n_wt/\n' > "$W6/.gitignore"; printf 'echo "1 passed"\n' > "$W6/t.sh"; git -C "$W6" add -A; gcommit "$W6" main
git -C "$W6" worktree add -q -b feat "$W6/_wt/feat" 2>/dev/null; git init -q "$W6/_wt/feat/sub"
wprofile "$W6" 'e2e_suite_cmd: bash t.sh' 'e2e_detached: true'
OUT="$(RUN_DIR="$W6/_wt/feat" run --only e2e)"; RC=$?
[[ $RC -eq 3 ]] && grep -q '^  cd ' "$TMP/err" \
  && ok "13 a detached leg whose commit cannot be named is printed, PENDING" || bad "13 nested detached: rc=$RC $OUT $(cat "$TMP/err")"
# the layout Stage 5 recommends: DEST is a `.` worktree of the workspace repo, with the nested
# backend repo's worktree inside it; a no-cd detached leg from the DEST root was refused
# outright by the round-2 print-time refusal (review of BL-557)
WR="$TMP/r2ws"; mkdir -p "$WR"; WR="$(cd "$WR" && pwd -P)"; git -C "$WR" init -q -b main
printf '_tmp/\nbackend/\n' > "$WR/.gitignore"; mkdir -p "$WR/.context"; printf 'x\n' > "$WR/.context/keep"
printf '#!/usr/bin/env bash\necho "4 passed"\n' > "$WR/test-e2e.sh"; chmod +x "$WR/test-e2e.sh"; git -C "$WR" add -A; gcommit "$WR" main
BR="$WR/backend"; mkdir -p "$BR"; git -C "$BR" init -q -b main; printf 'x\n' > "$BR/f"; git -C "$BR" add -A; gcommit "$BR" main
DT="$TMP/r2dest"; git -C "$WR" worktree add -q -b feat "$DT" 2>/dev/null; DT="$(cd "$DT" && pwd -P)"
git -C "$BR" worktree add -q -b feat "$DT/backend" 2>/dev/null
wprofile "$DT" 'e2e_suite_cmd: ./test-e2e.sh' 'e2e_detached: true'
OUT="$(RUN_DIR="$DT" run --only e2e)"; RC=$?
[[ $RC -eq 3 ]] && grep -q '^  cd ' "$TMP/err" \
  && ok "13 a DEST-root detached leg over a nested repo is printed, PENDING" || bad "13 r2 DEST detached: rc=$RC $OUT $(cat "$TMP/err")"
( cd "$DT" && bash -c "$(sed -n 's/^  cd /cd /p' "$TMP/err")" )
OUT="$(RUN_DIR="$DT" run --only e2e --from-log "$DT/_tmp/sweep-gate/e2e.log")"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"leg=e2e exit=0 count=4 "* && "$(head -1 "$DT/_tmp/sweep-gate/e2e.log")" == *"; commit unknown" ]] \
  && ok "13 its log, tied by leg and run-in only, is scored" || bad "13 r2 DEST from-log: rc=$RC $OUT $(cat "$TMP/err")"
# BL-556 (owner 2026-10-01: keep the refusal): a worktree.sh DEST whose root is itself a
# checkout (the `.` participant) and a leg with no cd lands in that root, not the repo worktree.
# The refusal names the cause and the fix.
WS="$TMP/r4ws"; mkdir -p "$WS"; WS="$(cd "$WS" && pwd -P)"; git -C "$WS" init -q -b main
printf '_tmp/\nrepo/\n' > "$WS/.gitignore"; mkdir -p "$WS/.context"; printf 'x\n' > "$WS/.context/keep"; git -C "$WS" add -A; gcommit "$WS" main
DR="$TMP/r4dest"; git -C "$WS" worktree add -q -b feat "$DR" 2>/dev/null; DR="$(cd "$DR" && pwd -P)"
RR="$TMP/r4repo"; mkdir -p "$RR"; git -C "$RR" init -q -b main; printf 'echo "1 passed"\n' > "$RR/t.sh"; git -C "$RR" add -A; gcommit "$RR" main
git -C "$RR" worktree add -q -b feat "$DR/repo" 2>/dev/null
wprofile "$DR" 'suite_cmd: bash t.sh'
refused "a DEST root-participant leg with no cd" "$DR" "$DR/repo" --only suite
grep -qF "(its own checkout $DR)" "$TMP/err" && grep -q 'make the leg cd into the repo worktree it tests' "$TMP/err" \
  && ok "13 the DEST root-participant refusal names the cause and the fix (BL-556)" || bad "13 BL-556 message: $(cat "$TMP/err")"
# the same refusal for a leg that cds to the root by absolute path: no "has no leading cd"
wprofile "$DR" "suite_cmd: cd $DR && bash t.sh"
refused "a DEST leg that cds to the DEST root" "$DR" "$DR/repo" --only suite
grep -q 'make the leg cd into the repo worktree it tests' "$TMP/err" && ! grep -q 'no leading' "$TMP/err" \
  && ok "13 a cd to the DEST root gets the same cause and fix" || bad "13 BL-556 abs cd message: $(cat "$TMP/err")"
# a DEST whose root is not a checkout at all: the message names no checkout it does not have
wprofile "$D" 'suite_cmd: bash t.sh'
OUT="$(RUN_DIR="$D/repo" run --only suite)"; RC=$?
[[ $RC -eq 2 ]] && grep -q 'not a checkout' "$TMP/err" && grep -q 'make the leg cd into the repo worktree it tests' "$TMP/err" \
  && ok "13 a non-git DEST root is named as not a checkout" || bad "13 BL-556 non-git message: rc=$RC $(cat "$TMP/err")"
wprofile "$W4" 'suite_cmd: cd "$PWD" && bash t.sh'
refused "a cd the gate cannot read" "$W4" "$W4/_wt/feat" --only suite
grep -q 'cannot resolve' "$TMP/err" && ok "13 the unreadable cd is named as the reason" || bad "13 unreadable cd reason: $(cat "$TMP/err")"
# BL-558 (b): a cd after a quote or a backslash is a cd too — `bash -c 'cd <main> ...' -`
# (the form dynamic_sites_ws wraps its legs in), `\cd`, `eval "cd ..."` each ran main
for form in "bash -c 'cd $W4 && bash t.sh' -" "\\cd $W4 && bash t.sh" "eval \"cd $W4\" && bash t.sh" \
            "c\\d $W4 && bash t.sh" "true && 'cd' $W4 && bash t.sh" "cd'' $W4 && bash t.sh" \
            "cd>/dev/null $W4 && bash t.sh" "\$'cd' $W4 && bash t.sh" "pushd $W4 && bash t.sh"; do
  wprofile "$W4" "suite_cmd: $form"
  refused "a quoted or escaped cd [$form]" "$W4" "$W4/_wt/feat" --only suite
  grep -q 'cannot resolve' "$TMP/err" || bad "13 [$form] refused for another reason: $(cat "$TMP/err")"
done
# the boundary is a word boundary, not a list of neighbours: `cd` inside a file or flag name is no cd
wprofile "$W4" "suite_cmd: bash t.sh cd-check.sh tests/cd/x.sh --x=cd.py"
OUT="$(RUN_DIR="$W4/_wt/feat" run --only suite)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"count=2 "* ]] && ok "13 'cd' inside a file or flag name is not refused" || bad "13 cd substring refused: rc=$RC $OUT $(cat "$TMP/err")"
rm -rf "$W4/_tmp" "$W4/.context/proofs"
# BL-558 (a): an exported CDPATH turns the leg's `cd sub` into main's sub while the
# invariant computed the worktree's — the leg PASSed on main's code. Inline and detached.
C="$TMP/r5cdp"; mkdir -p "$C/sub"; C="$(cd "$C" && pwd -P)"; git -C "$C" init -q -b main
printf '.context/\n_tmp/\n_wt/\n' > "$C/.gitignore"; printf 'echo "1 passed"\n' > "$C/sub/t.sh"; git -C "$C" add -A; gcommit "$C" main
git -C "$C" worktree add -q -b feat "$C/_wt/feat" 2>/dev/null
printf 'echo "branch fails"; exit 1\n' > "$C/_wt/feat/sub/t.sh"; gcommit "$C/_wt/feat" branch-only
wprofile "$C" 'suite_cmd: cd sub && bash t.sh' 'e2e_suite_cmd: cd sub && bash t.sh' 'e2e_detached: true'
OUT="$(CDPATH="$C" RUN_DIR="$C/_wt/feat" run --only suite)"; RC=$?
[[ $RC -ne 0 && "$OUT" != *"verdict=PASS"* ]] && grep -q 'branch fails' "$C/_tmp/sweep-gate/suite.log" \
  && ok "13 with CDPATH=<main> exported, the leg's cd still lands in the worktree" || bad "13 CDPATH ran main: rc=$RC $OUT"
CDPATH="$C" RUN_DIR="$C/_wt/feat" run --only e2e >/dev/null
( cd "$C/_wt/feat" && CDPATH="$C" bash -c "$(sed -n 's/^  cd /cd /p' "$TMP/err")" )
grep -q 'branch fails' "$C/_tmp/sweep-gate/e2e.log" && ! grep -q '1 passed' "$C/_tmp/sweep-gate/e2e.log" \
  && ok "13 the printed detached invocation lands in the worktree under CDPATH too" || bad "13 detached CDPATH log: $(cat "$C/_tmp/sweep-gate/e2e.log")"
wprofile "$C" 'e2e_suite_cmd: cd sub && bash t.sh' 'e2e_pre_cmd: true' 'e2e_detached: true'
CDPATH="$C" RUN_DIR="$C/_wt/feat" run --only e2e >/dev/null
( cd "$C/_wt/feat" && CDPATH="$C" bash -c "$(sed -n 's/^  cd /cd /p' "$TMP/err")" )
grep -q 'branch fails' "$C/_tmp/sweep-gate/e2e.log" && ! grep -q '1 passed' "$C/_tmp/sweep-gate/e2e.log" \
  && ok "13 the printed detached invocation with a pre-command lands in the worktree under CDPATH too" || bad "13 detached+pre CDPATH log: $(cat "$C/_tmp/sweep-gate/e2e.log")"

[[ $FAIL -eq 0 ]] && { echo "OK — sweep-gate: $PASS cells, countless leg fails, mutation flips it"; exit 0; }
echo "$FAIL failure(s), $PASS ok"; exit 1
