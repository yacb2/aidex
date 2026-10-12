#!/usr/bin/env bash
# test-lock-run.sh — lock_take (_lib.sh), the kernel lock behind every read-modify-write
# of a shared file. It replaced mkdir locks whose age-based takeover lost data (two
# waiters behind a killed holder both removed the lock; a future mtime deleted a live one).
# Layer: unit, real processes (the property is what concurrent processes see; no repo).
# Rows: T1 killed holder, T2 no takeover, T3 serialisation, T4 long live hold, T5 timeout,
# T6 no removal code, T7 bad wait, no perl, re-entrancy, section take/drop with nested fds,
# a killed bash holder. The leftover old-style lock directory row lives in
# audit/tests/test-escalation.sh, where that name is chosen.
#
# Run with: bash skills/conventions/scripts/test-lock-run.sh  (about 25 s: T4 holds 12 s)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP"
L="$TMP/data.lock" D="$TMP/data" E="$TMP/err" LOG="$TMP/log"
export LIB="$HERE/_lib.sh"

# w.sh <lock> <wait> <data> <tag> [sleep] — shape (b): append <tag> as a read-copy-rename
# (the callers' shape; a plain >> append is atomic and would pass with no lock at all),
# printing the line count it read first.
W="$TMP/w.sh"
cat > "$W" <<'EOF'
. "$LIB"
( lock_take "$1" "$2" || exit $?
  seen="$(wc -l < "$3" | tr -d ' ')"
  tmp="$(mktemp "$3.XXXXXX")"; cat "$3" > "$tmp"
  [[ -z "${5:-}" ]] || sleep "$5"
  printf '%s\n' "$4" >> "$tmp"; mv "$tmp" "$3"
  echo "$seen" )
EOF

# hold <lockfile> <seconds> [log] [data] — a perl flock holder in the background (HPID),
# returned once it holds the lock. With <data> it reads the file at once and writes it back
# plus "holder" at the end of the hold (a read-modify-write spanning the hold); it appends
# "released" to <log> as it lets go. The fifo is opened first: a holder that dies early
# ends the read instead of hanging it.
hold() {
  local fifo="$TMP/hold.$RANDOM"; mkfifo "$fifo"
  perl -MFcntl=:flock -e 'my ($lock, $fifo, $secs, $log, $data) = @ARGV; my $old = "";
    open(R, ">", $fifo) or die; open(H, ">>", $lock) or die; flock(H, LOCK_EX) or die;
    if ($data) { open(I, "<", $data) or die; local $/; $old = <I>; close I }
    print R "held\n"; close R; sleep $secs;
    if ($data) { open(O, ">", $data) or die; print O $old, "holder\n"; close O }
    if ($log) { open(G, ">>", $log); print G "released\n"; close G }' \
    "$1" "$fifo" "$2" "${3:-}" "${4:-}" &
  HPID=$!; read -r _ < "$fifo"; rm -f "$fifo"
}
killhold() { kill -9 "$HPID" 2>/dev/null; { wait "$HPID"; } 2>/dev/null; }

# T1 + T2: ten waiters behind a holder killed with -9, ten times: every row lands, every
# waiter exits 0, nobody reports a takeover
t1=0
: > "$E"
for r in 1 2 3 4 5 6 7 8 9 10; do
  printf 'head\n' > "$D"
  hold "$L" 600
  for i in 1 2 3 4 5 6 7 8 9 10; do
    { bash "$W" "$L" 30 "$D" "row$i" >/dev/null || echo "rc $? row$i" >&2; } 2>>"$E" &
  done
  sleep 0.3; killhold; wait
  [[ "$(grep -c '^row' "$D")" == 10 && "$(sed -n 1p "$D")" == head ]] || t1=$((t1 + 1))
done
[[ $t1 -eq 0 ]] || fail "T1: $t1 of 10 rounds lost a row behind a killed holder"
[[ ! -s "$E" ]] || fail "T2: every waiter should exit 0 with no takeover, stderr: $(sort "$E" | uniq -c | head -5)"

# T3: ten writers that sleep between their read and their write saw 0..9 lines
: > "$D"; S="$TMP/seen"; : > "$S"
for i in 1 2 3 4 5 6 7 8 9 10; do bash "$W" "$L" 30 "$D" "row$i" 0.05 >> "$S" & done
wait
[[ "$(sort -n "$S" | tr '\n' ' ')" == "0 1 2 3 4 5 6 7 8 9 " ]] \
  || fail "T3: the writers should be serialised (seen 0..9), got: $(sort -n "$S" | tr '\n' ' ')"

# T4: a live hold longer than the old stale windows (5 and 10 s) is waited out, never
# taken over: the waiter writes after the holder lets go, and the holder's write survives
printf 'head\n' > "$D"; : > "$LOG"
hold "$L" 12 "$LOG" "$D"
out="$(bash "$W" "$L" 30 "$D" waiter 2>&1)"; rc=$?; echo written >> "$LOG"
{ wait "$HPID"; } 2>/dev/null
[[ $rc -eq 0 && "$(tr '\n' ' ' < "$LOG")" == "released written " ]] \
  || fail "T4: the waiter should write after a 12 s holder exits, rc $rc, order: $(tr '\n' ' ' < "$LOG") $out"
[[ "$(tr '\n' ' ' < "$D")" == "head holder waiter " ]] || fail "T4: the holder's write should survive, data: $(tr '\n' ' ' < "$D")"

# T5: a holder still alive after the wait: the distinct status, the lock named, nothing written
printf 'head\n' > "$D"; before="$(cksum < "$D")"
hold "$L" 5
out="$(bash "$W" "$L" 1 "$D" late 2>&1)"; rc=$?
kill -0 "$HPID" 2>/dev/null; alive=$?
killhold
[[ $rc -eq 75 && $alive -eq 0 ]] || fail "T5: a 1 s wait on a live holder should return 75 (holder alive: $alive), rc $rc: $out"
[[ "$out" == *"$L"* ]] || fail "T5: the timeout message should name the lock file: $out"
[[ "$(cksum < "$D")" == "$before" ]] || fail "T5: a timed-out waiter wrote: $(tr '\n' ' ' < "$D")"

# T6: release is the process exit; nothing removes or ages a lock file
[[ "$(sed -n '/^lock_take()/,/^}/p' "$LIB" | grep -cE 'rmdir|unlink|(^|[[:space:];&|])rm |stat |take ?over|took over')" == 0 ]] \
  || fail "T6: lock_take removes or ages a lock"

# T7: a wait that is not whole seconds is one error, not an instant timeout
printf 'head\n' > "$D"; before="$(cksum < "$D")"
for bad in abc 0 1.5 ''; do
  out="$(bash "$W" "$L" "$bad" "$D" x 2>&1)"; rc=$?
  [[ $rc -eq 2 && "$(printf '%s\n' "$out" | grep -c .)" == 1 && "$out" == *"whole seconds"* ]] \
    || fail "T7: wait '$bad' should be one error with rc 2, rc $rc: $out"
done
[[ "$(cksum < "$D")" == "$before" ]] || fail "T7: a refused wait wrote"

# no perl: a clear error, never a weaker lock
mkdir -p "$TMP/noperl"
out="$(PATH="$TMP/noperl" "$BASH" "$W" "$L" 5 "$D" x 2>&1)"; rc=$?
[[ $rc -eq 2 && "$out" == *"perl is required"* && "$out" == *"$L"* ]] || fail "no perl: should refuse with rc 2, rc $rc: $out"
[[ "$(cksum < "$D")" == "$before" ]] || fail "no perl: wrote without a lock"

# re-entrancy, shape (a): a script holding the lock runs a child that asks for the same
# file (spelled another way) and gets it at once; a DIFFERENT lock is still waited for
A="$TMP/a.sh"
cat > "$A" <<'EOF'
. "$LIB"
lock_take "$1" "$2" || exit $?
printf '%s\n' "$3" >> "$4"
if [[ "$3" == parent ]]; then
  bash "$0" "$(dirname "$1")/./$(basename "$1")" 2 child "$4" || exit $?
  lock_take "$5" 1 8 || echo "other: $?"
fi
EOF
: > "$D"
hold "$TMP/other.lock" 30
out="$(bash "$A" "$L" 30 parent "$D" "$TMP/other.lock" 2>&1)"; rc=$?
killhold
[[ $rc -eq 0 && "$(tr '\n' ' ' < "$D")" == "parent child " ]] \
  || fail "re-entrancy: the child of a holder should not wait on its parent, rc $rc, data: $(tr '\n' ' ' < "$D") $out"
[[ "$out" == *"other: 75"* ]] || fail "re-entrancy: the marker must be per lock, another lock is still waited for: $out"

# probe <lockfile> — 0 when another process could take the lock right now
probe() { perl -MFcntl=:flock -e 'open(H, ">>", shift) or exit 2; exit(flock(H, LOCK_EX | LOCK_NB) ? 0 : 1)' "$1"; }

# section: the lock outlives the perl that took it (the shell's fd holds it) and goes
# when lock_drop closes the fd; nested sections on two files take two fds, and the same
# fd twice in one shell is refused (a second exec there would drop the first lock); a
# re-take after the drop really locks (a marker left behind would make it a no-op); a
# re-entrant take of the same lock in the same shell and its drop are one balanced pair
out="$(
  . "$LIB"; set +e; exec 2>&1
  lock_take "$L" 5 || exit 1
  probe "$L"; echo "held:$?"
  lock_take "$L" 5; lock_drop; probe "$L"; echo "nested:$?"
  lock_take "$TMP/inner.lock" 5 8 || exit 1
  probe "$TMP/inner.lock"; echo "inner:$?"
  lock_take "$TMP/third.lock" 5 8; echo "samefd:$?"
  lock_drop 8; probe "$TMP/inner.lock"; echo "innerdrop:$?"
  probe "$L"; echo "outer:$?"
  lock_drop; probe "$L"; echo "drop:$?"
  lock_take "$L" 5; probe "$L"; echo "retake:$?"
  probe "$TMP/third.lock"; echo "third:$?"
)"
want="held:1 nested:1 inner:1 samefd:2 innerdrop:0 outer:1 drop:0 retake:1 third:0"
[[ "$(printf '%s\n' "$out" | grep -E '^[a-z]+:[0-9]+$' | tr '\n' ' ')" == "$want " ]] \
  || fail "section: want $want, got: $(printf '%s\n' "$out" | tr '\n' ' ')"
[[ "$out" == *"fd 8 already holds a lock"* ]] || fail "section: the same-fd refusal should say so: $out"

# section, cross-fd: this shell holds A on fd 9 and B on fd 8; taking B again on fd 9 is
# refused before fd 9 is touched (its drop would otherwise close A's fd), both stay held
out="$(
  . "$LIB"; set +e; exec 2>&1
  lock_take "$TMP/a.flock" 5 9 || exit 1; lock_take "$TMP/b.flock" 5 8 || exit 1
  lock_take "$TMP/b.flock" 5; echo "cross:$?"
  probe "$TMP/a.flock"; echo "a:$?"; probe "$TMP/b.flock"; echo "b:$?"
  lock_drop 8; lock_drop 9
  probe "$TMP/a.flock"; echo "afree:$?"; probe "$TMP/b.flock"; echo "bfree:$?"
)"
want="cross:2 a:1 b:1 afree:0 bfree:0"
[[ "$(printf '%s\n' "$out" | grep -E '^[a-z]+:[0-9]+$' | tr '\n' ' ')" == "$want " ]] \
  || fail "section cross-fd: want $want, got: $(printf '%s\n' "$out" | tr '\n' ' ')"
[[ "$out" == *"$TMP/b.flock"*"fd 8"*"fd 9"* || "$out" == *"$TMP/b.flock"*"fd 9"*"fd 8"* ]] \
  || fail "section cross-fd: the refusal should name the lock file and both fds: $out"

# section, crashed holder: a bash holding the lock through its fd is killed with -9 (it
# waits on a builtin read, so no child of it inherits the fd); a 5 s waiter gets the lock
fifo="$TMP/bash-held"; gate="$TMP/bash-gate"; mkfifo "$fifo" "$gate"
bash -c '. "$LIB"; lock_take "$1" 5 || exit 1; echo held > "$2"; read -r _ < "$3"' _ "$L" "$fifo" "$gate" &
BPID=$!; read -r _ < "$fifo"
probe "$L"; before=$?
kill -9 "$BPID"; { wait "$BPID"; } 2>/dev/null
out="$( . "$LIB"; lock_take "$L" 5 2>&1 && echo got )"
[[ $before -eq 1 && "$out" == got ]] || fail "section crash: a killed bash holder should release (held before: $before): $out"

# a child started without the fd (`9>&-`) inherits the marker but not the lock: once its
# parent has let go and another run holds the lock, the child must wait, not trust the marker
C="$TMP/c.sh"; gate="$TMP/child-gate"; res="$TMP/child-res"; mkfifo "$gate" "$res"
cat > "$C" <<'EOF'
. "$LIB"; set +e
read -r _ < "$2"
lock_take "$1" 2 2>/dev/null; echo "child:$?" > "$3"
EOF
( . "$LIB"; lock_take "$L" 5 || exit 1; bash "$C" "$L" "$gate" "$res" 9>&- & )
hold "$L" 30
echo go > "$gate"; read -r got < "$res"
killhold
[[ "$got" == "child:75" ]] || fail "marker without fd: the child should wait for the other run's lock, got: $got"

if [[ $failures -gt 0 ]]; then printf '%d failure(s)\n' "$failures"; exit 1; fi
echo "OK — lock_take: killed holder x10 (10 waiters), no takeover, serialised 0..9, 12 s live hold waited out, timeout 75, no removal code, bad wait, no perl, re-entrant per lock, section drop + nested fds + balanced re-entry + cross-fd refused, killed bash holder, marker checked against the fd"
