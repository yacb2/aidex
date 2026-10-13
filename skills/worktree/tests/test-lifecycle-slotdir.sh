#!/usr/bin/env bash
# test-lifecycle-slotdir.sh -- the lifecycle test must read the slot directory
# worktree.sh really writes (BL-775, worktree-c33).
#
# test-worktree-lifecycle.sh needs a real Docker daemon, so nothing in the default
# suite runs it. It built the slot dir with a colon (`aidex:wt-slots-wtfix`) while
# SLOTDIR_FOR writes `aidex-wt-slots-<project>`: its `claims()` read a directory
# that never exists, so "==0" claim assertions passed vacuously and the "==1"/"==4"
# ones could never pass. This test evaluates BOTH definitions and compares them,
# so it runs with no daemon.
#
# Run with: bash skills/worktree/tests/test-lifecycle-slotdir.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LIFECYCLE="$DIR/../scripts/test-worktree-lifecycle.sh"
WT="$DIR/../scripts/worktree.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# The project name the lifecycle test really uses: the basename of its WS assignment.
PROJECT="$(sed -n 's|^WS="\$TMP/\(.*\)"$|\1|p' "$LIFECYCLE" | sed -n 1p)"
[[ -n "$PROJECT" ]] || fail "fixture: no WS=\"\$TMP/<name>\" assignment found in the lifecycle test"

# What the writer says, for that project under TMPDIR=/t.
want="$(eval "$(sed -n '/^SLOTDIR_FOR()/p' "$WT")"; PROJECT="$PROJECT" TMPDIR=/t SLOTDIR_FOR)"
[[ "$want" == "/t/aidex-wt-slots-$PROJECT" ]] || fail "fixture: SLOTDIR_FOR gave '$want', the premise of this test is stale"

# What the lifecycle test reads.
got="$(TMPDIR=/t; eval "$(sed -n '/^SLOTNAME=/p' "$LIFECYCLE")"; printf '%s' "$SLOTDIR")"
[[ "$got" == "$want" ]] || fail "the lifecycle test reads '$got' but worktree.sh writes '$want'"

# Its cleanup and purge must name the same directory, or a stale claim survives.
grep -q 'aidex:wt-slots' "$LIFECYCLE" && fail "the lifecycle test still names a colon slot dir (aidex:wt-slots)"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — lifecycle slot dir: the lifecycle test reads the directory worktree.sh writes"
