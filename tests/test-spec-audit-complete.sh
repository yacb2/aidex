#!/usr/bin/env bash
# Completeness gate for the EchoLab editor-spec layer audit (Phase 11, `s3`).
#
# Derives the non-`playback` spec list from EchoLab's timeline E2E directory at
# run time — never hard-coded — and asserts the audit table
# (references/04-e2e-layer-audit.md) has a row for every one of them. Written
# before the table (Task 11.2 precedes Task 11.1), so it starts red.
#
# A partial table must fail too, not only a missing one: a completeness check
# that only checks the file exists would be the "checkers lie by omission"
# failure this campaign keeps naming. Deleting one row must turn this red
# again.
#
# Skips with exit 2 — the runner's SKIP code — if EchoLab is not on disk,
# rather than passing vacuously against zero specs. NOT exit 0: run-all.sh counts
# exit 0 as a PASS, so a skip announced only in prose would report a test that
# never ran as one that passed.
#
# Lives at the repo root, NOT in skills/coverage/tests/, and that is the
# point: it names a real project (echo_lab_ws) and a real table in this
# workspace's private .context/, so it is repo data by the same rule
# 04-e2e-layer-audit.md states for the table itself. Shipped inside the skill it
# was copied to ~/.claude/skills/, where $REPO_ROOT resolved to ~/.claude and it
# FAILed on a .context/ that has no reason to exist there. Only skills/, rules/
# and hooks/ are installed, so this directory is repo-only by construction.
#
# Run with: bash tests/test-spec-audit-complete.sh

set -uo pipefail

# The completed table is project data, relocated out of the public skill
# (BL-211): it lives in this workspace's private .context/, and the skill keeps
# only the template. The gate has now followed the table out of the skill too.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# ...and `.context/` is gitignored, so a LINKED WORKTREE never has one. Resolving
# the table under whichever checkout this file happens to sit in made the
# assertion unsatisfiable there, and a sweep — which is mandated to run in a
# worktree — could never cite a green suite (BL-338). The table is workspace
# data with exactly one copy, so a worktree grades the main checkout's copy
# instead of pretending it has its own.
CANON_ROOT="$REPO_ROOT"
IN_WORKTREE=""
_gitdir="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
_common="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$_common" ] && [ "$_common" != "$_gitdir" ]; then
  IN_WORKTREE="$REPO_ROOT"
  CANON_ROOT="$(dirname "$_common")"
fi
AUDIT="$CANON_ROOT/.context/references/coverage/01-echolab-e2e-layer-audit.md"

ECHOLAB="${ECHOLAB_PATH:-$HOME/Documents/projects/echo_lab_ws}"
TIMELINE_DIR="$ECHOLAB/frontend/tests/e2e/timeline"

# Exit 2, not 0: the runner counts exit 0 as a PASS, so a skip announced only in
# prose would report a test that never ran as one that passed — the "checkers lie
# by omission" shape this repo keeps meeting.
if [ ! -d "$TIMELINE_DIR" ]; then
  echo "SKIP: EchoLab not on disk at $TIMELINE_DIR"
  exit 2
fi

fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

if [ ! -f "$AUDIT" ]; then
  # A worktree whose main checkout has no table has nothing to grade — say so and
  # name the worktree, rather than failing for a file that was never going to be
  # in reach from here.
  if [ -n "$IN_WORKTREE" ]; then
    echo "SKIP: running from the worktree $IN_WORKTREE and its main checkout ($CANON_ROOT) has no $AUDIT"
    exit 2
  fi
  # EchoLab IS on disk here, so on this workspace a missing table is a real
  # failure; on a machine with EchoLab but no aidex .context/ it cannot be —
  # there is nothing to ratchet. Absence of the private table with the private
  # project present is the one combination that must stay loud.
  err "audit table not found: $AUDIT (EchoLab is on disk — the relocated table should exist here)"
  exit 1
fi

# Derived from disk, never transcribed.
specs=()
while IFS= read -r -d '' f; do
  specs+=("$(basename "$f")")
done < <(find "$TIMELINE_DIR" -maxdepth 1 -name '*.spec.ts' ! -name 'playback-*' -print0)

if [ "${#specs[@]}" -eq 0 ]; then
  err "found zero non-playback specs in $TIMELINE_DIR — that itself is suspicious, not a pass"
  exit 1
fi

echo "Derived ${#specs[@]} non-playback specs from disk."

for spec in "${specs[@]}"; do
  if ! grep -qF "$spec" "$AUDIT"; then
    err "no audit row for $spec"
  fi
done

# Reverse direction: every `*.spec.ts` name the table cites must exist on disk.
# Catches a stale row left behind by a rename — a spec's row surviving under
# its old name is exactly the "checker lies by omission" failure this gate
# exists to prevent.
while IFS= read -r cited; do
  [ -f "$TIMELINE_DIR/$cited" ] || err "audit row names a file that does not exist: $cited"
done < <(grep -oE '`[A-Za-z0-9_.-]+\.spec\.ts`' "$AUDIT" | tr -d '`' | sort -u)

if [ "$fail" -eq 0 ]; then
  echo "PASS: every one of ${#specs[@]} non-playback specs has an audit row, and every cited file exists."
else
  echo "The audit table and disk disagree — see FAILs above." >&2
fi

exit "$fail"
