#!/usr/bin/env bash
# test-estimate-calibration.sh — the estimate-vs-realized-effort read (BL-131),
# against the usage-retro corpus fixture.
#
# The item's two scope guards are the interesting assertions here, because this
# read sits next to three items that all shipped mechanical gates and the obvious
# mistake is to build a fourth:
#   - it must never gate anything (rules/autonomy.md: a run does not stop for a signal)
#   - it must never print a single accuracy number (that would average the flat
#     median together with the spreading tail and hide the whole finding)
#
# Scenarios:
#   (a) exclusions are counted, never silently dropped
#   (b) only WORKING spans count as effort (the strict-span rule, BL-132)
#   (c) each realized-effort table reports median AND p90 AND max
#   (d) tail risk is reported separately from the per-bucket medians
#   (e) no single accuracy/score number is printed
#   (f) exit 0 even when nothing scores — a read never gates
#   (g) --project restricts the population
#
# Run with: bash skills/aidex-backlog/tests/test-estimate-calibration.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CAL="$TESTS_DIR/../scripts/estimate-calibration.py"
FIXTURE="$TESTS_DIR/../../aidex-audit/tests/fixtures/usage-retro-corpus.sh"
MINER="$TESTS_DIR/../../aidex-audit/scripts/usage-retro/mine_items.py"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

read -r PROJ TX <<< "$(bash "$FIXTURE")"
OUT="$(mktemp -d)"
cleanup() { rm -rf "$PROJ" "$TX" "$OUT"; }
trap cleanup EXIT

python3 "$MINER" --projects-root "$PROJ" --transcripts-root "$TX" \
  --out "$OUT" --min-mentions 1 >/dev/null 2>&1

out="$(python3 "$CAL" --from "$OUT" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "(setup) calibration should exit 0 (got $rc): $out"

# ---------------------------------------------------------------------------
# (a) The fixture holds 4 items: alpha (done/S, worked), beta (done/S, named only
#     in a tool_result so it has no attributed work), gamma (open/M) and delta
#     (done/L, worked). A calibration over a quietly-filtered population is how a
#     flat scale gets mistaken for a well-calibrated one, so every drop is counted.
# ---------------------------------------------------------------------------
echo "$out" | grep -q '2 closed items with an estimate and measurable work' \
  || fail "(a) expected 2 scored items: $out"
echo "$out" | grep -q 'excluded: 1 not closed, 0 no estimate, 1 no measurable work' \
  || fail "(a) exclusions should be itemised and counted: $out"

# ---------------------------------------------------------------------------
# (b) gamma has 2 edits and no prompt-mention, so its span is NOT working. It is
#     also open, so it must not score — but the effort join must ignore it too.
#     delta's 3 edits ARE working and must show up as 3.
# ---------------------------------------------------------------------------
echo "$out" | grep -qE '^ +L +1 +3 +3 +3$' \
  || fail "(b) delta (L) should show 3 realized edits from its working span: $out"

# ---------------------------------------------------------------------------
# (c) median alone hides the finding; every table carries the spread too.
# ---------------------------------------------------------------------------
n_tables="$(echo "$out" | grep -c 'estimate.*n.*median.*p90.*max')"
[[ "$n_tables" -eq 3 ]] \
  || fail "(c) expected 3 effort tables with median/p90/max, got $n_tables: $out"

# ---------------------------------------------------------------------------
# (d) the tail is the other half of the finding and a per-bucket median cannot
#     show it, so it is reported on its own.
# ---------------------------------------------------------------------------
echo "$out" | grep -q 'TAIL RISK' \
  || fail "(d) expected a separate tail-risk section: $out"
echo "$out" | grep -q 'top decile absorbs.*of all edits' \
  || fail "(d) tail risk should report the top decile's share: $out"

# ---------------------------------------------------------------------------
# (e) SCOPE GUARD. No single accuracy/score/grade number — averaging the flat
#     middle with the spreading tail would hide exactly what was measured.
# ---------------------------------------------------------------------------
echo "$out" | grep -qiE 'accuracy: *[0-9]|score: *[0-9]|calibration score|[0-9]+% accurate' \
  && fail "(e) a single accuracy number must never be printed: $out"
echo "$out" | grep -q 'No single' \
  || fail "(e) the report should say why no single number is given: $out"

# ---------------------------------------------------------------------------
# (f) SCOPE GUARD. A read gates nothing. Even with an empty population it must
#     exit 0 — a non-zero exit here is what would turn it into a mid-run stop.
# ---------------------------------------------------------------------------
EMPTY="$(mktemp -d)"
printf '%s\n' '{"project":"x","slug":"y","status":"open","estimate":"","kind":"backlog"}' \
  > "$EMPTY/items.jsonl"
: > "$EMPTY/spans.jsonl"
out_f="$(python3 "$CAL" --from "$EMPTY" 2>&1)"; rc_f=$?
rm -rf "$EMPTY"
[[ $rc_f -eq 0 ]] || fail "(f) an empty population must still exit 0 (got $rc_f)"
echo "$out_f" | grep -q 'Not a finding' \
  || fail "(f) an empty result should not read as a finding: $out_f"

# ---------------------------------------------------------------------------
# (g) --project restricts the population rather than being ignored.
# ---------------------------------------------------------------------------
out_g="$(python3 "$CAL" --from "$OUT" --project nonexistent_ws 2>&1)"; rc_g=$?
[[ $rc_g -eq 0 ]] || fail "(g) an unmatched --project must still exit 0 (got $rc_g)"
echo "$out_g" | grep -q 'corpus: 0 items' \
  || fail "(g) --project is not restricting the population: $out_g"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — estimate-calibration: exclusions counted, working-spans-only effort, median+p90+max per bucket, tail reported separately, no single accuracy number, exit 0 always, --project honoured"
