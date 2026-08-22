#!/usr/bin/env bash
# test-slot-lock.sh — the slot claim directory is shared, mutable state in /tmp,
# and all three of its guarantees were missing.
#
# 1. THE LOCK HAD NO OWNER. It was a bare `mkdir` directory with no trap and no
#    staleness reclamation, so one interrupted `new` wedged slot allocation for
#    the whole project until somebody deleted the directory by hand. The
#    lifecycle lock had already learned this (a stale one kept a gate green for
#    seventeen days); the slot lock had not.
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
# Run with: bash skills/aidex-worktree/tests/test-slot-lock.sh

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
SLOTS="$TMP/slots"; SD="$SLOTS/aidex-wt-slots-lockproj"
mkdir -p "$SD"

# The full 30s acquire wait is what this test would otherwise cost the default
# suite, which is meant to run in seconds. The wait is shortened, not removed:
# what the cases assert is WHICH owner gets reclaimed, not how long we wait.
run_wt() { out="$( cd "$PROJ" && TMPDIR="$SLOTS" AIDEX_WT_LOCK_TRIES=8 bash "$WT" "$@" 2>&1 )"; RC=$?; }

# --- 1. a lock whose owner is dead must be reclaimed, not waited out --------
# A PID that cannot exist stands in for the interrupted run. Before the fix the
# allocator waited its full 30s and then died telling the user to delete the
# lock by hand; after it, allocation proceeds.
rm -rf "$SD/.lock"; ln -s 999999 "$SD/.lock"
start=$SECONDS
run_wt new stale-lock --branch wt/stale
elapsed=$((SECONDS - start))
grep -qi 'could not acquire the slot lock' <<<"$out" \
  && fail "stale lock: an owner that is gone must be reclaimed, got: $out"
[[ "$elapsed" -lt 3 ]] \
  || fail "stale lock: waited ${elapsed}s — the lock was not reclaimed"
rm -rf "$SD/.lock"

# --- 2. a live owner still holds the lock ----------------------------------
# The reclamation must not be a blanket "steal any lock": that would reintroduce
# the collision the lock exists to prevent.
sleep 60 & LIVE=$!
rm -rf "$SD/.lock"; ln -s "$LIVE" "$SD/.lock"
run_wt new live-lock --branch wt/live
kill "$LIVE" 2>/dev/null; wait "$LIVE" 2>/dev/null
grep -qi 'could not acquire the slot lock' <<<"$out" \
  || fail "live lock: a lock held by a RUNNING process must not be stolen, got: $out"
rm -rf "$SD/.lock"

# --- 3. a pre-planted claim symlink is refused, and is not "free" -----------
TARGET="$TMP/victim"
rm -f "$SD"/slot-* "$TARGET"
ln -s "$TARGET" "$SD/slot-1"
run_wt new planted --branch wt/planted --slot 1
[[ ! -e "$TARGET" ]] \
  || fail "planted symlink: the claim write followed it and created $TARGET"
grep -qi 'symlink' <<<"$out" \
  || fail "planted symlink: must be refused by name, got: $out"
rm -f "$SD"/slot-*

# --- 4. up takes the same lock as new --------------------------------------
# Named at the CALL SITE. `up`'s read-check-write is the half that was unlocked,
# and a body-level assertion on the helper cannot see that.
awk '/^if \[\[ "\$cmd" == "up" \]\]/,/^# -+ new/' "$WT" | grep -q 'acquire_slot_lock' \
  || fail "up: its slot claim must be taken under acquire_slot_lock"
awk '/^if \[\[ "\$cmd" == "up" \]\]/,/^# -+ new/' "$WT" | grep -q 'release_slot_lock' \
  || fail "up: it must release the slot lock it took"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — slot lock: dead owners reclaimed, live owners respected, planted claim symlinks refused, up locks too"
