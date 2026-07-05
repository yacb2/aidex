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

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — affected-tests: module+hints, unmapped, clean tree, partial --since, test-file attribution"
