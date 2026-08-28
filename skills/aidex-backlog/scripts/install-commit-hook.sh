#!/usr/bin/env bash
# install-commit-hook.sh — wire a REPO-LOCAL post-commit hook that harvests commit
# SHAs into tracking artifacts via harvest-commit.sh (D-09). Never touches global
# git config. Run once inside a project that uses aidex tracking.
#
# Usage:
#   install-commit-hook.sh [--remove]
#
# Idempotent. If a non-aidex post-commit hook already exists, it is left untouched
# and the line to add manually is printed.

set -euo pipefail

MARK="# >>> aidex commit-trailer harvester (D-09) >>>"
END_MARK="# <<< aidex commit-trailer harvester <<<"
HARVEST='"$HOME/.claude/skills/aidex-backlog/scripts/harvest-commit.sh" >/dev/null 2>&1 || true'

REMOVE=0
[[ "${1:-}" == "--remove" ]] && REMOVE=1

GIT_DIR="$(git rev-parse --git-dir 2>/dev/null || true)"
[[ -n "$GIT_DIR" ]] || { echo "error: not inside a git repository" >&2; exit 2; }
HOOK="$GIT_DIR/hooks/post-commit"

if [[ $REMOVE -eq 1 ]]; then
  [[ -f "$HOOK" ]] || { echo "no post-commit hook to clean"; exit 0; }
  if grep -qF "$MARK" "$HOOK"; then
    awk -v a="$MARK" -v b="$END_MARK" '
      $0==a {skip=1; next} $0==b {skip=0; next} !skip {print}
    ' "$HOOK" > "$HOOK.tmp" && mv "$HOOK.tmp" "$HOOK"
    chmod +x "$HOOK"
    echo "removed aidex block from $HOOK"
  else
    echo "post-commit hook is not aidex-managed — left untouched"
  fi
  exit 0
fi

block() {
  printf '%s\n' "$MARK"
  printf '%s\n' "$HARVEST"
  printf '%s\n' "$END_MARK"
}

if [[ ! -f "$HOOK" ]]; then
  { printf '#!/usr/bin/env bash\n'; block; } > "$HOOK"
  chmod +x "$HOOK"
  echo "installed post-commit hook at $HOOK"
elif grep -qF "$MARK" "$HOOK"; then
  echo "aidex hook already present in $HOOK — nothing to do"
else
  echo "WARN: $HOOK exists and is not aidex-managed." >&2
  echo "Add this line to it manually to enable commit harvesting:" >&2
  echo "  $HARVEST" >&2
  exit 1
fi

echo
echo "Note: the hook updates .context/ artifacts AFTER the commit, so the SHA"
echo "lands as an unstaged change in the next working tree (commit it with the"
echo "next change, or amend). Use commit trailers: 'Backlog: BL-007' / 'Plan: <slug>#<phase>'."
