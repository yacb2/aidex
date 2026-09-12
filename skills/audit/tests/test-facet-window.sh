#!/usr/bin/env bash
# test-facet-window.sh — pins the facet window: `extract.py --until` and the
# coverage ledger `facet_coverage.py` (usage-retro-facets, phase 2).
#
# A facet run reads an explicit [since, until) window and records it in a ledger;
# the weekly cursor is a watermark and must never be read or written by a facet
# run. The two failures this file guards: an upper bound that advances the cursor
# past unread records, and a ledger whose absence or corruption silently picks a
# window (the cursor's original defect, one file over).
#
# Run with: bash skills/audit/tests/test-facet-window.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
EXTRACT="$HERE/../scripts/usage-retro/extract.py"
COVERAGE="$HERE/../scripts/usage-retro/facet_coverage.py"

PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }

TX="$(bash "$HERE/fixtures/extract-corpus.sh")"
OUT="$(mktemp -d)"
trap 'rm -rf "$TX" "$OUT"' EXIT
[[ -n "$TX" && -d "$TX" ]] || { bad "fixture corpus did not build"; exit 1; }

count() { sed -nE 's/^records: ([0-9]+).*/\1/p' <<<"$1"; }

# (1) the upper bound excludes a later record ---------------------------------
# The corpus spans 2026-01-01..2026-01-08; until 2026-01-04 keeps s1/s2/s3 only.
out_all="$(python3 "$EXTRACT" --out "$OUT/all.jsonl" --since 3650d --transcripts-root "$TX" 2>&1)"
out_win="$(python3 "$EXTRACT" --out "$OUT/win.jsonl" --since 2026-01-01 --until 2026-01-04 \
                   --transcripts-root "$TX" 2>&1)"; rc=$?
n_all="$(count "$out_all")"; n_win="$(count "$out_win")"
if [[ $rc -eq 0 && "${n_all:-0}" -gt 0 && "${n_win:-0}" -gt 0 && "$n_win" -lt "$n_all" ]] \
   && ! grep -q "fase dos" "$OUT/win.jsonl" && grep -q "mide el recall" "$OUT/win.jsonl"; then
  ok "--until excludes records at or after the bound ($n_win of $n_all kept)"
else
  bad "--until did not bound the window: rc=$rc all=$n_all win=$n_win: $out_win"
fi
grep -qE '^records:.*until 2026-01-04' <<<"$out_win" \
  && ok "the summary prints both bounds" \
  || bad "the window label does not name the upper bound: $(grep '^records:' <<<"$out_win")"

# (2) --until with --cursor is refused, and the cursor is untouched -----------
CUR="$OUT/cursor.json"
printf '{"through": "2016-01-01T00:00:00+00:00"}' > "$CUR"
before="$(shasum "$CUR")"
out_c="$(python3 "$EXTRACT" --out "$OUT/c.jsonl" --cursor "$CUR" --until 2026-01-04 \
                 --transcripts-root "$TX" 2>&1)"; rc_c=$?
[[ $rc_c -ne 0 && "$out_c" == *"ERROR"*"--until"*"--cursor"* ]] \
  && ok "--until + --cursor is refused with an ERROR naming both flags" \
  || bad "--until + --cursor was not refused (rc=$rc_c): $out_c"
[[ "$(shasum "$CUR")" == "$before" ]] \
  && ok "the cursor file is byte-identical after the refusal" \
  || bad "the refused run rewrote the cursor"

# (3) the default window comes from an existing ledger ------------------------
LEDGER="$OUT/coverage.json"
python3 "$COVERAGE" record --facet artifacts --ledger "$LEDGER" \
        --from 2026-07-13T00:00:00Z --to 2026-08-01T00:00:00Z --run 2026-08-01-usage-retro-artifacts >/dev/null
win="$(python3 "$COVERAGE" window --facet artifacts --ledger "$LEDGER")"
[[ "$win" == "2026-08-01T00:00:00+00:00 "*"resumed from coverage ledger" ]] \
  && ok "default window starts at the end of the last covered window" \
  || bad "default window is not the ledger's last 'to': $win"
win_none="$(python3 "$COVERAGE" window --facet backlog --ledger "$LEDGER")"
[[ "$win_none" == *"DEFAULT last 60d"* ]] \
  && ok "a facet with no coverage falls back to 60d and says so" \
  || bad "the uncovered facet did not announce its default: $win_none"
gap="$(python3 "$COVERAGE" gap --facet backlog --ledger "$LEDGER")"
[[ "$gap" == "never" ]] && ok "gap reports 'never' for an uncovered facet" \
                        || bad "gap for an uncovered facet: $gap"

# (4) record appends without reordering ---------------------------------------
python3 "$COVERAGE" record --facet artifacts --ledger "$LEDGER" \
        --from 2026-06-01T00:00:00Z --to 2026-06-15T00:00:00Z --run 2026-09-11-usage-retro-artifacts >/dev/null
runs="$(python3 -c '
import json,sys; print(" ".join(s["run"] for s in json.load(open(sys.argv[1]))["artifacts"]))' "$LEDGER")"
[[ "$runs" == "2026-08-01-usage-retro-artifacts 2026-09-11-usage-retro-artifacts" ]] \
  && ok "record appends in call order, never sorts" \
  || bad "ledger order changed: $runs"
win2="$(python3 "$COVERAGE" window --facet artifacts --ledger "$LEDGER")"
[[ "$win2" == "2026-08-01T00:00:00+00:00 "* ]] \
  && ok "the default window uses the LATEST 'to', not the last appended" \
  || bad "an older backfill window moved the default start: $win2"
[[ "$(ls "$OUT" | grep -c cursor)" == "1" ]] \
  && ok "the ledger script never touched or created a cursor file" \
  || bad "a cursor file appeared or vanished: $(ls "$OUT")"

# (5) an unreadable ledger is a hard error ------------------------------------
printf '{"artifacts": [' > "$LEDGER"
before_l="$(shasum "$LEDGER")"
for cmd in "window" "gap" "record --from 2026-01-01 --to 2026-01-02 --run r"; do
  out_e="$(python3 "$COVERAGE" $cmd --facet artifacts --ledger "$LEDGER" 2>&1)"; rc_e=$?
  [[ $rc_e -ne 0 && "$out_e" == *"ERROR"*"ledger"* ]] \
    && ok "an unreadable ledger is refused by '${cmd%% *}'" \
    || bad "'${cmd%% *}' on a corrupt ledger exited $rc_e: $out_e"
done
[[ "$(shasum "$LEDGER")" == "$before_l" ]] \
  && ok "the corrupt ledger is not rewritten" \
  || bad "the corrupt ledger was overwritten"

echo
echo "facet window: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
