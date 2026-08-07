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
#     would execute. Globs (* ? [ ]) must survive — pytest relies on the shell
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

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — affected-tests: module+hints, unmapped, clean tree, partial --since, test-file attribution, --command merge/INCOMPLETE/exit-3"
