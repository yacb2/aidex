#!/usr/bin/env bash
# Closing a plan regenerates the coverage boards — or says it could not.
#
# The regression this locks (ns_backoffice BL-197, 2026-08-31): closing the coverage
# adoption plan left `audits/test-coverage/coverage-matrix.md` and the run-level audits
# index stale until someone remembered to regenerate them by hand. A plan close is the
# exact moment the numbers change, so close-plan.sh regenerates them itself when the
# project has a test-coverage module-map, and stays a no-op when it does not.
#
#   PROVES  — (a) with a module-map, close-plan.sh leaves coverage-matrix.md/.json and
#             audits/00-index.md freshly generated and says so; (b) without one it
#             touches nothing under audits/ and prints no coverage line; (c) when the
#             regeneration fails (invalid map) the plan is STILL archived and the
#             failure is reported on stderr instead of swallowed.
#   DOES NOT — judge the boards' content; coverage_matrix.py has its own tests.
#
# Run with: bash tests/test-close-plan-regenerates-coverage-boards.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLOSE="$SCRIPT_DIR/../skills/aidex-plan/scripts/close-plan.sh"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A project: a git repo (the matrix walks `git ls-files`) with one source file, one
# test and one closeable plan.
project() {  # $1 = dir
  mkdir -p "$1/.context/plans" "$1/app"
  printf 'def f():\n    return 1\n' > "$1/app/thing.py"
  printf 'def test_f():\n    assert True\n' > "$1/app/test_thing.py"
  printf -- '---\ntitle: "A plan"\nstatus: doing\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\n\n- [x] the one task\n' \
    > "$1/.context/plans/2026-01-01-a-plan.md"
  ( cd "$1" && /usr/bin/git init -q . && /usr/bin/git add -A \
    && /usr/bin/git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null
}
map() {  # $1 = dir, $2 = json body
  mkdir -p "$1/.context/audits/test-coverage"
  printf '%s' "$2" > "$1/.context/audits/test-coverage/module-map.json"
}
GOOD_MAP='{"version": 2, "repos": [{"name": "app", "path": "."}],
 "modules": [{"id": "thing", "src": ["app/thing.py"], "tests": {"unit": ["app/test_thing.py"]}}]}'

# (a) with a map: boards regenerated and announced
A="$TMP/a"; project "$A"; map "$A" "$GOOD_MAP"
ERR_A="$( (cd "$A" && NO_COLOR=1 bash "$CLOSE" 2026-01-01-a-plan) 2>&1 >/dev/null )"; RC_A=$?
[[ $RC_A -eq 0 ]] || fail "(a) close-plan exited $RC_A: $ERR_A"
[[ -f "$A/.context/plans/_archive/2026-01-01-a-plan.md" ]] || fail "(a) plan not archived"
[[ -f "$A/.context/audits/test-coverage/coverage-matrix.md" ]] || fail "(a) coverage-matrix.md not generated"
[[ -f "$A/.context/audits/test-coverage/coverage-matrix.json" ]] || fail "(a) coverage-matrix.json not generated"
[[ -f "$A/.context/audits/00-index.md" ]] || fail "(a) audits/00-index.md not regenerated"
grep -q "coverage boards regenerated" <<<"$ERR_A" || fail "(a) close did not announce the regeneration: $ERR_A"

# (b) without a map: no-op, no coverage line, nothing created under audits/
B="$TMP/b"; project "$B"
ERR_B="$( (cd "$B" && NO_COLOR=1 bash "$CLOSE" 2026-01-01-a-plan) 2>&1 >/dev/null )"; RC_B=$?
[[ $RC_B -eq 0 ]] || fail "(b) close-plan exited $RC_B: $ERR_B"
[[ -f "$B/.context/plans/_archive/2026-01-01-a-plan.md" ]] || fail "(b) plan not archived"
[[ ! -e "$B/.context/audits" ]] || fail "(b) audits/ created in a project with no map"
grep -q "coverage" <<<"$ERR_B" && fail "(b) coverage mentioned without a map: $ERR_B"

# (c) map present but broken: the close still lands, the failure is reported
C="$TMP/c"; project "$C"; map "$C" '{"version": 2, "repos": [}'
ERR_C="$( (cd "$C" && NO_COLOR=1 bash "$CLOSE" 2026-01-01-a-plan) 2>&1 >/dev/null )"; RC_C=$?
[[ $RC_C -eq 0 ]] || fail "(c) a failed regeneration must not fail the close (exit $RC_C): $ERR_C"
[[ -f "$C/.context/plans/_archive/2026-01-01-a-plan.md" ]] || fail "(c) plan not archived"
grep -q "coverage boards NOT regenerated" <<<"$ERR_C" || fail "(c) failure not reported: $ERR_C"
grep -q "coverage-matrix.sh:" <<<"$ERR_C" || fail "(c) report does not name the failing step: $ERR_C"
[[ ! -f "$C/.context/audits/test-coverage/coverage-matrix.md" ]] || fail "(c) a matrix was written from a broken map"

if [[ $failures -eq 0 ]]; then echo "PASS: close-plan regenerates coverage boards (3 cases)"; exit 0; fi
echo "$failures failure(s)"; exit 1
