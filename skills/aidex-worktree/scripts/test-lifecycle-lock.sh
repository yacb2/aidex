#!/usr/bin/env bash
# test-lifecycle-lock.sh — the singleton guard of test-worktree-lifecycle.sh.
#
# The bug this pins down (field-observed 2026-08-13): the lifecycle suite's run
# lock is a bare `mkdir` directory carrying no owner. A run that dies before its
# `rmdir` leaves it forever, and every later invocation prints
# `SKIP — another test-worktree-lifecycle.sh is running` and exits **0**. The
# lock found in the wild had been planted on 2026-07-27 and had been making the
# gate report success without executing anything for seventeen days.
#
# A gate that cannot fail is not a gate, so this pins two properties:
#   - a skip is distinguishable from a pass — it exits NON-ZERO
#   - a lock whose owner is dead is reclaimed, while a live owner is still
#     refused (the fixture-corruption guard the lock exists for stays intact)
#
# It drives the real script through two seams rather than reimplementing the
# logic: AIDEX_WT_LIFECYCLE_LOCK points the lock somewhere private so this test
# can never disturb a concurrent real run, and AIDEX_WT_LIFECYCLE_LOCK_PROBE
# exits right after acquisition so a case costs milliseconds instead of the
# full Docker cycle.
#
# Run with: bash skills/aidex-worktree/scripts/test-lifecycle-lock.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SUT="$DIR/test-worktree-lifecycle.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
LOCK="$TMP/lifecycle.lock"
LIVE_PID=""
cleanup() {
  [[ -n "$LIVE_PID" ]] && kill "$LIVE_PID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "SKIP — docker unavailable; the script under test exits before the lock"
  exit 2
fi

# Drive the real script, lock redirected and stopped at acquisition.
probe() {
  AIDEX_WT_LIFECYCLE_LOCK="$LOCK" AIDEX_WT_LIFECYCLE_LOCK_PROBE=1 \
    bash "$SUT" 2>&1
}

# The lock is a symlink whose target is the owner PID, so it is DANGLING by
# design — `-e` is false on it and only `-L` sees it.
# --- 1. no lock: acquires, reports it, and releases on the way out -----------
rm -rf "$LOCK"
out="$(probe)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "no lock: expected exit 0, got $rc"
grep -q 'LOCK-ACQUIRED' <<<"$out" || fail "no lock: expected LOCK-ACQUIRED, got: $out"
[[ -L "$LOCK" ]] && fail "no lock: the lock survived the run"

# --- 2. live owner: still refused, and the refusal is NOT exit 0 -------------
# This is the property the guard was built for; the fix must not trade it away.
# `trap - EXIT` inside every background subshell, without exception. A `( ) &`
# child inherits this script's EXIT trap, so a job killed before it reaches its
# `exec` runs OUR cleanup and deletes $TMP out from under the next case. That
# cost an hour: case 3 failed with `ln: … No such file or directory` while the
# same three lines passed in isolation.
( trap - EXIT; exec sleep 300 ) & LIVE_PID=$!
rm -rf "$LOCK"; ln -s "$LIVE_PID" "$LOCK"
out="$(probe)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "live owner: a skipped run must not exit 0"
grep -qi 'SKIP' <<<"$out" || fail "live owner: expected a SKIP message, got: $out"
[[ -L "$LOCK" ]] || fail "live owner: the refused run removed someone else's lock"
[[ "$(readlink "$LOCK")" == "$LIVE_PID" ]] || fail "live owner: the lock changed hands"
kill "$LIVE_PID" 2>/dev/null; wait "$LIVE_PID" 2>/dev/null; LIVE_PID=""

# --- 3. dead owner: reclaimed, not honored forever --------------------------
# Let it exit on its own rather than killing it — a PID that died naturally is
# just as dead, and nothing races the fork.
( trap - EXIT; exit 0 ) & dead=$!
wait "$dead" 2>/dev/null
rm -rf "$LOCK"; ln -s "$dead" "$LOCK"
out="$(probe)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "dead owner: a stale lock must be reclaimed, got exit $rc"
grep -q 'LOCK-ACQUIRED' <<<"$out" || fail "dead owner: expected LOCK-ACQUIRED, got: $out"

# --- 4. legacy directory lock: the shape found in the wild ------------------
# The 17-day lock was a bare `mkdir` directory naming nobody. It predates PID
# anchoring, so it must be reclaimed too, or the fix misses the exact instance
# that motivated it.
rm -rf "$LOCK"; mkdir -p "$LOCK"
out="$(probe)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "legacy dir lock: must be reclaimed, got exit $rc"
grep -q 'LOCK-ACQUIRED' <<<"$out" || fail "legacy dir lock: expected LOCK-ACQUIRED, got: $out"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — lifecycle lock: skip exits non-zero, live owner refused, stale and ownerless locks reclaimed"
