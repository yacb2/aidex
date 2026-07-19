#!/usr/bin/env bash
# check-overview.sh — mechanical doc-shape check for a worktree overview
# (.context/worktrees/00-index.md). Verifies the machine-consumed surface is
# intact so a broken doc is caught and amended in-session rather than passively
# recommended:
#   - front-matter has the worktree_up / worktree_down fields
#   - the ## Procedure and ## Usage log sections are present
#   - every backlog/... path the doc references resolves (active / _archive /
#     _deferred)
# Non-zero exit lists the gaps (one per line, on stderr).
#
# Usage:
#   check-overview.sh [doc-path]
#
#   doc-path default: <project-root>/.context/worktrees/00-index.md
#
# Self-contained beyond _lib.sh (find_project_root / logging helpers).

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

DOC="${1:-$(find_project_root)/.context/worktrees/00-index.md}"
[[ -f "$DOC" ]] || die "worktree overview not found: $DOC"

# .context/ is the doc's grandparent (.context/worktrees/00-index.md).
DOC_DIR="$(cd "$(dirname "$DOC")" && pwd -P)"
BACKLOG_DIR="$(dirname "$DOC_DIR")/backlog"

gaps=()

# --- front-matter fields (first --- ... --- block) ---
fm="$(sed -n '/^---$/,/^---$/p' "$DOC")"
grep -qE '^worktree_up:'   <<<"$fm" || gaps+=("front-matter: missing 'worktree_up' field")
grep -qE '^worktree_down:' <<<"$fm" || gaps+=("front-matter: missing 'worktree_down' field")

# --- required sections ---
grep -qE '^## +Procedure *$' "$DOC" || gaps+=("section: missing '## Procedure'")
grep -qE '^## +Usage log *$' "$DOC" || gaps+=("section: missing '## Usage log'")

# --- backlog references resolve (active / _archive / _deferred) ---
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  tail="${ref#backlog/}"
  base="$(basename "$ref")"
  if [[ -e "$BACKLOG_DIR/$tail" || -e "$BACKLOG_DIR/_archive/$base" || -e "$BACKLOG_DIR/_deferred/$base" ]]; then
    continue
  fi
  gaps+=("backlog ref does not resolve: $ref")
done < <(grep -oE 'backlog/[A-Za-z0-9._/-]+\.md' "$DOC" | sort -u)

if [[ ${#gaps[@]} -gt 0 ]]; then
  err "doc-shape check FAILED (${#gaps[@]} gap(s)): $DOC"
  for g in "${gaps[@]}"; do printf '  - %s\n' "$g" >&2; done
  exit 1
fi

ok "doc-shape OK: $DOC"
