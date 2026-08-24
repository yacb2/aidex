#!/usr/bin/env bash
# test-affected-tests.sh — affected_tests.py against the coverage-workspace
# fixture (house pattern, same assert style as test-coverage-sweep.sh).
# Scenarios:
#   (a) dirty src file -> module listed with both test groups + rendered hints
#   (b) change outside any module -> appears under Unmapped
#   (c) clean tree -> "0 changed files"
#   (d) --since a ref missing from one repo -> warning + partial result, exit 0
#   (e) changed TEST file attributes to its module, never listed as Unmapped
#
# Run with: bash skills/aidex-audit/tests/test-affected-tests.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"
FIXTURE="$TESTS_DIR/fixtures/coverage-workspace.sh"
AFFECTED="$SCRIPTS_DIR/coverage/affected_tests.py"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# ---------------------------------------------------------------------------
# (a) dirty src file -> billing listed with unit + e2e groups and hints
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
echo x >> "$WS/backend/apps/billing/views.py"
out_a="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
rc=$?
[[ $rc -eq 0 ]] || fail "(a) affected_tests should exit 0 (got $rc)"
echo "$out_a" | grep -q '^\[billing\]$' \
  || fail "(a) billing module should be listed: $out_a"
echo "$out_a" | grep -q 'unit: backend/apps/billing/tests/.*hint: cd backend && pytest apps/billing/tests/' \
  || fail "(a) unit group + hint missing: $out_a"
echo "$out_a" | grep -q 'e2e:.*frontend/tests/e2e/billing/.*hint: \./test-e2e\.sh tests/e2e/billing/' \
  || fail "(a) e2e group + hint missing: $out_a"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (b) change outside any module -> Unmapped changes
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
mkdir -p "$WS/frontend/src/shared"
echo "export const x = 1;" > "$WS/frontend/src/shared/util.ts"
git -C "$WS/frontend" add -A
out_b="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_b" | grep -q 'Unmapped changes' \
  || fail "(b) expected an Unmapped changes section: $out_b"
echo "$out_b" | grep -q 'frontend/src/shared/util.ts' \
  || fail "(b) unmapped file should be listed: $out_b"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (c) clean tree -> "0 changed files"
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
out_c="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
rc=$?
[[ $rc -eq 0 ]] || fail "(c) clean tree should exit 0 (got $rc)"
echo "$out_c" | grep -q '0 changed files' \
  || fail "(c) expected '0 changed files': $out_c"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (d) --since a ref that exists in backend but not frontend -> warning +
#     partial result, exit 0
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE" --drift)"
TAG="pre-drift"
# Tag exists only in the backend repo's history (frontend has no such ref).
git -C "$WS/backend" tag "$TAG" HEAD~1 2>/dev/null \
  || git -C "$WS/backend" tag "$TAG" HEAD
err_d="$(python3 "$AFFECTED" "$WS" --since "$TAG" 2>&1 >/dev/null)"
out_d="$(python3 "$AFFECTED" "$WS" --since "$TAG" 2>/dev/null)"
rc=$?
[[ $rc -eq 0 ]] || fail "(d) partial --since result should still exit 0 (got $rc)"
echo "$err_d" | grep -qi 'warning' \
  || fail "(d) expected a warning for the missing ref in frontend: $err_d"
echo "$out_d" | grep -q 'billing' \
  || fail "(d) billing should still be reported from the backend side: $out_d"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (e) a changed TEST file attributes to its module and is NOT "unmapped"
#     (regression: field test 2026-07-05 — matching used src globs only, so a
#     modified spec file suggested extending a map that already covered it)
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
echo "// touched" >> "$WS/frontend/tests/e2e/billing/a.spec.ts"
out_e="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_e" | grep -q '^\[billing\]$' \
  || fail "(e) changed spec file should attribute to billing: $out_e"
echo "$out_e" | grep -q 'Unmapped changes' \
  && fail "(e) changed spec file must NOT appear under Unmapped changes: $out_e"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (f) --command: ONE merged unit command per repo, e2e as a comment only
#     (BL-135: per-module commands would pay the container startup floor once
#     per module — 15 s median, 114 s p90 — which can cost more than the
#     selection saves.)
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
# Give `people` a unit test group *in this workspace only* — the shared fixture
# deliberately leaves it uncovered for the sweep tests. Two modules in one repo is
# what makes the merge observable.
mkdir -p "$WS/backend/apps/people/tests"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for mod in m["modules"]:
    if mod["id"] == "people":
        mod.setdefault("tests", {})["unit"] = ["backend/apps/people/tests/**"]
json.dump(m, open(p, "w"), indent=2)
PY
echo x >> "$WS/backend/apps/billing/views.py"
echo x >> "$WS/backend/apps/people/views.py"
out_f="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
rc=$?
[[ $rc -eq 0 ]] || fail "(f) --command with a selection should exit 0 (got $rc)"
[[ "$(echo "$out_f" | grep -vc '^#')" -eq 1 ]] \
  || fail "(f) two modules in one repo must merge into ONE command: $out_f"
echo "$out_f" | grep -q '^cd backend && pytest apps/billing/tests/ apps/people/tests/' \
  || fail "(f) merged unit command missing or unmerged: $out_f"
echo "$out_f" | grep -q '^# e2e specs affected' \
  || fail "(f) e2e specs should be a comment, never a command: $out_f"
echo "$out_f" | grep -vE '^#' | grep -q 'test-e2e' \
  && fail "(f) --command must not emit an e2e run command: $out_f"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (g) --command with an unmapped change flags the selection INCOMPLETE.
#     A selection that silently omits what it does not cover reads as a
#     full all-clear — the failure mode verification-before-claims forbids.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
echo x >> "$WS/backend/apps/billing/views.py"
mkdir -p "$WS/frontend/src/shared"
echo "export const x = 1;" > "$WS/frontend/src/shared/util.ts"
git -C "$WS/frontend" add -A
out_g="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
echo "$out_g" | grep -q '^# INCOMPLETE: 1 changed file' \
  || fail "(g) unmapped change should mark the selection INCOMPLETE: $out_g"
echo "$out_g" | grep -q 'full suite still gates the commit' \
  || fail "(g) INCOMPLETE line must name the full-suite gate: $out_g"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (h) --command exits 3 (no selection available), never 0-with-empty-output,
#     when there is no map / no change / no match. A caller must be able to
#     tell "run nothing" apart from "selection unavailable, run everything".
# ---------------------------------------------------------------------------
NOMAP="$(mktemp -d)"; mkdir -p "$NOMAP/.context"
python3 "$AFFECTED" "$NOMAP" --command >/dev/null 2>&1
[[ $? -eq 3 ]] || fail "(h) no module-map under --command should exit 3"
err_h="$(python3 "$AFFECTED" "$NOMAP" --command 2>&1 >/dev/null)"
echo "$err_h" | grep -q 'run the full suite' \
  || fail "(h) the no-map message must name the full-suite fallback: $err_h"
rm -rf "$NOMAP"

WS="$(bash "$FIXTURE")"
python3 "$AFFECTED" "$WS" --command >/dev/null 2>&1
[[ $? -eq 3 ]] || fail "(h) clean tree under --command should exit 3"
rm -rf "$WS"

# The human-readable default must be unchanged by any of the above.
WS="$(bash "$FIXTURE")"
echo x >> "$WS/backend/apps/billing/views.py"
out_i="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_i" | grep -q '^AFFECTED TESTS — 1 changed file, 1 module$' \
  || fail "(i) default report regressed: $out_i"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (j) --command must never emit a line carrying shell metacharacters.
#     The output is meant to be RUN, so a map entry like `tests/**; curl evil`
#     would execute. Globs (* ?) must survive — pytest relies on the shell
#     expanding `test_auth_*.py` — so the guard rejects metacharacters without
#     quoting the path.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for mod in m["modules"]:
    if mod["id"] == "billing":
        mod["tests"]["unit"] = ["backend/apps/billing/tests/x; touch /tmp/aidex-pwned/**"]
json.dump(m, open(p, "w"), indent=2)
PY
echo x >> "$WS/backend/apps/billing/views.py"
# stdout is what a caller runs; the refusal goes to stderr and quotes the
# offending path, so the two must be asserted separately.
out_j="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
rc=$?
err_j="$(python3 "$AFFECTED" "$WS" --command 2>&1 >/dev/null)"
echo "$out_j" | grep -q 'touch /tmp/aidex-pwned' \
  && fail "(j) --command emitted a shell-injectable path on stdout: $out_j"
[[ -z "$out_j" ]] || fail "(j) stdout must be empty when refusing: $out_j"
[[ $rc -ne 0 ]] || fail "(j) an unsafe map entry must not exit 0 (got $rc)"
echo "$err_j" | grep -qi 'unsafe' \
  || fail "(j) refusal must name the problem: $err_j"
rm -rf "$WS"

# A legitimate glob must still pass — the guard must not be a blanket ban.
WS="$(bash "$FIXTURE")"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for mod in m["modules"]:
    if mod["id"] == "billing":
        mod["tests"]["unit"] = ["backend/apps/billing/tests/test_*.py"]
json.dump(m, open(p, "w"), indent=2)
PY
echo x >> "$WS/backend/apps/billing/views.py"
out_j2="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
echo "$out_j2" | grep -q 'apps/billing/tests/test_\*\.py' \
  || fail "(j) a legitimate glob must survive the guard: $out_j2"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (k) a module whose repo has no test_hint is DROPPED from --command output.
#     Silently: the human-readable report still shows its directory, but the
#     command mode emitted nothing for it, so a caller ran a selection that
#     omitted real tests while reading as complete. Fail open -> must announce.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for repo in m["repos"]:
    if repo["name"] != "backend":
        repo.pop("test_hint", None)
m["modules"].append({
    "id": "webonly",
    "src": ["frontend/src/shared/**"],
    "tests": {"unit": ["frontend/tests/unit/**"]},
})
json.dump(m, open(p, "w"), indent=2)
PY
echo x >> "$WS/backend/apps/billing/views.py"
mkdir -p "$WS/frontend/src/shared"
echo "export const x = 1;" > "$WS/frontend/src/shared/util.ts"
git -C "$WS/frontend" add -A
out_k="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
echo "$out_k" | grep -q '^# INCOMPLETE: 1 affected module(s) have no runnable command' \
  || fail "(k) a module with no test_hint must be announced, not dropped: $out_k"
echo "$out_k" | grep -q 'webonly' \
  || fail "(k) the announcement must name the omitted module: $out_k"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (l) a path that IS an option must be refused. The metacharacter guard looks
#     for a dash *after whitespace*, so a rel of exactly `-rf` slipped through
#     and joined into `pytest -rf` — an argument, not a path. Argument injection
#     is the same defect class as command injection with a smaller radius.
#     `~` is here for the same reason: the shell expands it before pytest sees it.
# ---------------------------------------------------------------------------
for BADPATH in "-rf" "--rootdir=+etc" "~+secrets"; do
  WS="$(bash "$FIXTURE")"
  BADGLOB="backend/${BADPATH}/**" python3 - "$WS" <<'PYL'
import json, os, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for mod in m["modules"]:
    if mod["id"] == "billing":
        mod["tests"]["unit"] = [os.environ["BADGLOB"]]
json.dump(m, open(p, "w"), indent=2)
PYL
  echo x >> "$WS/backend/apps/billing/views.py"
  out_l="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
  rc=$?
  [[ $rc -ne 0 ]] || fail "(l) option-shaped path '$BADPATH' must not exit 0 (got $rc)"
  [[ -z "$out_l" ]] || fail "(l) option-shaped path '$BADPATH' reached stdout: $out_l"
  rm -rf "$WS"
done

# ---------------------------------------------------------------------------
# (m) a test kind with SEVERAL globs: every glob reaches the selection. Only
#     globs[0] used to, so a second unit directory (perms_tests/) never ran and
#     the caller read a green partial run as complete — with no INCOMPLETE line.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
mkdir -p "$WS/backend/apps/billing/perms_tests"
echo "def test_p(): assert True" > "$WS/backend/apps/billing/perms_tests/test_perms.py"
git -C "$WS/backend" add -A && git -C "$WS/backend" commit -qm "perms tests"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for mod in m["modules"]:
    if mod["id"] == "billing":
        mod["tests"]["unit"] = ["backend/apps/billing/tests/**", "backend/apps/billing/perms_tests/**"]
json.dump(m, open(p, "w"), indent=2)
PY
echo x >> "$WS/backend/apps/billing/views.py"
out_m="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
echo "$out_m" | grep -q '^cd backend && pytest apps/billing/tests/ apps/billing/perms_tests/$' \
  || fail "(m) every unit glob must reach the --command selection: $out_m"
out_m2="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_m2" | grep -q 'unit: backend/apps/billing/perms_tests/' \
  || fail "(m) the human report must list the second unit glob: $out_m2"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (n) an affected module with NO tests mapped at all must be announced under
#     --command. It yields no group, so it fell through both the command list
#     and the no_command INCOMPLETE line — the only mode the callers use said
#     nothing about it.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
echo x >> "$WS/backend/apps/billing/views.py"
echo x >> "$WS/backend/apps/people/views.py"   # people maps to {unit: [], e2e: []}
out_n="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
echo "$out_n" | grep -q '^# INCOMPLETE:.*no tests mapped.*people' \
  || fail "(n) a changed module with no mapped tests must be announced: $out_n"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (o) no unit command renders, but there IS something to say: the e2e spec
#     pointer / the no-test_hint reason. Both were discarded by an early
#     `return None`, and main then claimed "changed files match no mapped
#     module" — false, the file matched. Exit stays 3 (no runnable selection).
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for mod in m["modules"]:
    if mod["id"] == "billing":
        mod["tests"]["unit"] = []
json.dump(m, open(p, "w"), indent=2)
PY
echo "<!-- x -->" >> "$WS/frontend/src/billing/Form.vue"
err_o="$(python3 "$AFFECTED" "$WS" --command 2>&1 >/dev/null)"
python3 "$AFFECTED" "$WS" --command >/dev/null 2>&1
[[ $? -eq 3 ]] || fail "(o) an e2e-only match has no runnable selection: exit 3"
echo "$err_o" | grep -q '# e2e specs affected.*frontend/tests/e2e/billing/' \
  || fail "(o) the e2e spec pointer must survive when no unit command renders: $err_o"
echo "$err_o" | grep -q 'match no mapped module' \
  && fail "(o) the file DID match a module; the message must not claim otherwise: $err_o"
rm -rf "$WS"

WS="$(bash "$FIXTURE")"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for repo in m["repos"]:
    repo.pop("test_hint", None)
json.dump(m, open(p, "w"), indent=2)
PY
echo x >> "$WS/backend/apps/billing/views.py"
err_o2="$(python3 "$AFFECTED" "$WS" --command 2>&1 >/dev/null)"
echo "$err_o2" | grep -q 'no test_hint' \
  || fail "(o) the no-test_hint reason must be surfaced, not swallowed: $err_o2"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (p) --since a ref that exists in NO repo. Every repo skipped is "nothing was
#     checked", and it was reported as "0 changed files" with exit 0 — a typo'd
#     ref on a branch full of changes read as nothing affected.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE" --drift)"
out_p="$(python3 "$AFFECTED" "$WS" --since nosuchref 2>/dev/null)"
rc=$?
err_p="$(python3 "$AFFECTED" "$WS" --since nosuchref 2>&1 >/dev/null)"
[[ $rc -eq 2 ]] || fail "(p) a ref missing from every repo is a hard error, exit 2 (got $rc)"
echo "$out_p" | grep -q '0 changed files' \
  && fail "(p) 'nothing checked' must not read as 'nothing changed': $out_p"
echo "$err_p" | grep -q 'not found in any repo' \
  || fail "(p) the error must say no repo resolved the ref: $err_p"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (q) --command with a valid map but a broken repo path: the git error must
#     reach stderr. It was replaced by "no module-map", which sent the operator
#     hunting for a file that exists.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
m["repos"].append({"name": "ghost", "path": "ghost"})
json.dump(m, open(p, "w"), indent=2)
PY
echo x >> "$WS/backend/apps/billing/views.py"
err_q="$(python3 "$AFFECTED" "$WS" --command 2>&1 >/dev/null)"
python3 "$AFFECTED" "$WS" --command >/dev/null 2>&1
[[ $? -eq 3 ]] || fail "(q) a hard error under --command still exits 3 (full-suite fallback)"
echo "$err_q" | grep -q 'ghost' \
  || fail "(q) the real error (broken repo path) must reach stderr: $err_q"
echo "$err_q" | grep -q 'no module-map' \
  && fail "(q) the map exists; the message must not say it is missing: $err_q"
echo "$err_q" | grep -q 'run the full suite' \
  || fail "(q) the fallback instruction must still be there: $err_q"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (r) a path containing whitespace word-splits into two bogus paths when the
#     command is run. The guard let it through: it only caught whitespace
#     followed by a dash.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for mod in m["modules"]:
    if mod["id"] == "billing":
        mod["tests"]["unit"] = ["backend/apps/billing/my tests/**"]
json.dump(m, open(p, "w"), indent=2)
PY
echo x >> "$WS/backend/apps/billing/views.py"
out_r="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
rc=$?
[[ $rc -ne 0 ]] || fail "(r) a path with whitespace must be refused, not emitted (got $rc)"
[[ -z "$out_r" ]] || fail "(r) whitespace path reached stdout: $out_r"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (s) --help prints usage and exits 0 like every sibling; an unknown flag is a
#     usage error. `--comand` used to fall through to the human report on
#     stdout with exit 0 — a caller piping stdout into a shell got a headline.
# ---------------------------------------------------------------------------
python3 "$AFFECTED" --help >/dev/null 2>&1
[[ $? -eq 0 ]] || fail "(s) --help must exit 0"
python3 "$AFFECTED" --help 2>/dev/null | grep -q 'affected_tests.py <workspace-root>' \
  || fail "(s) --help must print the usage line"
WS="$(bash "$FIXTURE")"
echo x >> "$WS/backend/apps/billing/views.py"
out_s="$(python3 "$AFFECTED" "$WS" --comand 2>/dev/null)"
rc=$?
[[ $rc -ne 0 ]] || fail "(s) an unknown flag must be a usage error (got $rc)"
[[ -z "$out_s" ]] || fail "(s) an unknown flag must not produce a report on stdout: $out_s"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (t) a third test kind (06-test-coverage.md: keys are open-ended) must reach
#     the selection like unit does. The kind loop was pinned to ("unit","e2e"),
#     so a module mapped ONLY through `integration` reported "no tests mapped"
#     — review 2026-08-23, #48 leg 3.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 - "$WS" <<'PY'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for mod in m["modules"]:
    if mod["id"] == "people":
        mod["tests"] = {"integration": ["backend/apps/people/tests/**"]}
json.dump(m, open(p, "w"), indent=2)
PY
mkdir -p "$WS/backend/apps/people/tests"; echo 'def test_x(): pass' > "$WS/backend/apps/people/tests/test_it.py"
/usr/bin/git -C "$WS/backend" add -A >/dev/null 2>&1; /usr/bin/git -C "$WS/backend" -c user.email=t@t -c user.name=t commit -qm "third kind" >/dev/null 2>&1
echo x >> "$WS/backend/apps/people/views.py"
out_t="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"
echo "$out_t" | grep -q 'apps/people/tests/' \
  || fail "(t) a third test kind must reach the --command selection: $out_t"
echo "$out_t" | grep -q 'no tests mapped.*people' \
  && fail "(t) a module mapped through a third kind is NOT 'no tests mapped': $out_t"
rm -rf "$WS"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — affected-tests: module+hints, unmapped, clean tree, partial --since, test-file attribution, --command merge/INCOMPLETE/exit-3, multi-glob, no-tests module, e2e-only/no-hint advisories, --since all-missing, git error text, whitespace path, --help/unknown flag"
