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
TEMPLATES_DIR="$SKILL_DIR/assets/templates"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m' C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_RESET=''
fi
info() { printf '%s%s%s\n' "$C_BLUE" "$*" "$C_RESET" >&2; }
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET" >&2; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
err()  { printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
die()  { err "error: $*"; exit 2; }

today_iso() { date +%Y-%m-%d; }

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.context" ]]; then printf '%s\n' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  pwd -P
}

# Render {{KEY}} placeholders. Usage: render <tpl> <out> KEY=val ...
render_template() {
  local template="$1"; shift
  local out="$1"; shift
  [[ -f "$template" ]] || die "template not found: $template"
  [[ -e "$out" ]] && die "refusing to overwrite existing file: $out"
  local content; content="$(cat "$template")"
  local kv key val
  for kv in "$@"; do
    key="${kv%%=*}"; val="${kv#*=}"
    val="${val//\\/\\\\}"; val="${val//|/\\|}"; val="${val//&/\\&}"
    content="$(printf '%s' "$content" | sed "s|{{$key}}|$val|g")"
  done
  printf '%s' "$content" > "$out"
}

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
