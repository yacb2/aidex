#!/usr/bin/env bash
# test-worklist-close-refusal.sh — worklist-close.sh refuses to end a run over an
# unanswered owner row or an unreconciled deferral; --force closes and RECORDS the
# override; a clean close archives the file so `worklist/<file>` keeps resolving.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BL="$(cd "$DIR/../../backlog/scripts" && pwd -P)"
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
bash "$BL/close-item.sh" "$AID" --sweep --no-index >/dev/null 2>&1   # owner row PARKS the item (awaiting: owner)
[[ -f "$A" ]] && grep -q '^awaiting: owner$' "$A" && ok "item with an unanswered owner row is parked, not archived" || bad "item not parked"
bash "$BL/close-item.sh" "$BID" --sweep --no-index >/dev/null 2>&1

# 1 · unanswered owner row on a PARKED queued item → refused, untouched
before="$(cat "$WL")"
bash "$DIR/worklist-close.sh" "$WL" >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 ]] && grep -q "owner rows still unanswered" "$TMP/err" && grep -q "$AID: wording of the toast" "$TMP/err" \
  && ok "refused over an unanswered owner row, naming the item and the judgement" || bad "owner refusal: rc=$RC $(cat "$TMP/err")"
[[ "$(cat "$WL")" == "$before" && -f "$WL" ]] && ok "refusal mutates nothing" || bad "refusal mutated"

# the owner answers (proof filled) → close proceeds
sed -i.bak 's/| owner | wording of the toast |  |/| owner | wording of the toast | approved by owner 2026-08-27 |/' "$A" && rm -f "$A.bak"
bash "$BL/close-item.sh" "$AID" --sweep --no-index >/dev/null 2>&1   # answered → closes and archives
[[ ! -f "$A" ]] && ok "answered owner row: the item closes and archives" || bad "answered item did not close"
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
bash "$DIR/worklist-close.sh" "$ARCH" >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 ]] && grep -q "already archived" "$TMP/err" && ok "closing an archived worklist is refused as already archived" || bad "double close: rc=$RC $(cat "$TMP/err")"

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

# 3a' · an owner cell holding a placeholder ("awaiting owner") is unanswered here too, the
# same definition close-item.sh parks on — the run must not end over it (BL-656)
D="$(reg --title "placeholder owner")"; DID="$(idof "$D")"
row "$D" test "t" "1 passed"; row "$D" owner "wording" "awaiting owner (chain ledger d10)"
WL9="$(bash "$DIR/worklist-new.sh" --title "Placeholder owner" --mode sweep --ref "backlog:$DID — d")"
bash "$BL/close-item.sh" "$DID" --sweep --no-index >/dev/null 2>&1
bash "$DIR/worklist-close.sh" "$WL9" >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 ]] && grep -q "owner rows still unanswered" "$TMP/err" && grep -q "$DID: wording" "$TMP/err" \
  && ok "refused over an owner row whose proof is a placeholder ('awaiting owner')" || bad "placeholder owner: rc=$RC $(cat "$TMP/err")"

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

# 5 · a slug names the work-list even when a same-named file sits in the CWD (BL-551).
# resolve_worklist's `[[ -f ]]` took ./<slug> first: close rewrote and archived the stray
# file as `_archive/<slug>`, advance peeked its queue.
cd "$P"
stray() { printf 'not a work-list\n1. [ ] stray\n' > "$1"; }
WL6="$(bash "$DIR/worklist-new.sh" --title "Slug six" --slug slug-six --ref "inline:first of six")"
stray slug-six
OUT="$(bash "$DIR/worklist-advance.sh" slug-six --peek 2>&1)"
[[ "$OUT" == *"first of six"* ]] && ok "advance by slug peeks the work-list, not ./slug-six" || bad "advance by slug: $OUT"
OUT="$(bash "$DIR/worklist-close.sh" slug-six 2>&1)"; RC=$?
[[ $RC -eq 0 && "$OUT" == "CLOSED $P/.context/worklists/_archive/$(basename "$WL6")" ]] \
  && ok "close by slug archives the work-list" || bad "close by slug: rc=$RC $OUT"
[[ "$(cat slug-six 2>/dev/null)" == $'not a work-list\n1. [ ] stray' && ! -e .context/worklists/_archive/slug-six ]] \
  && ok "the CWD file is untouched and not archived" || bad "the CWD file was rewritten or archived"
# a worktree that links .context (WT_LINKS): same answer through the symlink
mkdir -p "$TMP/sib" && ln -s "$P/.context" "$TMP/sib/.context"
bash "$DIR/worklist-new.sh" --title "Slug seven" --slug slug-seven --ref "inline:first of seven" >/dev/null
OUT="$(cd "$TMP/sib" && stray slug-seven && bash "$DIR/worklist-advance.sh" slug-seven --peek 2>&1)"
[[ "$OUT" == *"first of seven"* ]] && ok "through a symlinked .context, the slug still names the work-list" || bad "linked: $OUT"
# inside the linked worklists/, the logical CWD differs from the resolved one: only
# comparing `pwd -P` on both sides accepts the bare filename there
OUT="$(cd "$TMP/sib/.context/worklists" && bash "$DIR/worklist-advance.sh" "$(ls | grep slug-seven)" --peek 2>&1)"
[[ "$OUT" == *"first of seven"* ]] && ok "a bare filename from inside a symlinked worklists/ is taken as given" || bad "linked in-dir filename: $OUT"
# an explicit path, and a bare filename from inside worklists/, still resolve as given
OUT="$(bash "$DIR/worklist-advance.sh" ".context/worklists/$(ls .context/worklists | grep slug-seven)" --peek 2>&1)"
[[ "$OUT" == *"first of seven"* ]] && ok "a relative path is taken as given" || bad "relative path: $OUT"
OUT="$(cd .context/worklists && bash "$DIR/worklist-advance.sh" "$(ls | grep slug-seven)" --peek 2>&1)"
[[ "$OUT" == *"first of seven"* ]] && ok "a bare filename from inside worklists/ is taken as given" || bad "in-dir filename: $OUT"
# the in-dir branch itself: inside worklists/, `twin.md` is taken as given even though the
# glob would also hit a dated `*-twin.md` (without the branch: ambiguous, exit 2)
SEVEN=(.context/worklists/*slug-seven*.md); cp "${SEVEN[0]}" .context/worklists/twin.md
cp .context/worklists/twin.md .context/worklists/2026-10-02-twin.md
OUT="$(cd .context/worklists && bash "$DIR/worklist-advance.sh" twin.md --peek 2>&1)"; RC=$?
[[ $RC -eq 0 && "$OUT" == *"first of seven"* ]] && ok "inside worklists/, a bare filename wins over a glob twin" \
  || bad "in-dir twin: rc=$RC $OUT"
rm -f .context/worklists/twin.md .context/worklists/2026-10-02-twin.md
# the full dated filename, the form every listing prints, from OUTSIDE worklists/: the glob
# became `*<name>.md*.md` and matched nothing
OUT="$(bash "$DIR/worklist-advance.sh" "$(ls .context/worklists | grep slug-seven)" --peek 2>&1)"
[[ "$OUT" == *"first of seven"* ]] && ok "a full filename with .md from outside worklists/ resolves" || bad "filename from outside: $OUT"
# without --with-archive, an archived filename from inside _archive/ is not a work-list
OUT="$(cd .context/worklists/_archive && bash "$DIR/worklist-advance.sh" "$(basename "$WL6")" --peek 2>&1)"; RC=$?
[[ $RC -ne 0 && "$OUT" == *"not found"* ]] && ok "an archived filename from inside _archive/ is not found without --with-archive" \
  || bad "archived in-dir filename: rc=$RC $OUT"
# ".md" alone must not strip to an empty name that globs every work-list
OUT="$(bash "$DIR/worklist-advance.sh" .md --peek 2>&1)"; RC=$?
[[ $RC -ne 0 && "$OUT" != *"first of"* ]] && ok "'.md' alone resolves to nothing" || bad "'.md' alone: rc=$RC $OUT"

# 6 · a path outside worklists/ is not a work-list (BL-561): the resolver took any `*/*`
# as given, so `close ./notes.md` rewrote the user's file to done and archived it, and a
# plain advance ticked its queue. Each cell owns its filename, so one cell's archived
# copy cannot turn the next one red as an "archive collision".
note=$'---\nstatus: draft\nupdated: 2026-01-01\n---\n1. [ ] mine'
printf '%s\n' "$note" > notes-close.md
bash "$DIR/worklist-close.sh" ./notes-close.md >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -ne 0 && "$(cat notes-close.md 2>/dev/null)" == "$note" && ! -e .context/worklists/_archive/notes-close.md ]] && grep -q "not under" "$TMP/err" \
  && ok "close of a path outside worklists/ is refused and the file is untouched" || bad "close ./notes-close.md: rc=$RC $(cat "$TMP/err")"
printf '%s\n' "$note" > notes-advance.md
bash "$DIR/worklist-advance.sh" ./notes-advance.md >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -ne 0 && "$(cat notes-advance.md)" == "$note" ]] && grep -q "not under" "$TMP/err" \
  && ok "advance of a path outside worklists/ is refused and the file is untouched" || bad "advance ./notes-advance.md: rc=$RC, $(sed -n 5p notes-advance.md) $(cat "$TMP/err")"
# the check compares resolved directories, not the spelling: `worklists/../..` is the
# project root (one `..` is .context/, where no such file exists: a not-found, not this check)
printf '%s\n' "$note" > notes-dotdot.md
bash "$DIR/worklist-close.sh" .context/worklists/../../notes-dotdot.md >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -ne 0 && "$(cat notes-dotdot.md)" == "$note" && ! -e .context/worklists/_archive/notes-dotdot.md ]] && grep -q "not under" "$TMP/err" \
  && ok "a path that spells worklists/ but resolves outside it is refused" || bad "close .context/worklists/../../notes-dotdot.md: rc=$RC $(cat "$TMP/err")"
# `..` after a symlinked folder inside worklists/: a logical `cd ext/..` lands back in
# worklists/, while the file the kernel opens is beside the link's target
mkdir -p outside/sub && ln -s "$P/outside/sub" .context/worklists/ext
printf '%s\n' "$note" > outside/notes-symlink.md
(cd .context/worklists && bash "$DIR/worklist-close.sh" ext/../notes-symlink.md >/dev/null 2>"$TMP/err"); RC=$?
[[ $RC -ne 0 && "$(cat outside/notes-symlink.md 2>/dev/null)" == "$note" && ! -e .context/worklists/_archive/notes-symlink.md ]] && grep -q "not under" "$TMP/err" \
  && ok "a symlinked folder plus .. inside worklists/ does not let an outside file through" || bad "close ext/../notes-symlink.md: rc=$RC $(cat "$TMP/err")"
rm -f .context/worklists/ext; rm -rf outside
# an exported CDPATH must not redirect the directory check: `cd worklists` from P/work
# landed in P/.context/worklists, so a user file there passed as a work-list
mkdir -p work/worklists; note2=$'---\nstatus: doing\nupdated: 2026-01-01\n---\n1. [ ] mine'
printf '%s\n' "$note2" > work/worklists/notes-cdpath.md
(cd work && CDPATH="$P/.context" bash "$DIR/worklist-close.sh" worklists/notes-cdpath.md >/dev/null 2>"$TMP/err"); RC=$?
[[ $RC -ne 0 && "$(cat work/worklists/notes-cdpath.md 2>/dev/null)" == "$note2" && ! -e .context/worklists/_archive/notes-cdpath.md ]] && grep -q "not under" "$TMP/err" \
  && ok "with CDPATH exported, a user file outside worklists/ is still refused" || bad "CDPATH close: rc=$RC $(cat "$TMP/err")"
rm -rf work
# and the reverse: CDPATH pointing at another project must not refuse a real work-list
WL8="$(bash "$DIR/worklist-new.sh" --title "Cdpath reverse" --slug cdpath-reverse --ref "inline:first of reverse")"
mkdir -p "$TMP/other/.context/worklists"
OUT="$(CDPATH="$TMP/other" bash "$DIR/worklist-advance.sh" ".context/worklists/$(basename "$WL8")" --peek 2>&1)"
[[ "$OUT" == *"first of reverse"* ]] && ok "with CDPATH at another project, a path into worklists/ still resolves" || bad "CDPATH reverse: $OUT"

# 7 · an ARCHIVED work-list reached by a path without a literal `_archive/` (BL-591): close
# matched the string `*/_archive/*`, so `cd _archive && close ./x.md` rewrote status and
# updated and only then died on "archive collision"; advance had no archived check and
# ticked the archived queue. `updated` is backdated, or a buggy close rewrites the file
# byte-identical (status done, updated today) and the checksum cell passes for nothing.
OUT="$(bash "$DIR/worklist-close.sh" "$(bash "$DIR/worklist-new.sh" --title "Archived" --slug archived-seven \
  --ref "inline:a1" --ref "inline:a2" --ref "inline:a3" --ref "inline:a4")" 2>/dev/null)"
AR="${OUT#CLOSED }"; ARN="$(basename "$AR")"
sed -i.bak 's/^updated: .*/updated: 2026-01-01/' "$AR" && rm -f "$AR.bak"
archived_refused() {  # archived_refused <label> <cmd...> — rc 2, "already archived", bytes unchanged
  local label="$1" sum rc; shift; sum="$(cksum < "$AR")"
  "$@" >/dev/null 2>"$TMP/err"; rc=$?
  [[ $rc -eq 2 && "$(cksum < "$AR")" == "$sum" && -f "$AR" ]] && grep -q "already archived" "$TMP/err" \
    && ok "$label is refused as already archived, file untouched" || bad "$label: rc=$rc $(cat "$TMP/err")"
}
in_archive() { (cd .context/worklists/_archive && "$@"); }
archived_refused "close ./x.md from inside _archive/" in_archive bash "$DIR/worklist-close.sh" "./$ARN"
ln -s _archive .context/worklists/arch
archived_refused "close through a symlinked dir to _archive/" bash "$DIR/worklist-close.sh" ".context/worklists/arch/$ARN"
rm -f .context/worklists/arch
archived_refused "advance ./x.md from inside _archive/" in_archive bash "$DIR/worklist-advance.sh" "./$ARN"
archived_refused "advance of a literal _archive/ path" bash "$DIR/worklist-advance.sh" ".context/worklists/_archive/$ARN"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — worklist close refusal: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
