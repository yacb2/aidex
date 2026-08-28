#!/usr/bin/env bash
# test-worklist-sweep-wiring.sh — in sweep mode, advancing the queue DRIVES the item
# lifecycle: the head is closed through close-item.sh --sweep (inheriting its proof
# refusal), and the next backlog item is started. Also pins Task 2.3: the worklist scripts
# resolve the SAME project root as close-item.sh from inside a linked worktree — the
# queue and the item must never live in two trees.
#
# Fixture project in a temp dir; git only for the worktree case.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BL="$(cd "$DIR/../../aidex-backlog/scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
fm()  { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/.context/backlog"; cd "$P"
reg() { bash "$BL/register-item.sh" --origin manual "$@" 2>/dev/null; }
idof() { awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$1"; }
prove() { printf '| test | %s | 3 passed |\n' "$2" > "$TMP/row"
  awk -v row="$(cat "$TMP/row")" '{print} /^\|---\|---\|---\|$/ && !d {print row; d=1}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

echo "worklist sweep wiring:"
A="$(reg --title "first item")";  AID="$(idof "$A")"
B="$(reg --title "second item")"; BID="$(idof "$B")"
C="$(reg --title "third item")";  CID="$(idof "$C")"
WL="$(bash "$DIR/worklist-new.sh" --title "Sweep test" --mode sweep --publish never \
      --ref "backlog:$AID — first" --ref "backlog:$BID — second" --ref "inline:tidy" --ref "backlog:$CID — third")"
grep -q '^mode: sweep$' "$WL" && ok "worklist-new --mode sweep writes mode: sweep" || bad "no mode line"
grep -q '^  publish: never$' "$WL" && ok "--publish never accepted" || bad "publish never"
python3 "$DIR/validate-worklist.py" "$WL" >/dev/null && ok "sweep worklist validates" || bad "validate: $(python3 "$DIR/validate-worklist.py" "$WL")"

# 1 · the head has no proof: advance is refused, the box stays unticked, nothing moved
OUT="$(bash "$DIR/worklist-advance.sh" "$WL" 2>"$TMP/err")"; RC=$?
[[ $RC -ne 0 ]] && ok "advance refused over an unproven head (rc=$RC)" || bad "advance ticked past an unproven item"
grep -q "^1\. \[ \] " "$WL" && ok "head box stays unticked" || bad "head box was ticked"
[[ -f "$A" ]] && ok "unproven item still active (not archived)" || bad "item archived despite refusal"
grep -q "not closed" "$TMP/err" && ok "refusal names the item" || bad "stderr: $(cat "$TMP/err")"

# 2 · proven head: advance closes it, ticks, and STARTS the next backlog item
prove "$A" "tests/test_a.py"
NEXT="$(bash "$DIR/worklist-advance.sh" "$WL" 2>/dev/null)"; RC=$?
[[ $RC -eq 0 ]] && ok "advance succeeds over a proven head" || bad "advance rc=$RC"
[[ ! -f "$A" && -f "$P/.context/backlog/_archive/$(basename "$A")" ]] && ok "head closed and archived via close-item --sweep" || bad "head not archived"
grep -q "^1\. \[x\] " "$WL" && ok "head box ticked" || bad "head box not ticked"
[[ "$NEXT" == 2.* ]] && ok "prints the next item" || bad "next: $NEXT"
[[ "$(fm "$B" status)" == "doing" ]] && ok "next backlog item started (status: doing)" || bad "next item status: $(fm "$B" status)"
[[ "$(fm "$C" status)" == "open" ]] && ok "items further down are untouched" || bad "third item status: $(fm "$C" status)"

# 3 · --peek never closes or starts anything
prove "$B" "tests/test_b.py"
bash "$DIR/worklist-advance.sh" "$WL" --peek >/dev/null 2>&1
[[ -f "$B" && "$(grep -c '\[x\]' "$WL")" == "1" ]] && ok "--peek is read-only in sweep mode" || bad "--peek mutated"

# 4 · an inline next item is printed, not started; advancing past it is a plain tick
bash "$DIR/worklist-advance.sh" "$WL" >/dev/null 2>&1   # closes B, next is inline
[[ ! -f "$B" ]] && ok "second proven item closed on advance" || bad "second item not closed"
NEXT="$(bash "$DIR/worklist-advance.sh" "$WL" 2>/dev/null)"
[[ "$NEXT" == 4.* && "$(fm "$C" status)" == "doing" ]] && ok "inline head ticks plainly; the following backlog item is started" || bad "after inline: next=$NEXT status=$(fm "$C" status)"

# 5 · plain mode is unchanged: no close, no start
D="$(reg --title "plain d")"; DID="$(idof "$D")"
E="$(reg --title "plain e")"; EID="$(idof "$E")"
WL2="$(bash "$DIR/worklist-new.sh" --title "Plain" --ref "backlog:$DID — d" --ref "backlog:$EID — e")"
bash "$DIR/worklist-advance.sh" "$WL2" >/dev/null 2>&1
[[ -f "$D" && "$(fm "$E" status)" == "open" && "$(grep -c '\[x\]' "$WL2")" == "1" ]] && ok "plain worklist: tick only, no lifecycle" || bad "plain mode drove the lifecycle"

# 6 · --append is additive in sweep mode too — and a backlog append JOINS THE QUEUE
G="$(reg --title "emergent g")"; GID="$(idof "$G")"
bash "$DIR/worklist-advance.sh" "$WL" --append "backlog:$GID — emergent" >/dev/null 2>&1
grep -qE "^5\. \[ \] $GID — emergent   <!-- ref: backlog --> <!-- emergent -->" "$WL" && ok "sweep --append backlog: joins the numbered queue as item 5, marked emergent" || bad "append: $(grep "$GID" "$WL")"
[[ "$(fm "$C" status)" == "doing" && -f "$C" ]] && ok "--append neither closes nor starts" || bad "--append had lifecycle side effects"
python3 "$DIR/validate-worklist.py" "$WL" >/dev/null && ok "queue still validates after the emergent append" || bad "validate after append"
bash "$DIR/worklist-advance.sh" "$WL" --append "inline:tidy later" >/dev/null 2>&1
grep -q "^- \[ \] tidy later" "$WL" && ok "a non-backlog append still goes to the emergent section" || bad "inline append"

# 6b · a head closed OUT OF BAND is ticked past, not wedged; a deferred head likewise
prove "$C" "tests/test_c.py"
bash "$BL/close-item.sh" "$CID" --sweep --no-index >/dev/null 2>&1      # out of band
NEXT="$(bash "$DIR/worklist-advance.sh" "$WL" 2>"$TMP/err")"; RC=$?
[[ $RC -eq 0 && "$NEXT" == 5.* ]] && grep -q "already closed" "$TMP/err" && ok "an already-closed head is ticked past with a note" || bad "out-of-band head: rc=$RC next=$NEXT $(cat "$TMP/err")"
bash "$BL/defer-item.sh" defer "$GID" --reason "vendor" >/dev/null 2>&1
NEXT="$(bash "$DIR/worklist-advance.sh" "$WL" 2>"$TMP/err")"; RC=$?
[[ $RC -eq 0 && "$NEXT" == "DONE" ]] && grep -q "deferred" "$TMP/err" && ok "a deferred head is ticked past with a warning" || bad "deferred head: rc=$RC next=$NEXT $(cat "$TMP/err")"

# 6c · a next item that cannot be started is an error, not a silent success
H="$(reg --title "h")"; HID="$(idof "$H")"; prove "$H" "t"
WL4="$(bash "$DIR/worklist-new.sh" --title "Start fail" --mode sweep --ref "backlog:$HID — h" --ref "backlog:BL-777 — ghost")"
bash "$DIR/worklist-advance.sh" "$WL4" >/dev/null 2>"$TMP/err"; RC=$?
[[ $RC -eq 2 ]] && grep -q "could not start BL-777" "$TMP/err" && ok "a next item that does not exist fails the advance (exit 2)" || bad "ghost start: rc=$RC $(cat "$TMP/err")"
# and a quoted mode line still means sweep
sed -i.bak 's/^mode: sweep$/mode: "sweep"/' "$WL4" && rm -f "$WL4.bak"
bash "$DIR/worklist-advance.sh" "$WL4" >/dev/null 2>"$TMP/err"; RC=$?
grep -q "BL-777" "$TMP/err" && ok "mode: \"sweep\" (quoted) is still sweep mode" || bad "quoted mode ignored: rc=$RC $(cat "$TMP/err")"

# 7 · one project root: from a linked worktree, worklist and item resolve to the main tree
if command -v git >/dev/null 2>&1; then
  # .context/ is gitignored, as in this repo: with it TRACKED the worktree carries its own
  # copy and the resolver's pass 1 answers the worktree for every script alike — still one
  # root, just a different one (documented in _lib.sh). The hop is what is pinned here.
  printf '.context/\n' > "$P/.gitignore"
  ( cd "$P" && git init -q . && git -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1 \
      && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1
  ( cd "$P" && git worktree add -q "$TMP/proj-wt" -b feat ) >/dev/null 2>&1
  if [[ -d "$TMP/proj-wt" ]]; then
    F="$(cd "$TMP/proj-wt" && reg --title "from the worktree")"
    [[ "$F" == "$P/.context/backlog/"* ]] && ok "register-item.sh from a worktree writes to the main tree" || bad "item written at $F"
    WL3="$(cd "$TMP/proj-wt" && bash "$DIR/worklist-new.sh" --title "WT" --mode sweep --ref "backlog:$(idof "$F") — wt")"
    [[ "$WL3" == "$P/.context/worklists/"* ]] && ok "worklist-new.sh from a worktree writes to the SAME main tree" || bad "worklist written at $WL3"
    PEEK="$(cd "$TMP/proj-wt" && bash "$DIR/worklist-advance.sh" "$(basename "$WL3" .md)" --peek 2>/dev/null)"
    [[ "$PEEK" == 1.* ]] && ok "worklist-advance.sh --peek from the worktree resolves the same queue by slug" || bad "peek from worktree: $PEEK"
  else echo "  skip: git worktree add unavailable"; fi
else echo "  skip: git not on PATH"; fi

# BL-249 / BL-253: close-item refuses a hash that is not on the current branch, and
# worklist-advance --commit forwards the resolving commit so `commits:` is not empty
if command -v git >/dev/null; then
  P4="$TMP/proj4"; mkdir -p "$P4/.context/backlog"; ( cd "$P4" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m c1 )
  ONTRUNK="$(git -C "$P4" rev-parse --short HEAD)"
  ( cd "$P4" && git checkout -q -b side && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m side && git checkout -q - )
  OFFTRUNK="$(git -C "$P4" rev-parse --short side)"
  cd "$P4"
  X="$(reg --title "trunk check" --estimate XS --verify "a test" 2>/dev/null)"; XID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$X")"
  bash "$BL/define-item.sh" "$X" --touches "a.py" --no-index >/dev/null 2>&1
  sed -i.bak 's/^- <!-- concrete, verifiable criterion -->$/- done/' "$X" && rm -f "$X.bak"
  printf '| %s | %s | %s |\n' test tests/x.py "1 passed" > "$TMP/row4"
  awk -v r="$(cat "$TMP/row4")" '{print} /^\|---\|---\|---\|$/ && !d {print r; d=1}' "$X" > "$X.tmp" && mv "$X.tmp" "$X"
  ERR="$(bash "$BL/close-item.sh" "$XID" --sweep --commit "$OFFTRUNK" --no-index 2>&1 >/dev/null)"; RC=$?
  [[ $RC -ne 0 && -f "$X" && "$ERR" == *"not on the current branch"* ]] && ok "close-item refuses a commit from another branch and leaves the item active" || bad "off-trunk: rc=$RC $ERR"
  WL5="$(bash "$DIR/worklist-new.sh" --title "Trunk run" --mode sweep --publish never --ref "backlog:$XID — trunk check" 2>/dev/null | tail -1)"
  [[ -f "$WL5" ]] || WL5="$(ls .context/worklists/*trunk-run*.md | head -1)"
  bash "$DIR/worklist-advance.sh" "$WL5" --commit "$ONTRUNK" >/dev/null 2>&1; RC=$?
  XA="$(ls .context/backlog/_archive/*trunk-check*.md 2>/dev/null | head -1)"
  [[ $RC -eq 0 && -n "$XA" ]] && grep -q "^commits: \"$ONTRUNK\"" "$XA" && ok "worklist-advance --commit forwards the trunk commit into commits:" || bad "advance --commit: rc=$RC $(grep '^commits' "$XA" 2>/dev/null)"
  cd "$TMP"
fi

# BL-261: a parked head is ticked as handled, and its queue line says parked, not done
if command -v git >/dev/null; then
  P5="$TMP/proj5"; mkdir -p "$P5/.context/backlog"; ( cd "$P5" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m c1 ); cd "$P5"
  Y="$(reg --title "parked head" --estimate XS --verify "a test" 2>/dev/null)"; YID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$Y")"
  bash "$BL/define-item.sh" "$Y" --touches "a.py" --no-index >/dev/null 2>&1
  sed -i.bak 's/^- <!-- concrete, verifiable criterion -->$/- done/' "$Y" && rm -f "$Y.bak"
  for r in '| test | tests/y.py | 1 passed |' '| owner | wording | |'; do
    awk -v r="$r" '{print} /^\|---\|---\|---\|$/ && !d {print r; d=1}' "$Y" > "$Y.tmp" && mv "$Y.tmp" "$Y"
  done
  WL6="$(bash "$DIR/worklist-new.sh" --title "Parked run" --mode sweep --publish never --ref "backlog:$YID — parked head" 2>/dev/null | tail -1)"
  bash "$DIR/worklist-advance.sh" "$WL6" >/dev/null 2>&1; RC=$?
  L="$(grep -E "^1\. \[x\] $YID" "$WL6" || true)"
  [[ $RC -eq 0 && "$L" == *"<!-- parked: awaiting owner -->"* && -f "$Y" ]] && ok "a parked head is ticked and its queue line reads parked: awaiting owner" || bad "parked line: rc=$RC ${L:-<no ticked line>}"
  cd "$TMP"
fi

echo; [[ $FAIL -eq 0 ]] && { echo "OK — worklist sweep wiring: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
