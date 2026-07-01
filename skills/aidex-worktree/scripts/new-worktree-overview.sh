#!/usr/bin/env bash
# new-worktree-overview.sh — scaffold .context/worktrees/00-index.md.
# Usage: new-worktree-overview.sh
#
# One file per project (not one per topic) — refuses to overwrite an existing doc.
# Self-contained: inlines its helpers so it does not depend on a sibling _lib.sh.
# On success, prints the created file path to stdout.

set -euo pipefail

# Resolve the skill dir even via symlink.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
TEMPLATES_DIR="$SKILL_DIR/assets/templates"

ROOT="$(find_project_root)"
WORKTREES_DIR="$ROOT/.context/worktrees"
OUT="$WORKTREES_DIR/00-index.md"
DATE_ISO="$(today_iso)"

[[ -e "$OUT" ]] && die "refusing to overwrite existing file: $OUT (edit it directly, or delete it first if you want to re-bootstrap)"

mkdir -p "$WORKTREES_DIR"

render_template "$TEMPLATES_DIR/worktree-overview.md.template" "$OUT" \
  DATE="$DATE_ISO"

ok "Worktree overview scaffolded: $OUT"
cat >&2 <<EOF

Next steps:
  1. Fill every section from the topology detection + interview answers.
  2. See: $SKILL_DIR/references/02-worktree-overview-conventions.md
EOF

# Machine-readable path on stdout.
printf '%s\n' "$OUT"
