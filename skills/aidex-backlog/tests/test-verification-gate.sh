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
  [[ $rc -eq 2 ]] && grep -q "$4" "$TMP/err" && ok "$1: exit 2 — $(grep -o "$4" "$TMP/err" | head -1)" || bad "$1: rc=$rc $(cat "$TMP/err")"
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

# an owner row with an empty proof does NOT block the item close (worklist-close.sh owns that)
O="$(reg --title "owner row" --surface internal)"; OID="$(idof "$O")"
add_row "$O" test "tests/test_o.py" "4 passed"
add_row "$O" owner "wording of the new toast" ""
bash "$SCRIPTS/close-item.sh" "$OID" --sweep --no-index >/dev/null 2>&1 && ok "owner row with empty proof does not block the item" || bad "owner row blocked the close"

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
