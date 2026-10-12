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

# (6) an unparseable --since is refused, never swallowed (audit-c15) -----------
# resolve_cutoff fell through to the cursor or the 7-day default on a typo, while
# --until refused the same input; with --cursor the run then advanced the cursor.
CUR6="$OUT/cursor6.json"
printf '{"through": "2026-01-02T00:00:00+00:00"}' > "$CUR6"
before6="$(shasum "$CUR6")"
out_s="$(python3 "$EXTRACT" --out "$OUT/s.jsonl" --cursor "$CUR6" --since 2026/08/01 \
                 --transcripts-root "$TX" 2>&1)"; rc_s=$?
[[ $rc_s -ne 0 && "$out_s" == *"ERROR"*"--since"* ]] \
  && ok "an unparseable --since is refused with an ERROR naming the flag" \
  || bad "--since 2026/08/01 was accepted (rc=$rc_s): $out_s"
[[ "$(shasum "$CUR6")" == "$before6" ]] \
  && ok "the cursor is untouched by the refused --since" \
  || bad "the refused --since rewrote the cursor"

# Synthetic one-session transcripts for (7) and (8): human prompts carry origin.kind
# like a real transcript so prompt_kinds admits them.
mk_tx() {  # dir — one session: P1 old, skill fire, P2 old, P3 in window
  mkdir -p "$1/-Users-user-Documents-projects-demo-ws"
  python3 - "$1/-Users-user-Documents-projects-demo-ws/w1.jsonl" <<'PYW'
import json, sys
def user(ts, text):
    return {"type": "user", "timestamp": ts, "origin": {"kind": "human"},
            "message": {"content": text}}
def skill(ts, name):
    return {"type": "assistant", "timestamp": ts, "message": {"content": [
        {"type": "tool_use", "name": "Skill", "id": "t" + ts, "input": {"skill": name}}]}}
rows = [user("2026-01-01T10:00:00Z", "primer prompt viejo de la sesion"),
        skill("2026-01-01T10:01:00Z", "aidex:artifact"),
        user("2026-01-01T11:00:00Z", "segundo prompt viejo de la sesion"),
        user("2026-02-01T10:00:00Z", "tercer prompt dentro de la ventana")]
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PYW
}

# (7) a skipped prompt resets the adjacency, so the first in-window prompt does not
#     inherit an out-of-window prompt's Skills (audit-c07) -----------------------
TX7="$(mktemp -d)"; mk_tx "$TX7"
python3 "$EXTRACT" --out "$OUT/p7.jsonl" --since 2026-01-15 --transcripts-root "$TX7" >/dev/null 2>&1
python3 - "$OUT/p7.jsonl" <<'PY7' && ok "the first in-window prompt carries no stale prior_skills" \
  || bad "stale prior_skills leaked into the first in-window prompt: $(cat "$OUT/p7.jsonl")"
import json, sys
r = [json.loads(l) for l in open(sys.argv[1])]
assert len(r) == 1 and "tercer" in r[0]["prompt"], r
assert r[0]["prior_skills"] == [], r[0]["prior_skills"]
PY7
rm -rf "$TX7"

# (8) the cursor watermark is exclusive: the last prompt of run 1 is not run 2's
#     first (audit-c44) ---------------------------------------------------------
TX8="$(mktemp -d)"; mk_tx "$TX8"; CUR8="$OUT/cursor8.json"
python3 "$EXTRACT" --out "$OUT/r1.jsonl" --all --cursor "$CUR8" --transcripts-root "$TX8" >/dev/null 2>&1
out_r2="$(python3 "$EXTRACT" --out "$OUT/r2.jsonl" --cursor "$CUR8" --transcripts-root "$TX8" 2>&1)"
[[ "$(count "$out_r2")" == "0" ]] \
  && ok "a resumed run does not re-extract the prompt the cursor stands on" \
  || bad "the cursor's last prompt was extracted twice: $out_r2"
# a LATER prompt must still come through, and the cursor must advance to it
python3 - "$TX8/-Users-user-Documents-projects-demo-ws/w1.jsonl" <<'PY8'
import json, sys
open(sys.argv[1], "a").write(json.dumps({"type": "user", "timestamp": "2026-03-01T10:00:00Z",
    "origin": {"kind": "human"}, "message": {"content": "cuarto prompt posterior al cursor"}}) + "\n")
PY8
out_r3="$(python3 "$EXTRACT" --out "$OUT/r3.jsonl" --cursor "$CUR8" --transcripts-root "$TX8" 2>&1)"
thru="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["through"])' "$CUR8")"
[[ "$(count "$out_r3")" == "1" && "$thru" == "2026-03-01T10:00:00+00:00" ]] \
  && ok "a prompt after the cursor is extracted and the cursor advances to it" \
  || bad "resume past the watermark: through=$thru $out_r3"
# --since stays inclusive: the third prompt sits exactly on the bound
out_in="$(python3 "$EXTRACT" --out "$OUT/in.jsonl" --since 2026-02-01T10:00:00Z --until 2026-02-02 \
                 --transcripts-root "$TX8" 2>&1)"
[[ "$(count "$out_in")" == "1" ]] \
  && ok "--since includes a prompt exactly on the bound" \
  || bad "--since excluded the prompt on the bound: $out_in"
rm -rf "$TX8"

# (9) concurrent ledger writes lose no window, and leave no partial file (audit-c43)
LED9="$OUT/led9/coverage.json"; mkdir -p "$OUT/led9"
for i in $(seq 1 16); do
  python3 "$COVERAGE" record --facet artifacts --ledger "$LED9" \
          --from 2026-01-01T00:00:00Z --to 2026-01-02T00:00:00Z --run "run$i" >/dev/null 2>&1 &
done
wait
n9="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["artifacts"]))' "$LED9" 2>&1)"
[[ "$n9" == "16" ]] \
  && ok "16 concurrent record calls keep all 16 windows" \
  || bad "concurrent record lost windows: $n9 of 16"
[[ "$(ls "$OUT/led9")" == "coverage.json" ]] \
  && ok "record leaves only the ledger beside itself (no lock or tmp file)" \
  || bad "stray files beside the ledger: $(ls "$OUT/led9")"

echo
echo "facet window: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
