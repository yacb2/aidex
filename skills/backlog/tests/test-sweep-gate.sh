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

[[ $FAIL -eq 0 ]] && { echo "OK — sweep-gate: $PASS cells, countless leg fails, mutation flips it"; exit 0; }
echo "$FAIL failure(s), $PASS ok"; exit 1
