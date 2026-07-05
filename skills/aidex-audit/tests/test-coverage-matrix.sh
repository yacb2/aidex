#!/usr/bin/env bash
# test-coverage-matrix.sh — coverage_matrix.py against the coverage-workspace
# fixture (house pattern, same assert style as test-coverage-lib.sh): matrix
# file exists with GENERATED header; billing row shows 1 e2e spec / 2 e2e
# tests / 1 unit file / 1 unit test; people row shows NO TESTS;
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
  exit !($4 == "1" && $5 == "1" && $6 == "1" && $7 == "2")
}' || fail "billing row counts wrong (expected unit files=1 unit tests=1 e2e specs=1 e2e tests=2): $billing_row"

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
assert len(data['modules']) == 2, data['modules']
print('OK')
")"
[[ "$out" == "OK" ]] || fail "coverage-matrix.json parse/shape: $out"

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

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — coverage-matrix generation, billing/people rows, json shape, idempotency, hand-edit overwrite, unmapped noise filter"
