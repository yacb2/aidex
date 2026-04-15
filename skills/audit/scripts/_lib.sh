#!/usr/bin/env bash
# Shared helpers for audit scripts.
# Source: . "$(dirname "$0")/_lib.sh"

set -euo pipefail

# Resolve the skill directory even when invoked via symlink.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TEMPLATES_DIR="$SKILL_DIR/assets/templates"

# Colors for humans (no-op if NO_COLOR set or not a TTY).
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_DIM='' C_BOLD='' C_RESET=''
fi

log()   { printf '%s\n' "$*" >&2; }
info()  { printf '%s%s%s\n' "$C_BLUE"   "$*" "$C_RESET" >&2; }
ok()    { printf '%s%s%s\n' "$C_GREEN"  "$*" "$C_RESET" >&2; }
warn()  { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
err()   { printf '%s%s%s\n' "$C_RED"    "$*" "$C_RESET" >&2; }
die()   { err "error: $*"; exit 2; }

# Project root — walk up until we find .context/ or hit /
find_project_root() {
  local dir
  dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.context" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # Fallback: current directory (will create .context if needed)
  pwd -P
}

today() { date +%Y%m%d; }
today_iso() { date +%Y-%m-%d; }

# Render a template: substitute {{KEY}} placeholders with provided values.
# Usage: render_template <template-path> <output-path> KEY1=val1 KEY2=val2 ...
render_template() {
  local template="$1"; shift
  local out="$1"; shift
  [[ -f "$template" ]] || die "template not found: $template"
  [[ -e "$out" ]] && die "refusing to overwrite existing file: $out"

  local content
  content="$(cat "$template")"

  local kv key val
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    # Escape for sed: use | as delimiter; escape | & \ in val
    val="${val//\\/\\\\}"
    val="${val//|/\\|}"
    val="${val//&/\\&}"
    content="$(printf '%s' "$content" | sed "s|{{$key}}|$val|g")"
  done

  printf '%s' "$content" > "$out"
}

# Known audit types (canonical names)
AUDIT_TYPES=(ux-audit ia-opportunities retest security-audit perf-audit a11y-audit custom)

# Normalize short aliases to canonical type names.
# Prints the canonical type, or the input unchanged if already canonical.
# Returns non-zero if the type is unknown.
normalize_type() {
  local t="$1"
  case "$t" in
    ux|ux-audit)                   printf '%s\n' "ux-audit"; return 0 ;;
    ia|ai|ia-opportunities|ai-opportunities) printf '%s\n' "ia-opportunities"; return 0 ;;
    retest|re-test)                printf '%s\n' "retest"; return 0 ;;
    sec|security|security-audit)   printf '%s\n' "security-audit"; return 0 ;;
    perf|performance|perf-audit)   printf '%s\n' "perf-audit"; return 0 ;;
    a11y|accessibility|a11y-audit) printf '%s\n' "a11y-audit"; return 0 ;;
    custom)                        printf '%s\n' "custom"; return 0 ;;
    *) return 1 ;;
  esac
}

is_known_type() {
  normalize_type "$1" > /dev/null 2>&1
}

# kebab-case validator
is_valid_slug() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
}
