#!/usr/bin/env bash
# test-worklist-lifecycle-no-live-writes.sh — test_worklist_lifecycle.sh must never
# write into the project it is run from.
#
# The bug (field-observed 2026-09-29): a suite run left
# `aidex/.context/worklists/_archive/<date>-lifecycle-test-<pid>.md` in the PUBLIC
# repo, which must never carry a `.context/`. The lifecycle test created its fixture
# wherever find_project_root() pointed for the cwd — the main worktree from a linked
# worktree, the workspace from the main tree — and cleaned up by re-deriving the
# archive path from a root it computed once at start. Two suites running at once
# (one in a worktree, one in the main tree) flip that root mid-run for the other,
# so the scripts archived into one project while cleanup deleted from another.
#
# The race is not replayed here; the contract that removes it is: the live project
# is made read-only, so any write into it fails the lifecycle run. Both roots the
# field incident involved are covered — the linked-worktree hop and the workspace.
#
# Layer: shell integration, the lifecycle test run as a black box — only a run from
# a real cwd can show where its fixture lands.
#
# Run with: bash skills/conventions/scripts/test-worklist-lifecycle-no-live-writes.sh
set -uo pipefail

LIFECYCLE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/test_worklist_lifecycle.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(cd "$(mktemp -d)" && pwd -P)"
WS="$TMP/ws"; REPO="$WS/repo"; WT="$TMP/wt"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

# workspace with its own .context/, a nested repo without one, a linked worktree
mkdir -p "$WS/.context" "$REPO"
git -C "$REPO" init -q
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q "$WT" 2>/dev/null

# case 1: from the linked worktree the scripts resolve to the main tree ($REPO)
chmod a-w "$REPO"
out="$(cd "$WT" && bash "$LIFECYCLE" 2>&1)"; rc=$?
chmod u+w "$REPO"
[[ $rc -eq 0 ]] || fail "lifecycle run from a linked worktree wrote into the main tree (exit $rc): $(grep -m1 -E 'denied|FAIL' <<<"$out")"
[[ ! -e "$REPO/.context" ]] || fail "lifecycle run left $REPO/.context behind"

# case 2: from the main tree the scripts resolve to the workspace ($WS)
chmod a-w "$WS/.context"
out="$(cd "$REPO" && bash "$LIFECYCLE" 2>&1)"; rc=$?
chmod u+w "$WS/.context"
[[ $rc -eq 0 ]] || fail "lifecycle run from the main tree wrote into the workspace .context (exit $rc): $(grep -m1 -E 'denied|FAIL' <<<"$out")"
[[ -z "$(ls -A "$WS/.context")" ]] || fail "lifecycle run left files in $WS/.context: $(ls -A "$WS/.context")"

if [[ $failures -eq 0 ]]; then echo "PASS: lifecycle test writes nothing into the project it runs from"; else exit 1; fi
