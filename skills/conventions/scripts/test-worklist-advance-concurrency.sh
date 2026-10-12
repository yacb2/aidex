#!/usr/bin/env bash
# test-worklist-advance-concurrency.sh — worklist-advance.sh serialises its
# read-modify-write on a work-list (conventions-scripts-c19). It shared a fixed
# `$file.tmp` with no lock: concurrent `--append`s (register-item.sh --origin sweep
# chains one per registration) lost rows, and the file could be emptied outright.
# Also pinned: a lock left by a killed run blocks nobody (the mkdir lock that took a
# stale lock over by age let two waiters take it together and emptied the list in
# 3 of 8 trials); the rewrite keeps the work-list's mode. The lock's own timeout and
# refusals are test-lock-run.sh's.
#
# Layer: the script's CLI against a throwaway project — the race lives in the script.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"   # lock files are kept, never removed: keep them here
P="$TMP/proj"; mkdir -p "$P/.context/worklists" "$P/.context/backlog"; cd "$P"
N=10
mkwl() {  # mkwl <name> <mode-line> → path; one numbered item, valid front matter
  local f="$P/.context/worklists/2026-01-01-$1.md"
  printf -- '---\ntitle: c\nstatus: doing\ncreated: 2026-01-01\nupdated: 2026-01-01\n%bgate-policy:\n  publish: ask\n  destructive: deny\n---\n\n## Queue\n\n1. [ ] BL-1 head   <!-- ref: backlog -->\n\n## Deferred / emergent\n' "$2" > "$f"
  printf '%s' "$f"
}

echo "worklist-advance concurrency:"
# 1 · N parallel sweep backlog appends: every row joins the numbered queue
WL="$(mkwl sweep 'mode: sweep\n')"
for i in $(seq 1 $N); do bash "$DIR/worklist-advance.sh" "$WL" --append "backlog:BL-$((100 + i)) — e$i" >/dev/null 2>&1 & done; wait
got="$(grep -cE '<!-- emergent -->' "$WL")"
[[ "$got" -eq $N ]] && python3 "$DIR/validate-worklist.py" "$WL" >/dev/null \
  && ok "$N parallel sweep appends all land, queue numbered 1..$((N + 1)) and valid" \
  || bad "sweep appends: $got of $N landed, $(wc -l < "$WL") lines; $(python3 "$DIR/validate-worklist.py" "$WL" | tail -1)"

# 2 · N parallel plain appends: `>>` raced the front-matter rewrite of the next caller
WL2="$(mkwl plain '')"
for i in $(seq 1 $N); do bash "$DIR/worklist-advance.sh" "$WL2" --append "inline:loose $i" >/dev/null 2>&1 & done; wait
got="$(grep -cE '^- \[ \] loose [0-9]+ ' "$WL2")"
[[ "$got" -eq $N ]] && ok "$N parallel plain appends all land" || bad "plain appends: $got of $N landed"

# 3 · N parallel appends behind a lock a killed run left: all land, none waits it out.
# The holder takes the work-list's lock and is SIGKILLed holding it; the lock file stays.
WL3="$(mkwl killed 'mode: sweep\n')"
L3="$( . "$DIR/_lib.sh"; wl_lock_file "$WL3")"
{ bash -c '. "$1/_lib.sh"; lock_take "$2" 5 && kill -9 $$' _ "$DIR" "$L3"; RC=$?; } 2>/dev/null
[[ $RC -eq 137 && -f "$L3" ]] \
  || bad "3 fixture: the holder did not die holding a lock file (rc=$RC)"
t0=$SECONDS
for i in $(seq 1 $N); do bash "$DIR/worklist-advance.sh" "$WL3" --append "backlog:BL-$((200 + i)) — k$i" >/dev/null 2>>"$TMP/err3" & done; wait
el=$((SECONDS - t0)); got="$(grep -cE '<!-- emergent -->' "$WL3")"
[[ "$got" -eq $N && $el -lt 20 && ! -s "$TMP/err3" ]] && python3 "$DIR/validate-worklist.py" "$WL3" >/dev/null \
  && ok "$N parallel appends behind a killed run's lock all land in ${el}s, queue valid, nothing on stderr" \
  || bad "behind a killed lock: $got of $N landed after ${el}s, $(wc -c < "$WL3") bytes; $(head -3 "$TMP/err3")"

# 4 · the rewrite keeps the work-list's own mode (a temp file gets the umask's)
WL4="$(mkwl mode 'mode: sweep\n')"; chmod 640 "$WL4"
bash "$DIR/worklist-advance.sh" "$WL4" --append "backlog:BL-300 — m" >/dev/null 2>&1
m="$(stat -c %a "$WL4" 2>/dev/null || stat -f %Lp "$WL4")"
[[ "$m" == 640 ]] && grep -q "BL-300" "$WL4" && ok "a sweep append keeps the file mode (640)" || bad "mode after append: $m"
leftover="$(ls -a "$P/.context/worklists" | grep -vE '^\.\.?$|\.md$' || true)"
[[ -z "$leftover" ]] && ok "no temp or lock residue beside the work-lists" || bad "residue: $leftover"

# 5 · worklist-close.sh takes the same lock: a close started while a writer holds it waits
# for the writer, then archives the list with the writer's row in it. This pins only that
# order (close behind a writer); a writer behind a close is cells 8-10. Without the lock the
# close moved the list first and the writer's row went to a new file at the old path. The
# close starts with fd 9 closed, or it would inherit the holder's lock; the 1 s sleep only
# gives it time to block (if it has not, this passes for nothing, never fails for nothing).
WL5="$(mkwl closing '')"; L5="$( . "$DIR/_lib.sh"; wl_lock_file "$WL5")"
( . "$DIR/_lib.sh"; lock_take "$L5" 5 || exit 1
  bash "$DIR/worklist-close.sh" "$WL5" 9>&- >/dev/null 2>"$TMP/err5" &
  sleep 1; printf -- '- [ ] written under the lock\n' >> "$WL5"
  lock_drop; wait )
A5="$P/.context/worklists/_archive/$(basename "$WL5")"
[[ ! -e "$WL5" && -f "$A5" ]] && grep -q "written under the lock" "$A5" && grep -q '^status: done' "$A5" \
  && ok "a close waits for the writer holding the lock and archives the list with its row" \
  || bad "close under a held lock: old-path=$([[ -e "$WL5" ]] && cat "$WL5" || echo gone) archived=$([[ -f "$A5" ]] && grep -c 'written under' "$A5" || echo none) $(cat "$TMP/err5")"

# 6 · the lock is the file's whatever CDPATH says: a relative path with CDPATH exported at
# another project keyed the lock by that project's twin directory, so this append did not
# wait for the holder and wrote under it. The holder writes its line 1 s in, then drops;
# a waiting append lands after that line.
mkdir -p "$TMP/other/.context/worklists"
WL6="$(mkwl cdpath '')"; L6="$( . "$DIR/_lib.sh"; wl_lock_file "$WL6")"
( . "$DIR/_lib.sh"; lock_take "$L6" 5 || exit 1
  CDPATH="$TMP/other" bash "$DIR/worklist-advance.sh" ".context/worklists/$(basename "$WL6")" --append "inline:the appender" 9>&- >/dev/null 2>"$TMP/err6" &
  sleep 1; printf -- '- [ ] the holder\n' >> "$WL6"
  lock_drop; wait )
order="$(grep -oE 'the (holder|appender)' "$WL6" | tr '\n' ' ')"
[[ "$order" == "the holder the appender " ]] \
  && ok "with CDPATH exported, a relative path takes the same lock and waits for the holder" \
  || bad "CDPATH lock: order '$order' $(cat "$TMP/err6")"

# 7 · every read of the list runs under the lock: `mode: sweep` was read before it, so an
# append that waited behind a writer used the mode it saw first (or an empty file mid
# copy-back) and wrote an unnumbered `- [ ]` row the walk never works. Here the holder makes
# the list a sweep list while the append waits: the row must join the numbered queue.
WL7="$(mkwl modeflip '')"; L7="$( . "$DIR/_lib.sh"; wl_lock_file "$WL7")"
( . "$DIR/_lib.sh"; lock_take "$L7" 5 || exit 1
  bash "$DIR/worklist-advance.sh" "$WL7" --append "backlog:BL-9 — x" 9>&- >/dev/null 2>"$TMP/err7" &
  sleep 1; awk 'NR == 2 { print "mode: sweep" } { print }' "$WL7" > "$TMP/m7" && cat "$TMP/m7" > "$WL7"
  lock_drop; wait )
grep -qE '^2\. \[ \] BL-9 — x .*<!-- emergent -->' "$WL7" && python3 "$DIR/validate-worklist.py" "$WL7" >/dev/null \
  && ok "an append that waited reads the list's mode under the lock (joins the numbered queue)" \
  || bad "mode read before the lock: $(grep 'BL-9' "$WL7") $(cat "$TMP/err7")"

# 8-10 · a run that waited behind a close finds the list gone and refuses: it printed DONE
# with rc 0 (advance), recreated a one-line file at the old path (plain --append), or blamed
# the front matter (close). The holder moves the list to _archive/ as close does, under the lock.
gone_cell() {  # gone_cell <label> <script> [args...] — the script waits, the list is archived
  local label="$1" script="$2" wl l a rc; shift 2; rm -f "$TMP/rc8"
  wl="$(mkwl "gone-$script-$#" '')"; l="$( . "$DIR/_lib.sh"; wl_lock_file "$wl")"
  a="$P/.context/worklists/_archive/$(basename "$wl")"; mkdir -p "$(dirname "$a")"
  ( . "$DIR/_lib.sh"; lock_take "$l" 5 || exit 1
    bash "$DIR/$script" "$wl" "$@" 9>&- >"$TMP/out8" 2>"$TMP/err8" &
    sleep 1; mv "$wl" "$a"; cksum < "$a" > "$TMP/sum8"
    lock_drop; r=0; wait $! || r=$?; echo $r > "$TMP/rc8" )   # _lib.sh sets -e: keep the rc
  rc="$(cat "$TMP/rc8")"
  [[ $rc -eq 2 && ! -e "$wl" && "$(cksum < "$a")" == "$(cat "$TMP/sum8")" && "$(cat "$TMP/out8")" != *DONE* ]] \
    && grep -q "closed/archived while waiting" "$TMP/err8" \
    && ok "$label behind a close refuses (rc 2), writes nothing, recreates nothing" \
    || bad "$label behind a close: rc=$rc old-path=$([[ -e "$wl" ]] && echo PRESENT || echo gone) out=$(cat "$TMP/out8") err=$(cat "$TMP/err8")"
}
gone_cell "a plain advance" worklist-advance.sh
gone_cell "a plain --append" worklist-advance.sh --append "inline:x"
gone_cell "a second close" worklist-close.sh

# 11 · losing the wait writes nothing, in both scripts (AIDEX_WL_LOCK_WAIT: seconds, default
# 30). The holder keeps the lock while each script gives up.
WL11="$(mkwl waiting 'mode: sweep\n')"; L11="$( . "$DIR/_lib.sh"; wl_lock_file "$WL11")"; s11="$(cksum < "$WL11")"; t0=$SECONDS
( . "$DIR/_lib.sh"; lock_take "$L11" 5 || exit 1
  r=0; AIDEX_WL_LOCK_WAIT=1 bash "$DIR/worklist-advance.sh" "$WL11" --append "backlog:BL-11 — w" 9>&- >/dev/null 2>"$TMP/err11a" || r=$?; echo $r > "$TMP/rc11a"
  r=0; AIDEX_WL_LOCK_WAIT=1 bash "$DIR/worklist-close.sh" "$WL11" 9>&- >/dev/null 2>"$TMP/err11c" || r=$?; echo $r > "$TMP/rc11c" )
el=$((SECONDS - t0))
for x in a c; do
  [[ "$(cat "$TMP/rc11$x")" == 2 && $el -lt 10 && "$(cksum < "$WL11")" == "$s11" ]] && grep -q "could not lock $WL11" "$TMP/err11$x" \
    && ok "$([[ $x == a ]] && echo advance || echo close) that loses the wait exits 2, list byte-identical" \
    || bad "lost wait ($x): rc=$(cat "$TMP/rc11$x") after ${el}s $(cat "$TMP/err11$x")"
done
[[ ! -e "$P/.context/worklists/_archive/$(basename "$WL11")" ]] || bad "11: the close archived the list without the lock"

# 12 · a lock directory that is a symlink is refused, not followed (another user could plant
# one in a shared temp dir), and nothing is written
mkdir -p "$TMP/evil" "$TMP/elsewhere"; ln -s "$TMP/elsewhere" "$TMP/evil/aidex.locks.$EUID"
WL12="$(mkwl symlock 'mode: sweep\n')"; s12="$(cksum < "$WL12")"
TMPDIR="$TMP/evil" bash "$DIR/worklist-advance.sh" "$WL12" --append "backlog:BL-12 — s" >/dev/null 2>"$TMP/err12"; RC=$?
[[ $RC -eq 2 && "$(cksum < "$WL12")" == "$s12" && -z "$(ls -A "$TMP/elsewhere")" ]] && grep -q "symlink" "$TMP/err12" \
  && ok "a symlinked lock directory is refused, list byte-identical, nothing created through it" \
  || bad "symlinked lock dir: rc=$RC elsewhere=$(ls -A "$TMP/elsewhere") $(cat "$TMP/err12")"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — worklist-advance concurrency: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
