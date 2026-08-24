#!/usr/bin/env bash
# test-coverage-sweep.sh — coverage_sweep.py against the coverage-workspace
# fixture (house pattern, same assert style as test-coverage-matrix.sh).
# Scenarios:
#   (a) fixture without drift -> billing drift 0, no RE-RUN lines
#   (b) matrix baseline + drift -> billing RE-RUN RECOMMENDED, src=4 test=0 +1 src
#   (c) no coverage-matrix.json -> warning line, still exits 0
#   (d) --since 1970-01-01 overrides the baseline
#   (e) multi-repo: drift sums src commits across backend AND frontend
#
# Run with: bash skills/aidex-audit/tests/test-coverage-sweep.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"
FIXTURE="$TESTS_DIR/fixtures/coverage-workspace.sh"
SWEEP="$SCRIPTS_DIR/coverage/coverage_sweep.py"
MATRIX="$SCRIPTS_DIR/coverage/coverage_matrix.py"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# Columns are joined by 2+ spaces (single-space values like "+1 src" stay intact).
field() { awk -F'  +' -v r="$1" -v c="$2" '$1==r{print $c}'; }

# ---------------------------------------------------------------------------
# (a) fixture without drift: billing drift 0, no RE-RUN lines
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 "$MATRIX" "$WS" >/dev/null || fail "(a) matrix generation failed"
out_a="$(python3 "$SWEEP" "$WS" 2>/dev/null)"
[[ "$(echo "$out_a" | field billing 5)" == "0" ]] \
  || fail "(a) billing drift should be 0 without drift: $(echo "$out_a" | grep billing)"
echo "$out_a" | grep -q 'RE-RUN RECOMMENDED' \
  && fail "(a) no module should be flagged without drift"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (b) matrix baseline, then apply drift: billing flagged, src=4 test=0 +1 src
#     (matrix is snapshot BEFORE drift so the surface delta and --since window
#      are real; drift commits are future-dated by the fixture)
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 "$MATRIX" "$WS" >/dev/null || fail "(b) matrix generation failed"
bash "$FIXTURE" --apply-drift "$WS" || fail "(b) apply-drift failed"
out_b="$(python3 "$SWEEP" "$WS" 2>/dev/null)"
[[ "$(echo "$out_b" | field billing 6)" == "RE-RUN RECOMMENDED" ]] \
  || fail "(b) billing should be RE-RUN RECOMMENDED: $(echo "$out_b" | grep billing)"
[[ "$(echo "$out_b" | field billing 2)" == "4" ]] \
  || fail "(b) billing src_commits should be 4 (3 backend + 1 frontend): $(echo "$out_b" | grep billing)"
[[ "$(echo "$out_b" | field billing 3)" == "0" ]] \
  || fail "(b) billing test_commits should be 0: $(echo "$out_b" | grep billing)"
[[ "$(echo "$out_b" | field billing 4)" == "+1 src" ]] \
  || fail "(b) billing surface delta should be '+1 src': $(echo "$out_b" | grep billing)"
echo "$out_b" | grep -q 'baseline: coverage-matrix.json' \
  || fail "(b) baseline should be coverage-matrix.json: $out_b"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (c) no coverage-matrix.json: warning line to stderr, still exits 0
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"  # no matrix generated
err_c="$(python3 "$SWEEP" "$WS" 2>&1 >/dev/null)"
rc=$?
[[ $rc -eq 0 ]] || fail "(c) sweep must exit 0 even with no matrix (got $rc)"
echo "$err_c" | grep -q 'no baseline' \
  || fail "(c) expected a 'no baseline' warning line: $err_c"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (d) --since 1970-01-01 overrides the baseline (counts ALL history incl.
#     baseline commits) even when a matrix exists
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 "$MATRIX" "$WS" >/dev/null || fail "(d) matrix generation failed"
out_d="$(python3 "$SWEEP" "$WS" --since 1970-01-01 2>/dev/null)"
echo "$out_d" | grep -q 'since 1970-01-01 (baseline: --since flag)' \
  || fail "(d) --since flag should override matrix baseline: $out_d"
# With the matrix baseline (now) instead, billing src_commits would be 0; the
# 1970 override must include the baseline commits (>=1).
billing_src_d="$(echo "$out_d" | field billing 2)"
[[ "${billing_src_d:-0}" -ge 1 ]] \
  || fail "(d) --since 1970 should count baseline commits: $(echo "$out_d" | grep billing)"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (e) multi-repo: src commits are summed across backend AND frontend for the
#     same module. Apply the standard drift (3 backend + 1 frontend) plus one
#     extra frontend src commit, so backend=3, frontend=2, sum must be 5. A
#     single-repo implementation would report 3 (or 2), never 5.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 "$MATRIX" "$WS" >/dev/null || fail "(e) matrix generation failed"
bash "$FIXTURE" --apply-drift "$WS" || fail "(e) apply-drift failed"
# one more frontend billing-src commit (future-dated to stay after the matrix)
printf '\nextra\n' >> "$WS/frontend/src/billing/Form.vue"
git -C "$WS/frontend" add -A
GIT_AUTHOR_DATE="2099-06-01T00:00:00" GIT_COMMITTER_DATE="2099-06-01T00:00:00" \
  git -C "$WS/frontend" commit -q -m "billing: touch Form.vue (no tests)"
out_e="$(python3 "$SWEEP" "$WS" 2>/dev/null)"
[[ "$(echo "$out_e" | field billing 2)" == "5" ]] \
  || fail "(e) billing src_commits should sum both repos to 5: $(echo "$out_e" | grep billing)"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (f) CLI hygiene: a malformed --since (#47) and an unknown flag (#60) are
#     usage errors, never a legitimate-looking table; a missing module-map is
#     a hard error with exit 2, distinct from config_check's exit 1 = drift (#59)
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
out_f="$(python3 "$SWEEP" "$WS" --since garbage 2>/dev/null)"; rc=$?
[[ $rc -ne 0 ]] || fail "(f) --since garbage must exit non-zero (got $rc)"
echo "$out_f" | grep -q 'COVERAGE SWEEP' && fail "(f) --since garbage must not print a table: $out_f"
out_f2="$(python3 "$SWEEP" "$WS" --sinc 2020-01-01 2>/dev/null)"; rc=$?
[[ $rc -ne 0 ]] || fail "(f) unknown flag --sinc must exit non-zero (got $rc)"
echo "$out_f2" | grep -q 'COVERAGE SWEEP' && fail "(f) unknown flag must not print a table: $out_f2"
rm -rf "$WS"
NOMAP="$(mktemp -d)"
git -C "$NOMAP" init -q
err_f="$(python3 "$SWEEP" "$NOMAP" 2>&1 >/dev/null)"; rc=$?
[[ $rc -eq 2 ]] || fail "(f) missing module-map must exit 2 (got $rc): $err_f"
echo "$err_f" | grep -q 'ERROR:' || fail "(f) missing module-map must say ERROR: on stderr: $err_f"
rm -rf "$NOMAP"

# ---------------------------------------------------------------------------
# (g) a third test kind counts as test commits (#48): a commit touching only
#     an `integration` test must not read as src-only drift
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
python3 "$MATRIX" "$WS" >/dev/null || fail "(g) matrix generation failed"
python3 - "$WS/.context/audits/test-coverage/module-map.json" <<'PYK'
import json, sys
m = json.load(open(sys.argv[1]))
for mod in m['modules']:
    if mod['id'] == 'billing':
        mod['tests']['integration'] = ['backend/apps/billing/integration/**']
json.dump(m, open(sys.argv[1], 'w'), indent=2)
PYK
mkdir -p "$WS/backend/apps/billing/integration"
printf 'def test_i():\n    assert True\n' > "$WS/backend/apps/billing/integration/test_i.py"
git -C "$WS/backend" add -A
GIT_AUTHOR_DATE="2099-01-01T00:00:00" GIT_COMMITTER_DATE="2099-01-01T00:00:00" \
  git -C "$WS/backend" commit -q -m "billing: integration test"
out_g="$(python3 "$SWEEP" "$WS" 2>/dev/null)"
[[ "$(echo "$out_g" | field billing 3)" == "1" ]] \
  || fail "(g) billing test_commits should count the integration kind (1): $(echo "$out_g" | grep billing)"
rm -rf "$WS"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — coverage-sweep drift: no-drift baseline, flagged RE-RUN, no-matrix warning, --since override, multi-repo sum, CLI hygiene, open-ended test kinds"
