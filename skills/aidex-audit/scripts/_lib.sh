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

# Make a kebab-case slug from arbitrary text: lowercase, non-alnum -> hyphen,
# collapse repeats, trim leading/trailing hyphens. Empty input -> empty output.
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Resolve the inventory file: canonical 00-inventory.md, else legacy INVENTORY.md.
# Prints the path, or dies if neither exists.
# Usage: resolve_inventory <audits_dir>
resolve_inventory() {
  local audits_dir="$1"
  if [[ -f "$audits_dir/00-inventory.md" ]]; then
    printf '%s\n' "$audits_dir/00-inventory.md"
  elif [[ -f "$audits_dir/INVENTORY.md" ]]; then
    printf '%s\n' "$audits_dir/INVENTORY.md"
  else
    die "inventory not found: expected $audits_dir/00-inventory.md (or legacy INVENTORY.md)"
  fi
}

# Find which audit run folder recorded a finding. Prints the run folder basename;
# falls back to the most recent run folder, or "unknown-run".
# Usage: find_audit_run <audits_dir> <finding_id>
find_audit_run() {
  local audits_dir="$1" finding_id="$2" audit_run="" f
  if compgen -G "$audits_dir/[0-9]*-*/findings.md" > /dev/null; then
    while IFS= read -r f; do
      if grep -q "$finding_id" "$f"; then
        audit_run="$(basename "$(dirname "$f")")"
        break
      fi
    done < <(find "$audits_dir" -type f -name findings.md -path '*/[0-9]*-*/findings.md' | sort)
  fi
  if [[ -z "$audit_run" ]]; then
    audit_run="$(ls -1d "$audits_dir"/[0-9]*-*/ 2>/dev/null | sort | tail -1 | xargs -I{} basename {})"
  fi
  [[ -z "$audit_run" ]] && audit_run="unknown-run"
  printf '%s\n' "$audit_run"
}

# Extract "<summary>\t<severity>" for a finding row from the inventory.
# Prints empty if not found. Skips HTML comment blocks so template example rows
# never pollute the match. Summary is cell 5, status cell 6, severity cell 7.
# Usage: extract_finding_row <inventory> <finding_id>
extract_finding_row() {
  local inventory="$1" finding_id="$2"
  awk -v id="$finding_id" '
    BEGIN { in_comment = 0 }
    {
      line = $0
      # Handle HTML comments (single-line and multi-line)
      while (1) {
        if (in_comment) {
          end = index(line, "-->")
          if (end == 0) { line = ""; break }
          line = substr(line, end + 3)
          in_comment = 0
        } else {
          start = index(line, "<!--")
          if (start == 0) break
          before = substr(line, 1, start - 1)
          after = substr(line, start + 4)
          end = index(after, "-->")
          if (end == 0) { line = before; in_comment = 1; break }
          line = before substr(after, end + 3)
        }
      }
      # Parse as pipe-delimited row
      if (line !~ /^\|/) next
      n = split(line, cells, "|")
      if (n < 11) next
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[2])
      if (cells[2] == id) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[5])
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[6])
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cells[7])
        # Must also have a real-looking status to avoid matching reference tables
        if (cells[6] ~ /open|triaged|escalated|in-progress|closed|dropped/) {
          print cells[5] "\t" cells[7]
          exit
        }
      }
    }
  ' "$inventory"
}

# Rewrite a finding's inventory row in place: status -> escalated, append today
# to the runs column, set the "Escalated To" cell to <link> (a pre-built markdown
# link). Skips HTML comment blocks so template EXAMPLE rows are never rewritten.
# Usage: mark_row_escalated <inventory> <finding_id> <link>
mark_row_escalated() {
  local inventory="$1" finding_id="$2" link="$3" tmp
  tmp="$(mktemp)"
  awk -v id="$finding_id" -v link="$link" -v today="$(today)" '
    BEGIN { in_comment = 0 }
    {
      # Track whether the CURRENT line is inside a multi-line HTML comment.
      line = $0
      skip_parse = in_comment
      tmp = line
      while (1) {
        if (in_comment) {
          end = index(tmp, "-->")
          if (end == 0) { tmp = ""; break }
          tmp = substr(tmp, end + 3)
          in_comment = 0
        } else {
          start = index(tmp, "<!--")
          if (start == 0) break
          after = substr(tmp, start + 4)
          end = index(after, "-->")
          if (end == 0) { in_comment = 1; break }
          tmp = substr(after, end + 3)
        }
      }

      # If the line started inside a comment or contained comment markers, pass through unchanged.
      if (skip_parse || index($0, "<!--") > 0 || index($0, "-->") > 0) {
        print $0
        next
      }

      # Parse as pipe-delimited
      if ($0 !~ /^\|/) { print $0; next }
      n = split($0, cells, "|")
      if (n < 11) { print $0; next }

      t = cells[2]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
      if (t != id) { print $0; next }

      # Verify this is a real finding row (status column has a known marker)
      s = cells[6]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (s !~ /open|triaged|escalated|in-progress|closed|dropped/) {
        print $0; next
      }

      # Update fields
      cells[6]  = " escalated "
      cells[9]  = " " today " "
      runs = cells[10]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", runs)
      if (index(runs, today) == 0) {
        if (runs == "" || runs == "—") runs = today
        else runs = runs ", " today
      }
      cells[10] = " " runs " "
      cells[11] = " " link " "

      # Reassemble
      out = cells[1]
      for (i = 2; i <= n; i++) out = out "|" cells[i]
      print out
    }
  ' "$inventory" > "$tmp"
  mv "$tmp" "$inventory"
}

# Compute the relative path from a base file's directory to a target file.
# Usage: relpath_from <target> <base-file>
relpath_from() {
  python3 -c "import os,sys; print(os.path.relpath(sys.argv[1], start=os.path.dirname(sys.argv[2])))" "$1" "$2" 2>/dev/null || printf '%s\n' "$1"
}
