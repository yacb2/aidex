#!/usr/bin/env bash
# test-coverage-matrix.sh — coverage_matrix.py against the coverage-workspace
# fixture (house pattern, same assert style as test-coverage-lib.sh): matrix
# file exists with GENERATED header; billing row shows 2 e2e spec files (a
# real spec plus a route-constants helper the glob covers) / 2 e2e tests /
# 1 unit file / 1 unit test; people row shows NO TESTS;
# coverage-matrix.json parses and carries a timestamp; running twice is
# idempotent (no duplicate sections); a hand-edit is overwritten on
# regeneration.
#
# Run with: bash skills/aidex-audit/tests/test-coverage-matrix.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

WS="$(bash "$TESTS_DIR/fixtures/coverage-workspace.sh")"
trap 'rm -rf "$WS"' EXIT

MD="$WS/.context/audits/test-coverage/coverage-matrix.md"
JSON="$WS/.context/audits/test-coverage/coverage-matrix.json"

# --- first run: matrix exists with GENERATED header ---
python3 "$SCRIPTS_DIR/coverage/coverage_matrix.py" "$WS" >/dev/null \
  || fail "coverage_matrix.py exited non-zero on first run"
[[ -f "$MD" ]] || fail "coverage-matrix.md not written"
grep -q 'GENERATED' "$MD" || fail "coverage-matrix.md missing GENERATED header"

# --- billing row: 1 unit file, 1 unit test, 1 e2e spec, 2 e2e tests ---
billing_row="$(grep -E '^\| billing \|' "$MD")"
[[ -n "$billing_row" ]] || fail "billing row not found in matrix"
echo "$billing_row" | awk -F'|' '{
  gsub(/^[ \t]+|[ \t]+$/, "", $4); gsub(/^[ \t]+|[ \t]+$/, "", $5);
  gsub(/^[ \t]+|[ \t]+$/, "", $6); gsub(/^[ \t]+|[ \t]+$/, "", $7);
  exit !($4 == "1" && $5 == "1" && $6 == "2" && $7 == "2")
}' || fail "billing row counts wrong (expected unit files=1 unit tests=1 e2e specs=2 e2e tests=2): $billing_row"

# --- people row: NO TESTS ---
people_row="$(grep -E '^\| people \|' "$MD")"
[[ -n "$people_row" ]] || fail "people row not found in matrix"
echo "$people_row" | grep -q 'NO TESTS' || fail "people row should say NO TESTS: $people_row"

# --- json parses and carries a timestamp ---
out="$(python3 -c "
import json
with open('$JSON') as f:
    data = json.load(f)
assert 'generated' in data and data['generated'], data
assert data.get('schema') == 'coverage-matrix/2', data.get('schema')
assert len(data['modules']) == 2, data['modules']
print('OK')
")"
[[ "$out" == "OK" ]] || fail "coverage-matrix.json parse/shape: $out"

# --- typed routes: covered vs uncovered, actions, and the gap list -----------
# The point of the whole field: '/billing/settings' is declared and no e2e spec
# ever visits it, so it must be REPORTED, not silently absent.
out="$(python3 -c "
import json
data = json.load(open('$JSON'))
mods = {m['id']: m for m in data['modules']}
b = mods['billing']
routes = {r['path']: r for r in b['routes']}
assert set(routes) == {'/billing/invoices', '/billing/invoices/:id/edit', '/billing/settings'}, sorted(routes)
assert routes['/billing/invoices']['covered'] is True, routes['/billing/invoices']
assert routes['/billing/invoices']['reached_by'] == ['frontend/tests/e2e/billing/a.spec.ts'], routes['/billing/invoices']
assert routes['/billing/invoices']['spec'] == 'frontend/src/billing/Form.vue', routes['/billing/invoices']
assert routes['/billing/invoices/:id/edit']['covered'] is True, routes['/billing/invoices/:id/edit']
# and a non-spec file inside the e2e globs (routes.ts, a constants table) is
# not coverage either, however literally it names the route
assert routes['/billing/settings']['covered'] is False, routes['/billing/settings']
assert routes['/billing/invoices']['actions'] == [{'action': 'create-invoice', 'endpoint': 'POST /api/invoices/'}], routes['/billing/invoices']['actions']
gaps = [(g['module'], g['path']) for g in data['route_gaps']]
assert gaps == [('billing', '/billing/settings')], gaps
assert data['totals']['routes'] == 3, data['totals']
assert data['totals']['routes_uncovered'] == 1, data['totals']
assert mods['people']['routes'] == [], mods['people']
assert data['unmapped_actions'] == [], data['unmapped_actions']
print('OK')
")"
[[ "$out" == "OK" ]] || fail "route shape/coverage: $out"

grep -q '/billing/settings' "$MD" || fail "markdown must name the uncovered route"
grep -q 'NO E2E SPEC' "$MD" || fail "markdown must flag the route with no reaching spec"
grep -q 'POST /api/invoices/' "$MD" || fail "markdown must show the endpoint an action calls"

# --- route matching: the boundary rules, against the forms real specs use ----
# Cases taken from the measured NS e2e corpus (plain literal, template literal
# with a ${} placeholder, query string) plus the two over-reporting traps: a
# prefix route and a `*/` comment terminator standing in for the root route.
out="$(python3 - "$SCRIPTS_DIR/coverage" <<'PYRX'
import sys
sys.path.insert(0, sys.argv[1])
import coverage_matrix as cm

BT = chr(96)
cases = [
    ("/people",             "goto('/people')",                             True),
    ("/people",             "goto('/people/create')",                      False),
    ("/people/:id/edit",    "goto(" + BT + "/people/${id}/edit" + BT + ")", True),
    ("/suppliers/invoices",
     "goto(" + BT + "${BASE_URL}/suppliers/invoices" + BT + ")",           True),
    ("/x/create",           "goto('/x/create?from=1')",                    True),
    ("/",                   "goto('/')",                                   True),
    ("/",                   "   */",                                       False),
    ("/",                   "const r = a / b",                             False),
    # a Vite alias import is not a visit (#37): `@/login` names a src folder
    ("/login",              "import { login } from '@/login'",             False),
    ("/login",              "import { login } from '~/login'",             False),
]
for path, text, want in cases:
    got = bool(cm.route_regex(path).search(text))
    assert got == want, (path, text, want, got)
print("OK")
PYRX
)"
[[ "$out" == "OK" ]] || fail "route_regex boundary rules: $out"

# --- surface_files counts glob-shaped keys only, and still sums a v1 map -----
# The trap in the schema change: a URL route is not a file path, so counting the
# typed `routes` list would report zero surface files for exactly the modules
# that adopt the new shape.
sf_v2="$(python3 -c "
import json
m = {x['id']: x for x in json.load(open('$JSON'))['modules']}
print(m['billing']['surface_files'])
")"
[[ "$sf_v2" == "1" ]] || fail "v2 surface_files should count only the endpoints glob (got $sf_v2)"

MAP="$WS/.context/audits/test-coverage/module-map.json"
cp "$MAP" "$WS/map-v2.json"
python3 - "$MAP" <<'PYV1'
import json, sys
m = json.load(open(sys.argv[1]))
m['version'] = 1
for mod in m['modules']:
    if mod['id'] == 'billing':
        mod['surfaces'] = {
            'routes': ['frontend/src/billing/**'],
            'endpoints': ['backend/apps/billing/views.py'],
            'actions': [{'route': '/people', 'action': 'create', 'endpoint': 'POST /api/people'}],
        }
json.dump(m, open(sys.argv[1], 'w'), indent=2)
PYV1
python3 "$SCRIPTS_DIR/coverage/coverage_matrix.py" "$WS" >/dev/null \
  || fail "coverage_matrix.py exited non-zero on a v1 map"
# an action on a v1 map has no declared route to sit under; the JSON reports it
# and the markdown must too (#49: the section was nested under the route board)
grep -q 'undeclared route' "$MD" || fail "v1 map: markdown must carry the undeclared-route section"
grep -q '/people' "$MD" || fail "v1 map: markdown must name the orphan action's route"
out="$(python3 -c "
import json
data = json.load(open('$JSON'))
m = {x['id']: x for x in data['modules']}
assert m['billing']['surface_files'] == 2, m['billing']['surface_files']
assert m['billing']['has_surfaces'] is True, m['billing']
assert m['billing']['routes'] == [], m['billing']['routes']
assert data['schema'] == 'coverage-matrix/2', data['schema']
print('OK')
")"
[[ "$out" == "OK" ]] || fail "v1 map compatibility (surface_files must stay 2): $out"
cp "$WS/map-v2.json" "$MAP"
python3 "$SCRIPTS_DIR/coverage/coverage_matrix.py" "$WS" >/dev/null \
  || fail "coverage_matrix.py exited non-zero after restoring the v2 map"

# --- idempotent: second run rewrites cleanly, no duplicate sections ---
python3 "$SCRIPTS_DIR/coverage/coverage_matrix.py" "$WS" >/dev/null \
  || fail "coverage_matrix.py exited non-zero on second run"
header_count="$(grep -c '^# Coverage Matrix$' "$MD")"
[[ "$header_count" -eq 1 ]] || fail "second run produced duplicate/missing '# Coverage Matrix' header (count=$header_count)"
totals_count="$(grep -c '^## Totals$' "$MD")"
[[ "$totals_count" -eq 1 ]] || fail "second run produced duplicate/missing '## Totals' section (count=$totals_count)"
billing_count="$(grep -c '^| billing |' "$MD")"
[[ "$billing_count" -eq 1 ]] || fail "second run duplicated the billing row (count=$billing_count)"

# --- hand-edit is overwritten on regeneration ---
printf '\nHAND EDITED — SHOULD NOT SURVIVE\n' >> "$MD"
python3 "$SCRIPTS_DIR/coverage/coverage_matrix.py" "$WS" >/dev/null \
  || fail "coverage_matrix.py exited non-zero on regeneration after hand-edit"
grep -q 'HAND EDITED' "$MD" && fail "hand-edit survived regeneration"

# --- unmapped section: lists real test files, never __init__.py packaging
#     stubs (regression: field test 2026-07-05 — NS matrix listed dozens of
#     __init__.py files under tests/ dirs as "unmapped test files") ---
mkdir -p "$WS/backend/apps/other/tests"
touch "$WS/backend/apps/other/tests/__init__.py"
printf 'def test_z():\n    assert True\n' > "$WS/backend/apps/other/tests/test_z.py"
git -C "$WS/backend" add -A >/dev/null
git -C "$WS/backend" commit -q -m "unmapped test app"
python3 "$SCRIPTS_DIR/coverage/coverage_matrix.py" "$WS" >/dev/null \
  || fail "coverage_matrix.py exited non-zero with unmapped test app"
grep -q 'backend/apps/other/tests/test_z.py' "$MD" \
  || fail "unmapped real test file should be listed"
grep -q 'backend/apps/other/tests/__init__.py' "$MD" \
  && fail "__init__.py must not be listed as an unmapped test file"

# --- a third test kind (keys are open-ended per 06-test-coverage.md) is a
# module's test file too: never listed as unmapped (#48) ---
mkdir -p "$WS/backend/apps/billing/integration"
printf 'def test_i():\n    assert True\n' > "$WS/backend/apps/billing/integration/test_i.py"
git -C "$WS/backend" add -A >/dev/null
git -C "$WS/backend" commit -q -m "integration test"
python3 - "$MAP" <<'PYK'
import json, sys
m = json.load(open(sys.argv[1]))
for mod in m['modules']:
    if mod['id'] == 'billing':
        mod['tests']['integration'] = ['backend/apps/billing/integration/**']
json.dump(m, open(sys.argv[1], 'w'), indent=2)
PYK
python3 "$SCRIPTS_DIR/coverage/coverage_matrix.py" "$WS" >/dev/null \
  || fail "coverage_matrix.py exited non-zero with an integration kind"
out="$(python3 -c "
import json
data = json.load(open('$JSON'))
assert 'backend/apps/billing/integration/test_i.py' not in data['unmapped_test_files'], data['unmapped_test_files']
assert 'backend/apps/other/tests/test_z.py' in data['unmapped_test_files'], data['unmapped_test_files']
print('OK')
")"
[[ "$out" == "OK" ]] || fail "third test kind must not be reported as unmapped: $out"

# --- --out: read the map from, and write outputs to, an external dir --------
# BL-204: a read-only field run against a workspace you may not write into.
WS2="$(bash "$TESTS_DIR/fixtures/coverage-workspace.sh")"
OUT2="$(mktemp -d)"
cp "$WS2/.context/audits/test-coverage/module-map.json" "$OUT2/"
rm -rf "$WS2/.context"          # the target workspace carries no .context at all
python3 "$SCRIPTS_DIR/coverage/coverage_matrix.py" "$WS2" --out "$OUT2" >/dev/null \
  || fail "--out run exited non-zero"
[[ -f "$OUT2/coverage-matrix.md" && -f "$OUT2/coverage-matrix.json" ]] \
  || fail "--out must write both outputs into the --out dir"
[[ -e "$WS2/.context" ]] && fail "--out run must not create .context in the target workspace"
rm -rf "$WS2" "$OUT2"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — coverage-matrix generation, billing/people rows, json shape, idempotency, hand-edit overwrite, unmapped noise filter"
