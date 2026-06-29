#!/usr/bin/env bash
# new-workflow-spec.sh — scaffold a workflow-spec in .context/workflows/.
# Usage: new-workflow-spec.sh new <slug>
#   <slug>: kebab-case identifier, e.g. "review-auth-across-dimensions"
#
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

is_valid_slug() { [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; }

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

# Next sequential id WF-NNN across active + _archive (ids stay stable).
next_workflow_id() {
  local dir="$1" max=0 n f
  shopt -s nullglob
  for f in "$dir"/*.md "$dir"/_archive/*.md; do
    [[ -f "$f" ]] || continue
    n="$(awk '/^---[[:space:]]*$/{c++; if(c==2) exit} c==1 && $1 ~ /^id:/ {v=$2; gsub(/[^0-9]/,"",v); print v; exit}' "$f")"
    [[ -n "$n" ]] && (( 10#$n > max )) && max=$((10#$n))
  done
  shopt -u nullglob
  printf 'WF-%03d' $((max+1))
}

# Strip leading "new" dispatched by the skill.
if [[ "${1:-}" == "new" ]]; then shift; fi

SLUG="${1:-}"
if [[ -z "$SLUG" ]]; then
  cat <<EOF >&2
Usage: /aidex-workflow new <slug>

Example:
  /aidex-workflow new review-auth-across-dimensions
EOF
  exit 2
fi
is_valid_slug "$SLUG" || die "invalid slug: $SLUG (use kebab-case: lowercase letters, digits, hyphens)"

ROOT="$(find_project_root)"
WORKFLOWS_DIR="$ROOT/.context/workflows"
DATE_ISO="$(today_iso)"
mkdir -p "$WORKFLOWS_DIR"

ID="$(next_workflow_id "$WORKFLOWS_DIR")"
OUT="$WORKFLOWS_DIR/$DATE_ISO-$SLUG.md"

render_template "$TEMPLATES_DIR/workflow-spec.md.template" "$OUT" \
  ID="$ID" SLUG="$SLUG" DATE="$DATE_ISO"

ok "Workflow-spec scaffolded: $OUT"
cat >&2 <<EOF

Next steps:
  1. Fill the spec: Goal, Shape, Work-list, Per-agent model+effort, Gate policy.
  2. See the shape catalog: $SKILL_DIR/references/01-workflow-spec-conventions.md
  3. When ready: /aidex-workflow run $SLUG
EOF

# Machine-readable path on stdout.
printf '%s\n' "$OUT"
