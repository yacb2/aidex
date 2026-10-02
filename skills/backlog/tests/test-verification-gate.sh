#!/usr/bin/env bash
# test-verification-gate.sh — close-item.sh --sweep refuses `done` without proof.
#
# The refusal is the point, not a stronger warning: the warning is what close-item had,
# and its measured adoption is the 2.2% number. Every refusal cell asserts exit 2 AND that
# the file is byte-identical and still in the active folder — a refusal that mutates is a
# half-close, which is worse than either outcome.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.context/backlog"; cd "$TMP/p"
reg() { bash "$SCRIPTS/register-item.sh" --origin manual "$@" 2>/dev/null; }
idof() { awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$1"; }
add_row() { # add_row <file> <kind> <what> <proof>
  printf '| %s | %s | %s |\n' "$2" "$3" "$4" > "$TMP/row"
  awk -v row="$(cat "$TMP/row")" '{print} /^\|---\|---\|---\|$/ && !done {print row; done=1}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}
refused() { # refused <label> <id> <file> <expected message fragment>
  local before rc; before="$(cat "$3")"
  bash "$SCRIPTS/close-item.sh" "$2" --sweep --no-index >/dev/null 2>"$TMP/err"; rc=$?
  [[ $rc -eq 0 ]] && { bad "$1: closed"; return; }
  [[ $rc -eq 2 ]] && grep -q "$4" "$TMP/err" && ok "$1: exit 2 — $(grep -o "$4" "$TMP/err" | sed -n 1p)" || bad "$1: rc=$rc $(cat "$TMP/err")"
  [[ "$(cat "$3")" == "$before" && -f "$3" ]] && ok "$1: file unchanged, still active" || bad "$1: file mutated or moved"
}

echo "close-item.sh --sweep:"
# internal, no rows
A="$(reg --title "internal no proof")"; AID="$(idof "$A")"
refused "internal/no rows" "$AID" "$A" "no ## Verification rows"
add_row "$A" test "tests/test_gap.py::test_lane" ""
refused "internal/empty proof" "$AID" "$A" "empty proof cell"
# fill the empty cell in place — the proven row replaces the unproven one
sed -i.bak 's/| test | tests\/test_gap.py::test_lane |  |/| test | tests\/test_gap.py::test_lane | 3 passed |/' "$A" && rm -f "$A.bak"
OUT="$(bash "$SCRIPTS/close-item.sh" "$AID" --sweep --no-index 2>/dev/null)"; RC=$?
[[ $RC -eq 0 && -f "$OUT" && "$OUT" == */_archive/* ]] && ok "internal/proven test row closes and archives" || bad "internal proven: rc=$RC $OUT"
grep -q '^status: done' "$OUT" && ok "archived item is done" || bad "status not done"

# behaviour needs test AND e2e|smoke
B="$(reg --title "behaviour" --surface behaviour)"; BID="$(idof "$B")"
add_row "$B" test "tests/test_x.py" "2 passed"
refused "behaviour/test only" "$BID" "$B" "AND an"
add_row "$B" smoke "/editor renders the gap lane" "proofs/bl/gap.png"
bash "$SCRIPTS/close-item.sh" "$BID" --sweep --no-index >/dev/null 2>&1 && ok "behaviour/test+smoke closes" || bad "behaviour test+smoke refused"

# ui needs a smoke
U="$(reg --title "ui" --surface ui)"; UID_="$(idof "$U")"
add_row "$U" test "unit" "1 passed"
refused "ui/test only" "$UID_" "$U" "smoke"
add_row "$U" smoke "/settings at 390px" "proofs/bl/settings.png"
bash "$SCRIPTS/close-item.sh" "$UID_" --sweep --no-index >/dev/null 2>&1 && ok "ui/smoke closes" || bad "ui smoke refused"

# an owner row with an empty proof PARKS the item: exit 0, awaiting: owner, not done, not
# archived (owner's call 2026-08-27 — a closed-looking item gets archived by mistake)
O="$(reg --title "owner row" --surface internal)"; OID="$(idof "$O")"
add_row "$O" test "tests/test_o.py" "4 passed"
add_row "$O" owner "wording of the new toast" ""
OUT="$(bash "$SCRIPTS/close-item.sh" "$OID" --sweep --no-index 2>/dev/null)"; RC=$?
[[ $RC -eq 0 ]] && grep -q "^parked:" <<<"$OUT" && ok "owner row with empty proof parks (exit 0, says parked)" || bad "park: rc=$RC $OUT"
[[ -f "$O" ]] && grep -q '^awaiting: owner$' "$O" && grep -q '^status: open$' "$O" && ok "parked item stays active with awaiting: owner, status untouched" || bad "parked item state wrong"
bash "$SCRIPTS/register-item.sh" --reindex >/dev/null 2>&1
grep -q '^## Awaiting owner' .context/backlog/00-index.md && grep -q 'Awaiting owner:\*\* 1' .context/backlog/00-index.md && ok "index lists it under ## Awaiting owner, counted apart from Active" || bad "index section missing"
sed -i.bak 's/| owner | wording of the new toast |  |/| owner | wording of the new toast | fine — owner 2026-08-27 |/' "$O" && rm -f "$O.bak"
OUT="$(bash "$SCRIPTS/close-item.sh" "$OID" --sweep --no-index 2>/dev/null)"; RC=$?
[[ $RC -eq 0 && "$OUT" == */_archive/* ]] && ! grep -q '^awaiting:' "$OUT" && grep -q '^status: done' "$OUT" && ok "answered owner row: closes, archives, awaiting line dropped" || bad "answered close: rc=$RC $OUT"

# A proof cell that says the proof does NOT exist is not a proof (BL-641) and an owner
# cell that says the answer is still owed is not an answer (BL-656). The recognizer is a
# short phrase list, anchored, so a real proof that merely contains one of the words
# still counts — those boundary rows are the control half of this block.
NR="$(reg --title "negated smoke" --surface behaviour)"; NRID="$(idof "$NR")"
add_row "$NR" test "tests/test_x.py" "2 passed"
add_row "$NR" smoke "browser" "not run: no data in dev"
NEG='the proof says no proof exists: "'
refused "behaviour/smoke proof 'not run: ...'" "$NRID" "$NR" "$NEG"
for ph in "Not run: no data in dev" "no se corrió: sin datos en dev" "pending" "TBD" "TODO: run it on staging" \
          "deferred: the dev copy has no employee" "blocked: waits on plan chain-ledger" "skipped" \
          "NOT DONE, the sync is missing" "NOT delivered: the export"; do
  sed -i.bak "s/| smoke | browser | [^|]* |$/| smoke | browser | $ph |/" "$NR" && rm -f "$NR.bak"
  refused "behaviour/smoke proof '$ph'" "$NRID" "$NR" "$NEG"
done
# Decided trade-off (fail closed): a REAL proof that opens with one of these words is still
# refused — the author rewords it. Field cases: work_hours BL-283, BL-143.
for ph in "pending C PATCHed onto approved ... 400 se solapa" "Not run as a separate step: ... 2388 passed"; do
  sed -i.bak "s/| smoke | browser | [^|]* |$/| smoke | browser | $ph |/" "$NR" && rm -f "$NR.bak"
  refused "decided: real proof opening '$ph' is refused (reword it)" "$NRID" "$NR" "$NEG"
done
sed -i.bak 's/| smoke | browser | [^|]* |$/| smoke | browser | screenshot shots\/x.png |/' "$NR" && rm -f "$NR.bak"
OUT="$(bash "$SCRIPTS/close-item.sh" "$NRID" --sweep --no-index 2>/dev/null)"; RC=$?
[[ $RC -eq 0 && "$OUT" == */_archive/* ]] && ok "control: same row with 'screenshot shots/x.png' closes" || bad "control screenshot: rc=$RC $OUT"
# boundary: the listed words inside a real proof do not make it a placeholder
for real in "3 passed (test_pending_rows_park)" "shots/x.png — captured after not running CI" "todo verde: 12 passed" "pendientes 0, 5 passed" "tests/test_o.py::test_owner_unanswered 1 passed"; do
  R="$(reg --title "real proof" --surface internal)"; RID="$(idof "$R")"
  add_row "$R" test "tests/test_r.py" "$real"
  bash "$SCRIPTS/close-item.sh" "$RID" --sweep --no-index >/dev/null 2>"$TMP/err" && ok "real proof '$real' closes" || bad "real proof '$real' refused: $(cat "$TMP/err")"
done
# an owner cell holding a placeholder parks exactly like an empty one
for ph in "awaiting owner (chain ledger d10)" "pending: consultation Q6, unanswered" "consultation 2026-10-02 Q6, unanswered" "sin respuesta" "blocked: waits on plan chain-ledger"; do
  PO="$(reg --title "placeholder owner" --surface behaviour)"; POID="$(idof "$PO")"
  add_row "$PO" test "tests/test_x.py" "2 passed"
  add_row "$PO" smoke "/editor" "proofs/bl/editor.png"
  add_row "$PO" owner "wording of the toast" "$ph"
  OUT="$(bash "$SCRIPTS/close-item.sh" "$POID" --sweep --no-index 2>/dev/null)"; RC=$?
  [[ $RC -eq 0 ]] && grep -q "^parked:" <<<"$OUT" && [[ -f "$PO" ]] && grep -q '^awaiting: owner$' "$PO" && grep -q '^status: open$' "$PO" \
    && ok "owner proof '$ph' parks, not archived" || bad "owner placeholder '$ph': rc=$RC $OUT"
done
sed -i.bak 's/| owner | wording of the toast | [^|]* |$/| owner | wording of the toast | answered 2026-10-02, consultation Q6: yes |/' "$PO" && rm -f "$PO.bak"
OUT="$(bash "$SCRIPTS/close-item.sh" "$POID" --sweep --no-index 2>/dev/null)"; RC=$?
[[ $RC -eq 0 && "$OUT" == */_archive/* ]] && ! grep -q '^awaiting:' "$OUT" && grep -q '^status: done' "$OUT" && ok "owner proof 'answered 2026-10-02, consultation Q6: yes' closes" || bad "answered owner: rc=$RC $OUT"

# ops: no test surface — one proven row of any kind is the minimum
P="$(reg --title "ops" --surface ops)"; PID_="$(idof "$P")"
add_row "$P" owner "bucket decision" ""
OUT="$(bash "$SCRIPTS/close-item.sh" "$PID_" --sweep --no-index 2>"$TMP/err")"; RC=$?
[[ $RC -eq 2 ]] && grep -q "surface ops needs one proven row" "$TMP/err" && ok "ops/only an unanswered owner row: refused (nothing proven)" || bad "ops unproven: rc=$RC $(cat "$TMP/err")"
add_row "$P" smoke "check-worktree-isolation.sh --census" "proofs/bl/census.txt: 0 findings"
OUT="$(bash "$SCRIPTS/close-item.sh" "$PID_" --sweep --no-index 2>/dev/null)"; RC=$?
[[ $RC -eq 0 ]] && grep -q "^parked:" <<<"$OUT" && ok "ops/smoke proven + owner open: parked, not refused" || bad "ops parked: rc=$RC $OUT"

# unknown kind is refused
K="$(reg --title "bad kind")"; KID="$(idof "$K")"
add_row "$K" manual "clicked around" "yes"
refused "unknown kind" "$KID" "$K" "kind 'manual'"

# --sweep with --status dropped needs no proof
DR="$(reg --title "dropped")"; DRID="$(idof "$DR")"
bash "$SCRIPTS/close-item.sh" "$DRID" --sweep --status dropped --no-index >/dev/null 2>&1 && ok "dropped needs no proof in sweep mode" || bad "dropped refused"

# outside sweep mode nothing tightened: a bare item still closes (with the bug warning only)
N="$(reg --title "plain close" --type bug)"; NID="$(idof "$N")"
ERR="$(bash "$SCRIPTS/close-item.sh" "$NID" --no-index 2>&1 >/dev/null)"; RC=$?
[[ $RC -eq 0 && "$ERR" == *"no RED->GREEN proof"* ]] && ok "plain close unchanged: warns, still closes" || bad "plain close: rc=$RC $ERR"
# ...and RED/GREEN inside an HTML comment is not proof (the stripper must actually strip —
# the first version used a sed form BSD sed treats as a no-op, and this cell was vacuous)
N2="$(reg --title "comment only" --type bug)"; N2ID="$(idof "$N2")"
printf '\n<!-- procedure: RED first, then GREEN -->\n' >> "$N2"
ERR2="$(bash "$SCRIPTS/close-item.sh" "$N2ID" --no-index 2>&1 >/dev/null)"
[[ "$ERR2" == *"no RED->GREEN proof"* && "$ERR2" != *"sed:"* ]] && ok "RED/GREEN inside an HTML comment does not count as proof" || bad "comment read as proof or sed error: $ERR2"
# an empty `what` cell must not shift the proof into the what slot
W="$(reg --title "empty what")"; WID="$(idof "$W")"
add_row "$W" test "" "3 passed"
bash "$SCRIPTS/close-item.sh" "$WID" --sweep --no-index >/dev/null 2>&1 && ok "a row with an empty what cell but a proof is accepted" || bad "empty-what row refused"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — verification gate: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
