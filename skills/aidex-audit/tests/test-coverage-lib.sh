#!/usr/bin/env bash
# test-coverage-lib.sh — _coverage_lib.py against the coverage-workspace fixture
# (house pattern, same assert style as test-status-vocab.sh): load_map parses a
# valid module-map; a missing-key map dies with ERROR:; matches() honors ** glob
# scoping; repo_for() resolves both repos; commits_since() counts real commits
# for in-repo globs and 0 for out-of-repo globs; count_tests() counts test( /
# it( / def test_ occurrences and not describe/hook/step calls. Plus the
# review-2026-08-23 regressions: wildcard-above-repo globs, ** segment
# anchoring, trailing-slash dirs, load_map shape checks, non-ASCII paths.
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
assert m['version'] == 2
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

# --- repo_for(): longest prefix wins (regression: review finding 2026-07-05,
# first-match order used to let a root '.' repo shadow a nested one) ---
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
repos = [{'name': 'root', 'path': '.'}, {'name': 'backend', 'path': 'backend'}]
r = lib.repo_for('backend/apps/billing/views.py', repos)
assert r is not None and r['name'] == 'backend', r
r_root = lib.repo_for('unrelated/file.txt', repos)
assert r_root is not None and r_root['name'] == 'root', r_root
print('OK')
")"
[[ "$out" == "OK" ]] || fail "repo_for() longest-prefix: $out"

# --- load_map: repos[] entry missing 'path' exits non-zero with ERROR:
# (regression: used to raise an uncaught KeyError downstream) ---
BADREPO="$TMP/bad-repo-workspace"
mkdir -p "$BADREPO/.context/audits/test-coverage"
echo '{"version": 1, "repos": [{"name": "backend"}], "modules": []}' > "$BADREPO/.context/audits/test-coverage/module-map.json"
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
lib.load_map('$BADREPO')
" 2>&1)"
rc=$?
[[ $rc -ne 0 ]] || fail "load_map on repo missing 'path' should exit non-zero"
printf '%s' "$out" | grep -q "ERROR:" || fail "load_map repo-missing-path error should say ERROR:, got: $out"

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

# --- commits_since(): a glob whose first wildcard sits ABOVE the repo path
# (review 2026-08-23 #32: `**/views.py` matched the files but counted 0 commits
# because the repo-prefix filter dropped the glob) ---
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
m = lib.load_map('$WS')
backend = next(r for r in m['repos'] if r['name'] == 'backend')
n = lib.commits_since('$WS', backend, '1970-01-01', ['**/views.py'])
assert n >= 1, n
n2 = lib.commits_since('$WS', backend, '1970-01-01', ['*/apps/billing/**'])
assert n2 >= 1, n2
print('OK')
")"
[[ "$out" == "OK" ]] || fail "commits_since() glob with wildcard above repo path: $out"

# --- glob_to_re(): a mid-path ** re-anchors at a segment boundary (#38),
# and a trailing-slash directory glob matches its contents (#34) ---
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
assert lib.matches('a/xb', ['a/**/b']) is False
assert lib.matches('a/b', ['a/**/b']) is True
assert lib.matches('a/x/y/b', ['a/**/b']) is True
assert lib.matches('backend/apps/old_views.py', ['backend/**/views.py']) is False
assert lib.matches('backend/apps/billing/views.py', ['backend/**/views.py']) is True
assert lib.matches('backend/apps/auth/x.py', ['backend/apps/auth/']) is True
print('OK')
")"
[[ "$out" == "OK" ]] || fail "glob_to_re() ** segment anchoring / trailing slash: $out"

# --- count_tests(): structural calls (describe/beforeEach/step) and
# RegExp.test( are not tests; it( is (#33) ---
mkdir -p "$TMP/cnt"
cat > "$TMP/cnt/a.spec.ts" <<'EOF'
test.describe('suite', () => {
  test.beforeEach(async () => {});
  it('a', async () => { await test.step('s', () => {}); });
  it('b', () => {});
});
EOF
cat > "$TMP/cnt/b.test.ts" <<'EOF'
it('a', () => {}); it('b', () => {}); test('c', () => {}); const ok = /x/.test(s);
EOF
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
assert lib.count_tests('$TMP/cnt', ['a.spec.ts']) == 2, lib.count_tests('$TMP/cnt', ['a.spec.ts'])
assert lib.count_tests('$TMP/cnt', ['b.test.ts']) == 3, lib.count_tests('$TMP/cnt', ['b.test.ts'])
print('OK')
")"
[[ "$out" == "OK" ]] || fail "count_tests() it()/describe rules: $out"

# --- load_map: repos [] (#43), string-typed src (#63) and invalid JSON (#59)
# all die with ERROR: instead of yielding an all-zero result ---
for case in 'repos-empty:{"version": 2, "repos": [], "modules": [{"id": "m", "src": ["a/**"], "tests": {}}]}' \
            'src-string:{"version": 2, "repos": [{"name": "r", "path": "."}], "modules": [{"id": "m", "src": "a/**", "tests": {}}]}' \
            'not-json:{not json'; do
  name="${case%%:*}"; body="${case#*:}"
  D="$TMP/$name"
  mkdir -p "$D/.context/audits/test-coverage"
  printf '%s' "$body" > "$D/.context/audits/test-coverage/module-map.json"
  out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
lib.load_map('$D')
" 2>&1)"
  rc=$?
  [[ $rc -ne 0 ]] || fail "load_map on $name should exit non-zero"
  printf '%s' "$out" | grep -q "ERROR:" || fail "load_map on $name should say ERROR:, got: $out"
done

# --- list_files(): a non-ASCII path arrives unquoted (#46: git's default
# core.quotePath C-quotes it, and the quoted name matches no glob) ---
U="$TMP/unicode-repo"
mkdir -p "$U/api"
printf 'def test_a():\n    pass\n' > "$U/api/tést.py"
printf 'def test_b():\n    pass\n' > "$U/api/plain.py"
git -C "$U" init -q && git -C "$U" add -A && git -C "$U" -c user.email=t@e.com -c user.name=T commit -q -m init
out="$(python3 -c "
import sys; sys.path.insert(0, '$LIB_DIR')
import _coverage_lib as lib
files = lib.list_files('$U', [{'name': 'r', 'path': '.'}])
assert sorted(files) == ['api/plain.py', 'api/tést.py'], files
assert lib.count_tests('$U', [f for f in files if lib.matches(f, ['api/**'])]) == 2
print('OK')
")"
[[ "$out" == "OK" ]] || fail "list_files() non-ASCII path: $out"

rm -rf "$WS"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — load_map, matches, repo_for, commits_since, count_tests on the coverage-workspace fixture"
