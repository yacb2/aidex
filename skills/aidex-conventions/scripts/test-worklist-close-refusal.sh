#!/usr/bin/env bash
# test-worklist-close-refusal.sh — worklist-close.sh refuses to end a run over an
# unanswered owner row or an unreconciled deferral; --force closes and RECORDS the
# override; a clean close archives the file so `worklist/<file>` keeps resolving.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BL="$(cd "$DIR/../../aidex-backlog/scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/.context/backlog"; cd "$P"
reg() { bash "$BL/register-item.sh" --origin manual --no-index "$@" 2>/dev/null; }
idof() { awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$1"; }
row() { printf '| %s | %s | %s |\n' "$2" "$3" "$4" > "$TMP/row"
  awk -v r="$(cat "$TMP/row")" '{print} /^\|---\|---\|---\|$/ && !d {print r; d=1}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

echo "worklist-close.sh refusals:"
A="$(reg --title "with owner row")"; AID="$(idof "$A")"
row "$A" test "tests/test_a.py" "2 passed"; row "$A" owner "wording of the toast" ""
B="$(reg --title "plain proven")"; BID="$(idof "$B")"; row "$B" test "t" "1 passed"
WL="$(bash "$DIR/worklist-new.sh" --title "Refusal" --mode sweep --publish never --ref "backlog:$AID — a" --ref "backlog:$BID — b")"
bash "$BL/close-item.sh" "$AID" --sweep --no-index >/dev/null 2>&1   # owner row does not block the ITEM
[[ ! -f "$A" ]] && ok "item with an unanswered owner row closes (archived)" || bad "item did not close"
bash "$BL/close-item.sh" "$BID" --sweep --no-index >/dev/null 2>&1

# 1 · unanswered owner row on an ARCHIVED queued item → refused, untouched
before="$(cat "$WL")"
bash "$DIR/worklist-close.sh" "$WL" >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 ]] && grep -q "owner rows still unanswered" "$TMP/err" && grep -q "$AID: wording of the toast" "$TMP/err" \
  && ok "refused over an unanswered owner row, naming the item and the judgement" || bad "owner refusal: rc=$RC $(cat "$TMP/err")"
[[ "$(cat "$WL")" == "$before" && -f "$WL" ]] && ok "refusal mutates nothing" || bad "refusal mutated"

# the owner answers (proof filled) → close proceeds
AR="$P/.context/backlog/_archive/$(basename "$A")"
sed -i.bak 's/| owner | wording of the toast |  |/| owner | wording of the toast | approved by owner 2026-08-27 |/' "$AR" && rm -f "$AR.bak"
# 2 · an unreconciled deferral → refused
bash "$DIR/worklist-advance.sh" "$WL" --append "inline:found a stale row, carry to a later sweep" >/dev/null 2>&1
bash "$DIR/worklist-close.sh" "$WL" >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 ]] && grep -q "unreconciled deferrals" "$TMP/err" && grep -q "stale row" "$TMP/err" \
  && ok "refused over an unreconciled deferral (no BL-NNN, no CLOSE:)" || bad "deferral refusal: rc=$RC $(cat "$TMP/err")"
# reconcile it with a BL-NNN → close proceeds
sed -i.bak 's/carry to a later sweep/carry to a later sweep — BL-900/' "$WL" && rm -f "$WL.bak"
OUT="$(bash "$DIR/worklist-close.sh" "$WL" 2>/dev/null)"; RC=$?
[[ $RC -eq 0 && "$OUT" == "CLOSED $P/.context/worklists/_archive/"* ]] && ok "clean close archives to worklists/_archive/" || bad "clean close: rc=$RC $OUT"
ARCH="${OUT#CLOSED }"
[[ -f "$ARCH" && ! -f "$WL" ]] && grep -q '^status: done' "$ARCH" && ok "archived file carries status done" || bad "archive state"
bash "$DIR/worklist-close.sh" "$ARCH" >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "closing an archived worklist is refused" || bad "double close"

# 3 · --force closes anyway and records what it overrode, in the file and on stderr
C="$(reg --title "never answered")"; CID="$(idof "$C")"; row "$C" test "t" "1 passed"; row "$C" owner "colour of the badge" ""
WL2="$(bash "$DIR/worklist-new.sh" --title "Forced" --mode sweep --ref "backlog:$CID — c")"
bash "$BL/close-item.sh" "$CID" --sweep --no-index >/dev/null 2>&1
bash "$DIR/worklist-advance.sh" "$WL2" --append "inline:loose end" >/dev/null 2>&1
OUT="$(bash "$DIR/worklist-close.sh" "$WL2" --force 2>"$TMP/err")"; RC=$?
[[ $RC -eq 0 && "$OUT" == CLOSED* ]] && ok "--force closes" || bad "--force: rc=$RC $OUT"
grep -q "FORCED close" "$TMP/err" && grep -q "colour of the badge" "$TMP/err" && grep -q "loose end" "$TMP/err" && ok "--force prints both overrides" || bad "force stderr: $(cat "$TMP/err")"
grep -q "with --force, overriding: unanswered owner rows" "${OUT#CLOSED }" && grep -q "unreconciled deferrals" "${OUT#CLOSED }" && ok "--force records the override in the file" || bad "force not recorded: $(tail -2 "${OUT#CLOSED }")"

# 3a · a queued id that resolves to NO item must not kill the close (the helper's no-match
# path ended on a false `[[ ]] &&`, and `set -e` turned `f="$(item_file …)"` into exit 1)
WL5="$(bash "$DIR/worklist-new.sh" --title "Ghost id" --mode sweep --ref "backlog:BL-9999 — never registered")"
bash "$DIR/worklist-close.sh" "$WL5" >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 0 ]] && ok "a sweep list whose queued id resolves to no item still closes (no set -e death)" || bad "ghost id: rc=$RC $(cat "$TMP/err")"

# 3b · a PLAIN work-list is not gated: an unchecked emergent line still closes (audit kickoffs use this)
WL3="$(bash "$DIR/worklist-new.sh" --title "Plain" --ref "inline:only inline")"
bash "$DIR/worklist-advance.sh" "$WL3" --append "inline:loose end" >/dev/null 2>&1
bash "$DIR/worklist-close.sh" "$WL3" >/dev/null 2>&1 && ok "a plain (non-sweep) work-list closes over an unchecked emergent line, as before" || bad "plain worklist gated"

# 4 · a worklist/<file> cross-ref resolves before AND after archive (validate.py)
V="$DIR/validate.py"
mkdir -p "$P/.context/research"
cat > "$P/.context/research/2026-08-27-sweep-report.md" <<EOF2
---
title: "Sweep report"
status: done
created: 2026-08-27
updated: 2026-08-27
origin: sweep
origin_ref: worklist/$(basename "$ARCH")
---

# Sweep report

Anchored to the archived work-list.
EOF2
python3 "$V" --type research --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); f=[x for x in (d if isinstance(d,list) else d.get("findings",[])) if "crossref" in x.get("rule","")]; sys.exit(1 if f else 0)' \
  && ok "origin_ref: worklist/<archived file> validates clean" || bad "worklist cross-ref flagged: $(python3 "$V" --type research 2>&1 | grep -i crossref)"
sed -i.bak "s|origin_ref: worklist/.*|origin_ref: worklist/2026-01-01-no-such-run.md|" "$P/.context/research/2026-08-27-sweep-report.md" && rm -f "$P/.context/research/2026-08-27-sweep-report.md.bak"
VOUT="$(python3 "$V" --type research 2>&1)"
grep -q "resolves to no file" <<<"$VOUT" && ok "a worklist ref to a missing run is still caught" || bad "missing worklist ref not flagged: $VOUT $(grep origin_ref "$P/.context/research/2026-08-27-sweep-report.md")"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — worklist close refusal: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
