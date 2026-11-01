#!/usr/bin/env bash
# install-commit-hook.sh — wire a REPO-LOCAL post-commit hook that harvests commit
# SHAs into tracking artifacts via harvest-commit.sh (D-09). Never touches global
# git config. Run once inside a project that uses aidex tracking.
#
# Usage:
#   install-commit-hook.sh [--remove]
#
# Idempotent; re-running refreshes an aidex block written by an older version. If a
# non-aidex post-commit hook already exists, it is left untouched and the line to add
# manually is printed.

set -euo pipefail

MARK="# >>> aidex commit-trailer harvester (D-09) >>>"
END_MARK="# <<< aidex commit-trailer harvester <<<"
# The hook we write runs as a git post-commit in the user's repo, outside any plugin
# context, so it must carry the ABSOLUTE path resolved from this script's own location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# The hook runs outside any plugin context, so it bakes the install-time path and,
# when that path is gone (a plugin update moves the cache dir per version), falls
# back to the newest cached copy of the plugin, in either profile's config dir
# (~/.claude, ~/.claude-work): a git hook fired from a plain terminal has no
# CLAUDE_CONFIG_DIR to say which one. `.claude*` matches any ~/.claude-prefixed
# directory, so a harvest-commit.sh under such a sibling path is a candidate too.
HARVEST="h=\"$SCRIPT_DIR/harvest-commit.sh\"; [ -x \"\$h\" ] || h=\$(ls -t \"\$HOME\"/.claude*/plugins/cache/*/aidex/*/skills/backlog/scripts/harvest-commit.sh 2>/dev/null | sed -n 1p); [ -n \"\$h\" ] && \"\$h\" >/dev/null 2>&1 || true"

REMOVE=0
[[ "${1:-}" == "--remove" ]] && REMOVE=1

# --git-path hooks is where git reads hooks from: core.hooksPath when set, the common
# directory (not the per-worktree one) from a linked worktree.
HOOKS_DIR="$(git rev-parse --git-path hooks 2>/dev/null || true)"
[[ -n "$HOOKS_DIR" ]] || { echo "error: not inside a git repository" >&2; exit 2; }
HOOK="$HOOKS_DIR/post-commit"

# True when the hook holds a whole aidex block: the start marker as an exact line, then
# the end marker. A block without its end would make the rewrite below drop every line
# after the start, and .git/hooks is not versioned; a CRLF hook matches neither line.
has_block() {
  awk -v a="$MARK" -v b="$END_MARK" '$0==a {m=1} m && $0==b {f=1} END {exit !f}' "$HOOK"
}
# Write through the path, so a symlinked hook stays a symlink and its target changes.
replace_hook() { cat "$HOOK.tmp" > "$HOOK"; rm -f "$HOOK.tmp"; }

if [[ $REMOVE -eq 1 ]]; then
  [[ -f "$HOOK" ]] || { echo "no post-commit hook to clean"; exit 0; }
  if has_block; then
    awk -v a="$MARK" -v b="$END_MARK" '
      $0==a {skip=1; next} $0==b {skip=0; next} !skip {print}
    ' "$HOOK" > "$HOOK.tmp" && replace_hook
    chmod +x "$HOOK"
    echo "removed aidex block from $HOOK"
  elif grep -qF "$MARK" "$HOOK"; then
    echo "WARN: the aidex block in $HOOK is incomplete (no end marker line, or CRLF line endings) — left untouched; edit it by hand" >&2
    exit 1
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
  mkdir -p "$HOOKS_DIR"
  { printf '#!/usr/bin/env bash\n'; block; } > "$HOOK"
  chmod +x "$HOOK"
  echo "installed post-commit hook at $HOOK"
elif has_block; then
  # Replace the block in place, so a hook written by an older version picks up the
  # current HARVEST line; the hook's other lines are kept. ENVIRON, not -v: awk -v would
  # unescape the backslashes in HARVEST.
  HARVEST="$HARVEST" awk -v a="$MARK" -v b="$END_MARK" '
    $0==a {print; print ENVIRON["HARVEST"]; skip=1; next} $0==b {skip=0} !skip {print}
  ' "$HOOK" > "$HOOK.tmp"
  if cmp -s "$HOOK" "$HOOK.tmp"; then
    rm -f "$HOOK.tmp"
    echo "aidex hook already present in $HOOK — nothing to do"
  else
    replace_hook; chmod +x "$HOOK"
    echo "updated the aidex block in $HOOK"
  fi
else
  if grep -qF "$MARK" "$HOOK"; then
    echo "WARN: the aidex block in $HOOK is incomplete (no end marker line, or CRLF line endings) — left untouched." >&2
  else
    echo "WARN: $HOOK exists and is not aidex-managed." >&2
  fi
  echo "Add this line to it manually to enable commit harvesting:" >&2
  echo "  $HARVEST" >&2
  exit 1
fi

echo
echo "Note: the hook updates .context/ artifacts AFTER the commit, so the SHA"
echo "lands as an unstaged change in the next working tree (commit it with the"
echo "next change, or amend). Use commit trailers: 'Backlog: BL-007' / 'Plan: <slug>#<phase>'."
