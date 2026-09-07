#!/usr/bin/env bash
# test-worktree-suite-parity.sh — the suite must be citable from a linked worktree.
#
# Sweeps are mandated to run in a worktree (BL-333 fixed close-item.sh for the same
# reason). Two tests could never pass in one, so a worktree run scored 137/139 and a
# real regression there was indistinguishable from the two structural failures by the
# exit code alone (BL-338):
#
#   tests/test-spec-audit-complete.sh resolved the EchoLab audit table under its OWN
#   checkout's `.context/`. `.context/` is gitignored, so a worktree never has one and
#   the assertion could only fail there.
#
#   hooks/test-memory-save-gate.py built a project slug from the checkout's path and
#   needed `memory-sweep.py` to decode it back to a git repo. A worktree path does not
#   survive that round trip, so `unpushed-is-not-a-fact` stayed silent and the deny
#   assertion failed — while its MIRROR ("a reachable SHA is not denied") went on
#   PASSING, because a check that never runs denies nothing either. That vacuous pass is
#   what hid the breakage: one FAIL beside one PASS reads like a half-broken check
#   rather than a dead one.
#
# So this test asserts the two of them ARE runnable from a worktree, and — because a
# "did it exit 0" check is satisfied by a test that does nothing — that each one
# actually did its work: the spec gate must say how many specs it derived, and the gate
# suite must show the unreachable-SHA pair asserted in BOTH directions.
#
# It runs them against the WORKING TREE, not against HEAD: a fresh worktree checks out a
# commit, so every uncommitted file is copied in before the two run. Without that the
# test would grade the last commit and go green on a broken working tree.
#
# Run with: bash tests/test-worktree-suite-parity.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "SKIP: $REPO_ROOT is not a git checkout, so no worktree can be made of it"
  exit 2
fi

TMP="$(mktemp -d)"
WT="$TMP/wt"
cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "$WT" >/dev/null 2>&1
  git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

# Detached, so it never moves a branch another session is on.
if ! git -C "$REPO_ROOT" worktree add --detach -q "$WT" HEAD >/dev/null 2>&1; then
  fail "could not create a throwaway worktree of this repo"
  exit 1
fi

# The worktree is at HEAD; the suite under test is the working tree. Copy the difference.
copied=0
while IFS= read -r line; do
  path="${line:3}"
  case "$line" in *" -> "*) path="${line#*" -> "}" ;; esac   # a rename: grade the new name
  [ -f "$REPO_ROOT/$path" ] || continue                      # deletions and directories
  mkdir -p "$WT/$(dirname "$path")"
  cp "$REPO_ROOT/$path" "$WT/$path" && copied=$((copied + 1))
done < <(git -C "$REPO_ROOT" status --porcelain --untracked-files=all)
printf 'worktree at %s, %d uncommitted file(s) copied in\n' "$WT" "$copied"

# A worktree of this repo must not carry a `.context/` — if it did, the first defect
# would be invisible here and this test would be grading nothing.
if [ -d "$WT/.context" ]; then
  fail "the fixture is wrong: the worktree carries a .context/, so the gitignored-table case cannot be reproduced"
fi

# ---------- 1. the EchoLab spec-audit gate ----------
spec_out="$(cd "$WT" && bash tests/test-spec-audit-complete.sh 2>&1)"; spec_rc=$?

case "$spec_rc" in
  0)
    grep -q '^Derived [0-9]* non-playback specs' <<<"$spec_out" \
      || fail "test-spec-audit-complete.sh passed in a worktree without saying how many specs it derived — a green that asserted nothing: $spec_out"
    ;;
  2)
    grep -q '^SKIP' <<<"$spec_out" \
      || fail "test-spec-audit-complete.sh exited 2 without printing a SKIP reason: $spec_out"
    ;;
  *)
    fail "test-spec-audit-complete.sh exited $spec_rc in a worktree (expected 0, or 2 with a stated reason): $spec_out"
    ;;
esac

# The skip path itself, forced: with EchoLab absent there is nothing to ratchet against,
# and the runner's SKIP protocol is exit 2 plus a leading SKIP line — not exit 0, which
# would count a test that never ran as a pass.
skip_out="$(cd "$WT" && ECHOLAB_PATH="$TMP/no-echolab" bash tests/test-spec-audit-complete.sh 2>&1)"; skip_rc=$?
[ "$skip_rc" -eq 2 ] \
  || fail "with EchoLab absent test-spec-audit-complete.sh exited $skip_rc, expected 2 (the runner's SKIP protocol; exit 0 is counted as a pass)"
grep -q '^SKIP' <<<"$skip_out" \
  || fail "the EchoLab-absent skip printed no SKIP line: $skip_out"

# ---------- 2. the memory-save-gate suite ----------
mem_out="$(cd "$WT/hooks" && python3 test-memory-save-gate.py 2>&1)"; mem_rc=$?

if [ "$mem_rc" -ne 0 ]; then
  fail "hooks/test-memory-save-gate.py exited $mem_rc in a worktree:"
  printf '%s\n' "$mem_out" | grep -E '^  FAIL|^FAILED|^ALL' | head -20
fi

# Both halves of the unreachable-SHA pair must be asserted, and asserted as PASSes. The
# mirror alone is worthless: it passes whenever the check is inert, which is exactly how
# this stayed hidden.
grep -q 'PASS  an unreachable commit SHA is denied' <<<"$mem_out" \
  || fail "the unreachable-SHA deny was not asserted in a worktree — the check that BL-338 found silent there"
grep -q 'PASS  a reachable commit SHA is not denied' <<<"$mem_out" \
  || fail "the reachable-SHA mirror was not asserted in a worktree — a mirror that cannot run must report itself, never pass quietly"

if [ "$failures" -eq 0 ]; then
  echo "PASS: both structurally-worktree-hostile tests run and assert from a linked worktree."
else
  printf '%d assertion(s) failed\n' "$failures"
fi
exit $((failures > 0))
