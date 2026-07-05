#!/usr/bin/env bash
# test-coverage-lib.sh — _coverage_lib.py against the coverage-workspace fixture
# (house pattern, same assert style as test-status-vocab.sh): load_map parses a
# valid module-map; a missing-key map dies with ERROR:; matches() honors ** glob
# scoping; repo_for() resolves both repos; commits_since() counts real commits
# for in-repo globs and 0 for out-of-repo globs; count_tests() counts test( /
# def test_ occurrences.
#
# Run with: bash skills/aidex-audit/tests/test-coverage-lib.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LIB_DIR="$TESTS_DIR/../scripts/coverage"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

WS="$(bash "$TESTS_DIR/fixtures/coverage-workspace.sh")"

run_py() {
  python3 -c "$1" 2>&1
}

# --- load_map: valid module-map parses ---
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
m = lib.load_map('$WS')
assert m['version'] == 1
assert len(m['modules']) == 2
ids = {mod['id'] for mod in m['modules']}
assert ids == {'billing', 'people'}, ids
print('OK')
")"
[[ "$out" == "OK" ]] || fail "load_map on valid fixture: $out"

# --- load_map: missing key exits non-zero with ERROR: ---
BAD="$TMP/bad-workspace"
mkdir -p "$BAD/.context/audits/test-coverage"
echo '{"version": 1, "repos": []}' > "$BAD/.context/audits/test-coverage/module-map.json"
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
lib.load_map('$BAD')
" 2>&1)"
rc=$?
[[ $rc -ne 0 ]] || fail "load_map on module-map missing 'modules' should exit non-zero"
printf '%s' "$out" | grep -q "ERROR:" || fail "load_map missing-key error should say ERROR:, got: $out"

# --- matches(): ** scoping ---
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
assert lib.matches('frontend/tests/e2e/billing/a.spec.ts', ['frontend/tests/e2e/billing/**']) is True
assert lib.matches('backend/apps/people/views.py', ['frontend/tests/e2e/billing/**']) is False
print('OK')
")"
[[ "$out" == "OK" ]] || fail "matches() ** scoping: $out"

# --- repo_for(): resolves both repos ---
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
m = lib.load_map('$WS')
r1 = lib.repo_for('backend/apps/billing/views.py', m['repos'])
r2 = lib.repo_for('frontend/src/billing/Form.vue', m['repos'])
assert r1 is not None and r1['name'] == 'backend', r1
assert r2 is not None and r2['name'] == 'frontend', r2
print('OK')
")"
[[ "$out" == "OK" ]] || fail "repo_for() resolution: $out"

# --- commits_since(): >=1 for billing src, 0 for a glob outside the repo ---
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
m = lib.load_map('$WS')
backend = next(r for r in m['repos'] if r['name'] == 'backend')
n = lib.commits_since('$WS', backend, '1970-01-01', ['backend/apps/billing/**'])
assert n >= 1, n
n_outside = lib.commits_since('$WS', backend, '1970-01-01', ['frontend/src/billing/**'])
assert n_outside == 0, n_outside
print('OK')
")"
[[ "$out" == "OK" ]] || fail "commits_since(): $out"

# --- count_tests(): 2 for the spec file, 1 for the pytest file ---
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
n_spec = lib.count_tests('$WS', ['frontend/tests/e2e/billing/a.spec.ts'])
n_py = lib.count_tests('$WS', ['backend/apps/billing/tests/test_x.py'])
assert n_spec == 2, n_spec
assert n_py == 1, n_py
print('OK')
")"
[[ "$out" == "OK" ]] || fail "count_tests(): $out"

rm -rf "$WS"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — load_map, matches, repo_for, commits_since, count_tests on the coverage-workspace fixture"
