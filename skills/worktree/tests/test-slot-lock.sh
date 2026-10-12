#!/usr/bin/env bash
# test-slot-lock.sh — the slot claim directory is shared, mutable state in /tmp,
# and all three of its guarantees were missing.
#
# 1. THE LOCK HAD NO OWNER. It was a bare `mkdir` directory with no trap and no
#    staleness reclamation, so one interrupted `new` wedged slot allocation for
#    the whole project until somebody deleted the directory by hand. The
#    lifecycle lock had already learned this (a stale one kept a gate green for
#    seventeen days); the slot lock had not. Its PID-symlink successor reclaimed
#    a dead owner's lock, and every reclaim scheme let two contenders both hold
#    it (worktree-c32, then its ticket fix). It is now a kernel lock (`lock_take`
#    on `.flock`): a killed holder's lock goes with its process, nothing is
#    reclaimed, so there is no stale state to race over.
#
# 2. `up` NEVER TOOK IT. It re-asserted its claim with a read-check-write and no
#    lock at all, so it raced `new`'s locked allocator: two worktrees could land
#    on one slot with only one of them named in the claim file.
#
# 3. THE CLAIM PATH WAS UNCHECKED. A pre-planted dangling symlink named `slot-N`
#    turns the claim write into an arbitrary-file create/truncate as this user,
#    and a dangling symlink is not `-e`, so it also read as a FREE slot.
#
# The claim directory's PATH is deliberately not uid-scoped: that would make
# every existing claim invisible, and a live worktree's `down` would then find no
# slot recorded. This is hardening, not a live failure.
#
# Every case runs with its own TMPDIR. No daemon needed.
#
# Run with: bash skills/worktree/tests/test-slot-lock.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$DIR/../scripts/worktree.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PROJ="$TMP/lockproj"
mkdir -p "$PROJ/.context/worktrees" "$PROJ/backend"
cat > "$PROJ/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_PORT_VARS="DB_PORT=6400"
WT_PORT_STRIDE=100
WT_MAX_SLOTS=4
ENV
# `backend` is not a git repo: each `new` below fails in worktree-multi AFTER
# its slot is reserved, which is all these cases need. `--base main` keeps it
# from being refused earlier for want of a default branch to fork from.
SLOTS="$TMP/slots"; SD="$SLOTS/aidex-wt-slots-lockproj"
mkdir -p "$SD"

# The full 30s acquire wait is what this test would otherwise cost the default
# suite, which is meant to run in seconds. The wait is shortened, not removed:
# what the cases assert is WHICH owner gets reclaimed, not how long we wait.
# Docker is stubbed for every case: `up` starts a stack and a failed `new` rolls
# one back, and neither may reach a real daemon from a unit test.
BIN="$TMP/bin"; mkdir -p "$BIN"
mk_docker() { printf '%s\n' "$1" > "$BIN/docker"; chmod +x "$BIN/docker"; }
mk_docker '#!/bin/sh
exit 0'
run_wt() { out="$( cd "$PROJ" && TMPDIR="$SLOTS" PATH="$BIN:$PATH" AIDEX_WT_LOCK_WAIT=1 bash "$WT" "$@" 2>&1 )"; RC=$?; }

# A live run holding the slot lock: a process that took it through the same
# `lock_take` and then became `sleep`, so the lock lives exactly as long as
# $HOLDER does. Signalled on a FIFO opened read-write, so a holder that never
# gets the lock fails this fixture instead of hanging the suite.
LIB="$DIR/../../conventions/scripts/_lib.sh"
HELD="$TMP/held"; mkfifo "$HELD"
hold_lock() {  # hold_lock <lockfile>; sets HOLDER
  ( trap - EXIT; exec bash -c '. "$1"; lock_take "$2" 5 || exit 1; echo held > "$3"; exec sleep 60' _ "$LIB" "$1" "$HELD" ) &
  HOLDER=$!
  read -t 10 -r _ <> "$HELD" || fail "fixture: the lock holder never took $1"
}

# --- 1. a run that died holding the lock does not wedge allocation ----------
# Killed mid-section, with a PID-symlink `.lock` from the old scheme naming a
# dead PID beside it. Before, the allocator waited its full 30 s and died
# telling the user to delete the lock by hand; now allocation proceeds at once.
rm -f "$SD/.lock"; ln -s 999999 "$SD/.lock"
hold_lock "$SD/.flock"; kill -9 "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
start=$SECONDS
run_wt new stale-lock --branch wt/stale --base main
elapsed=$((SECONDS - start))
grep -q 'held by another run' <<<"$out" \
  && fail "dead holder: a lock whose run was killed must not block, got: $out"
[[ "$elapsed" -lt 3 ]] || fail "dead holder: waited ${elapsed}s for a lock nobody holds"
grep -q 'slot 1 -> DB_PORT=6500' <<<"$out" || fail "dead holder: new must reserve slot 1 under the freed lock: $out"
rm -f "$SD/.lock" "$SD"/slot-*

# --- 1b. a `new` killed while its reaper waits on docker does not wedge it --
# The reaper asks `docker ps` about a dead claim while holding the lock. With
# the daemon wedged, `docker ps` hangs; `9>&-` on docker alone left fd 9 open in
# the `$( )` subshell, so once `new` was killed that orphan held the lock and
# every later new/up/down exited 2 "held by another run" (r2 F1). And with no
# timeout, the claim the listing was about must survive the listing's failure.
# The stub ignores SIGALRM as the real docker CLI does (a Go binary): an alarm
# that only signals the listing never stops it, so the timeout must kill it.
( trap - EXIT; exit 0 ) & dead=$!; wait "$dead" 2>/dev/null
printf '%s gone\n' "$dead" > "$SD/slot-3"
# Both ends open the FIFO read-write: a later `docker ps` with no reader waiting
# must not block on it, and the read here is bounded.
PSFIFO="$TMP/ps-entered"; mkfifo "$PSFIFO"
mk_docker "#!/bin/sh
case \"\$1\" in ps) trap '' ALRM; echo \$\$ >> '$TMP/ps.pids'; echo go 1<> '$PSFIFO'; exec sleep 30 ;; esac
exit 0"
( trap - EXIT; cd "$PROJ" && TMPDIR="$SLOTS" PATH="$BIN:$PATH" exec bash "$WT" new first --branch wt/first --base main >/dev/null 2>&1 ) &
NEW=$!
read -t 10 -r _ <> "$PSFIFO" || fail "fd9 fixture: new never reached the reaper's docker ps"
kill -TERM "$NEW" 2>/dev/null; wait "$NEW" 2>/dev/null
start=$SECONDS
AIDEX_DOCKER_TIMEOUT=1 run_wt new second --branch wt/second --base main
elapsed=$((SECONDS - start))
kill $(cat "$TMP/ps.pids" 2>/dev/null) 2>/dev/null
grep -q 'held by another run' <<<"$out" \
  && fail "fd9: a new killed during the reaper's docker ps left the slot lock held: $out"
grep -q 'slot 1 -> DB_PORT=6500' <<<"$out" || fail "fd9: the next new must reserve slot 1: $out"
[[ "$elapsed" -lt 10 ]] || fail "docker timeout: the reaper waited ${elapsed}s on a hung docker ps"
[[ -e "$SD/slot-3" ]] || fail "docker timeout: a claim was reaped on a docker ps that timed out: $out"
mk_docker '#!/bin/sh
exit 0'
rm -f "$SD"/slot-*

# --- 2. a live holder keeps the lock: nobody runs the section beside it -----
# The c32 property. Every reclaim of a "stale" lock was a way for two
# contenders to both hold it; a live holder is now simply waited for.
hold_lock "$SD/.flock"
run_wt new live-lock --branch wt/live --base main
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null
[[ "$RC" -eq 2 ]] || fail "live lock: new must exit 2 while a live run holds the slot lock, got $RC: $out"
grep -q "error: $SD/.flock is held by another run (waited 1 s)" <<<"$out" \
  || fail "live lock: a lock held by a RUNNING process must not be stolen, got: $out"
[[ -z "$(ls "$SD" | grep '^slot-')" ]] || fail "live lock: a claim was written without the lock: $(ls "$SD")"

# --- 3. a pre-planted claim symlink is refused, and is not "free" -----------
TARGET="$TMP/victim"
rm -f "$SD"/slot-* "$TARGET"
ln -s "$TARGET" "$SD/slot-1"
run_wt new planted --branch wt/planted --base main --slot 1
[[ ! -e "$TARGET" ]] \
  || fail "planted symlink: the claim write followed it and created $TARGET"
grep -qi 'symlink' <<<"$out" \
  || fail "planted symlink: must be refused by name, got: $out"
rm -f "$SD"/slot-*

# --- 4. up takes the same lock as new --------------------------------------
# Named at the CALL SITE. `up`'s read-check-write is the half that was unlocked,
# and a body-level assertion on the helper cannot see that.
awk '/^if \[\[ "\$cmd" == "up" \]\]/,/^# -+ new/' "$WT" | grep >/dev/null 'acquire_slot_lock' \
  || fail "up: its slot claim must be taken under acquire_slot_lock"
awk '/^if \[\[ "\$cmd" == "up" \]\]/,/^# -+ new/' "$WT" | grep >/dev/null 'release_slot_lock' \
  || fail "up: it must release the slot lock it took"

# --- 6. worktree-c37: a refused slot directory stops the command there -------
# `die` inside `$(ensure_slotdir)` ended only the subshell; SLOTDIR came back
# empty, the lock path became `/.lock`, and the reader got a 30 s wait and a
# second error about a lock at the filesystem root.
SLINK="$TMP/slots-link"; mkdir -p "$SLINK" "$TMP/elsewhere"
ln -s "$TMP/elsewhere" "$SLINK/aidex-wt-slots-lockproj"
mkdir -p "$TMP/lockproj-wt-c37u"; echo 2 > "$TMP/lockproj-wt-c37u/.wt-slot"
for args in "new c37n --branch wt/c37n --base main" "up c37u"; do
  out="$( cd "$PROJ" && TMPDIR="$SLINK" PATH="$BIN:$PATH" AIDEX_WT_LOCK_WAIT=1 bash "$WT" $args 2>&1 )"; RC=$?
  [[ "$RC" -eq 2 ]] || fail "c37 ${args%% *}: a symlinked slot directory must exit 2, got $RC: $out"
  grep -q "error: refusing slot directory $SLINK/aidex-wt-slots-lockproj: it is a symlink" <<<"$out" \
    || fail "c37 ${args%% *}: the refusal must name the symlinked slot directory: $out"
  grep -q '/\.flock\|/\.lock' <<<"$out" \
    && fail "c37 ${args%% *}: the refusal went on to a lock at the filesystem root: $out"
done

# --- 7. worktree-c40: a claim whose PID was reused is not a live run ---------
# The reaper trusted a bare `kill -0`, so an abandoned claim whose PID now
# belongs to an unrelated process stayed forever. A claim carries the start
# time of the run that wrote it; a PID alive under another start time is dead.
# Two-field claims from before keep the bare `kill -0` reading.
# The start time is UTC whatever the zone of the run that reads it: `ps` prints
# local time, so a claim written under TZ=UTC read as dead under Asia/Tokyo and
# the reaper handed out a live run's slot (r1 F1). Slot 4's token is taken here
# in UTC and the reading run is in another zone.
sleep 60 & REUSED=$!
rm -f "$SD"/slot-*
printf '%s ghost MonJan100:00:001990\n' "$REUSED" > "$SD/slot-3"   # same PID, another run
printf '%s live %s\n' "$REUSED" "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$REUSED" | tr -d ' ')" > "$SD/slot-4"
printf '%s oldfmt\n' "$REUSED" > "$SD/slot-2"
TZ=Asia/Tokyo run_wt new c40 --branch wt/c40 --base main
kill "$REUSED" 2>/dev/null; wait "$REUSED" 2>/dev/null
[[ ! -e "$SD/slot-3" ]] || fail "c40: a claim whose PID was reused by another process was kept: $out"
[[ -e "$SD/slot-4" ]] || fail "c40: a live run's claim (start time taken in UTC) was reaped by a run under TZ=Asia/Tokyo: $(ls "$SD") $out"
[[ -e "$SD/slot-2" ]] || fail "c40: a two-field claim with a live PID must keep the old reading: $out"
grep -q 'slot 1 -> DB_PORT=6500' <<<"$out" || fail "c40: new must have reserved slot 1 after the reap: $out"

# --- 8. note C: the reaper does not read "docker ps failed" as "no containers" -
# A claim `down` withheld over an unreachable daemon was reaped by the next
# `new` while the daemon was still down: the empty output of a FAILED `docker
# ps` passed for proof that nothing remains. Only a successful listing reaps.
( trap - EXIT; exit 0 ) & dead=$!; wait "$dead" 2>/dev/null
rm -f "$SD"/slot-*
printf '%s withheld\n' "$dead" > "$SD/slot-3"
mk_docker '#!/bin/sh
exit 1'
run_wt new cnc --branch wt/cnc --base main
mk_docker '#!/bin/sh
exit 0'
[[ -e "$SD/slot-3" ]] || fail "note C: a withheld claim was reaped while docker ps could not list anything: $out"
grep -q 'slot 1 -> DB_PORT=6500' <<<"$out" || fail "note C: new must still reserve a free slot: $out"
rm -f "$SD"/slot-*

# --- 9. worktree-c35: up does not take a second slot for a worktree holding one --
# `up --slot 4` on a worktree claiming slot 2 wrote slot-4 and never released
# slot-2: one slot leaked until `down`. `up` resumes on the recorded slot, so a
# different --slot while a claim names this slug is refused, naming the slot.
mkdir -p "$TMP/lockproj-wt-mv"; echo 2 > "$TMP/lockproj-wt-mv/.wt-slot"
printf '%s mv\n' "$$" > "$SD/slot-2"
run_wt up mv --slot 4
[[ "$RC" -eq 2 ]] || fail "c35: up --slot 4 on a worktree holding slot 2 must exit 2, got $RC: $out"
grep -q "error: 'mv' already holds slot 2" <<<"$out" \
  || fail "c35: the refusal must name the slot the worktree holds: $out"
[[ ! -e "$SD/slot-4" ]] || fail "c35: a second claim was written for 'mv': $(ls "$SD")"
[[ "$(cat "$SD/slot-2")" == "$$ mv" ]] || fail "c35: the held claim on slot 2 was changed: $(cat "$SD/slot-2")"
[[ "$(cat "$TMP/lockproj-wt-mv/.wt-slot")" == 2 ]] || fail "c35: .wt-slot was rewritten by a refused up"
rm -f "$SD"/slot-*

# --- 10. up's refusal to write the slot env file leaves no claim it made -----
# write_wt_env refusing (a .env worktree.sh did not write) exited 2 AFTER `up`
# had claimed the slot, so a worktree that never held one kept slot 3 for a
# stack that never started. A claim `up` found already held is a resume: kept.
D10="$TMP/lockproj-wt-envx"; mkdir -p "$D10"; : > "$D10/.wt-slot"; printf 'FOO=bar\n' > "$D10/.env"
run_wt up envx --slot 3
[[ "$RC" -eq 2 ]] || fail "up env refusal: must exit 2, got $RC: $out"
grep -q "error: $D10/.env exists and was not written by worktree.sh" <<<"$out" \
  || fail "up env refusal: must name the .env it refused: $out"
[[ ! -e "$SD/slot-3" ]] || fail "up env refusal: the claim up had just made on slot 3 was left behind"
echo 3 > "$D10/.wt-slot"; printf '%s envx\n' "$$" > "$SD/slot-3"
run_wt up envx
[[ "$RC" -eq 2 ]] || fail "up env refusal (held): must exit 2, got $RC: $out"
[[ -e "$SD/slot-3" ]] || fail "up env refusal (held): a claim the worktree already held was released"
rm -f "$SD"/slot-*
# The same undo when the refusal is render_env_files' (a WT_ENV_RENDER entry
# whose template is missing), its own project so the config can name it.
RP="$TMP/rendproj"; RSD="$SLOTS/aidex-wt-slots-rendproj"
mkdir -p "$RP/.context/worktrees" "$TMP/rendproj-wt-rx"
sed 's/^WT_LINKS=.*/WT_ENV_RENDER="frontend\/.env.local"/' "$PROJ/.context/worktrees/config.env" > "$RP/.context/worktrees/config.env"
out="$( cd "$RP" && TMPDIR="$SLOTS" PATH="$BIN:$PATH" bash "$WT" up rx --slot 3 2>&1 )"; RC=$?
[[ "$RC" -eq 2 ]] || fail "up render refusal: must exit 2, got $RC: $out"
grep -q "template is missing: $RP/.context/worktrees/env-templates/frontend/.env.local.tmpl" <<<"$out" \
  || fail "up render refusal: must name the missing template: $out"
[[ ! -e "$RSD/slot-3" ]] || fail "up render refusal: the claim up had just made on slot 3 was left behind"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — slot lock: a killed holder does not wedge it, a live holder is waited for, planted claim symlinks refused, up locks too, a refused slot dir stops there, reused PIDs and failed listings judged right, up takes no second slot and undoes a fresh claim"
