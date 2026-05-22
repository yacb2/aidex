#!/usr/bin/env bash
# close-item.sh — atomically close a backlog item (D-10): set status, record
# resolving commit(s), stamp `updated`, move to _archive/, rebuild the index.
# Never edit `status` by hand — this is the one supported close path.
#
# Usage:
#   close-item.sh <BL-id | filename | path> [options]
#
# Options:
#   --status <done|dropped>     default: done
#   --commit <sha>              resolving commit (repeatable). Use when the item
#                               was fixed directly, with no plan (D-09 provenance).
#   --superseded-by <type/ref>  mark superseded (status stays; index shows "superseded →")
#   --escalated-to <type/ref>   mark handed off (e.g. plan/<slug>)
#   --reason "<text>"           appended under ## Notes
#   --no-index                  skip index regeneration
#
# Resolves <BL-id> against active backlog items' front-matter `id:` field.

set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_RESET=$'\033[0m'
else C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''; fi
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET" >&2; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
die()  { printf '%serror: %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 2; }

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  pwd -P
}

TARGET="" STATUS="done" SUPERSEDED="" ESCALATED="" REASON="" NO_INDEX=0
COMMITS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)        STATUS="$2"; shift 2 ;;
    --commit)        COMMITS+=("$2"); shift 2 ;;
    --superseded-by) SUPERSEDED="$2"; shift 2 ;;
    --escalated-to)  ESCALATED="$2"; shift 2 ;;
    --reason)        REASON="$2"; shift 2 ;;
    --no-index)      NO_INDEX=1; shift ;;
    -h|--help)       sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)              die "unknown option: $1" ;;
    *)               TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || die "target required: <BL-id | filename | path>"
case "$STATUS" in done|dropped) ;; *) die "invalid --status: $STATUS (done|dropped)";; esac

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- resolve target to an active backlog file ---
read_id() { awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$1"; }
FILE=""
if [[ "$TARGET" =~ ^[Bb][Ll]-[0-9]+$ ]]; then
  TARGET_UC="$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')"
  for f in "$BACKLOG_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(read_id "$f")" == "$TARGET_UC" ]] && { FILE="$f"; break; }
  done
  [[ -n "$FILE" ]] || die "no active backlog item with id $TARGET_UC (already closed?)"
elif [[ -f "$TARGET" ]]; then
  FILE="$TARGET"
elif [[ -f "$BACKLOG_DIR/$TARGET" ]]; then
  FILE="$BACKLOG_DIR/$TARGET"
else
  die "cannot resolve target: $TARGET"
fi

[[ "$(dirname "$FILE")" == "$BACKLOG_DIR" ]] || die "target is not an active backlog item: $FILE"

TODAY="$(date +%Y-%m-%d)"
COMMITS_STR="${COMMITS[*]:-}"

# --- mutate front-matter (status, updated, optional superseded_by/escalated_to/commits) ---
awk -v status="$STATUS" -v today="$TODAY" -v sup="$SUPERSEDED" -v esc="$ESCALATED" -v commits="$COMMITS_STR" '
  BEGIN { d=0; infm=0; seen_sup=0; seen_esc=0; seen_commits=0 }
  /^---[[:space:]]*$/ {
    d++
    if (d==1) { infm=1; print; next }
    if (d==2) {
      if (sup!="" && !seen_sup) print "superseded_by: " sup
      if (esc!="" && !seen_esc) print "escalated_to: " esc
      if (commits!="" && !seen_commits) print "commits: \"" commits "\""
      infm=0; print; next
    }
  }
  infm==1 {
    if ($0 ~ /^status:/)  { print "status: " status; next }
    if ($0 ~ /^updated:/) { print "updated: " today; next }
    if (sup!="" && $0 ~ /^superseded_by:/) { print "superseded_by: " sup; seen_sup=1; next }
    if (esc!="" && $0 ~ /^escalated_to:/)  { print "escalated_to: " esc; seen_esc=1; next }
    if (commits!="" && $0 ~ /^commits:/) {
      val=$0; sub(/^commits:[[:space:]]*/,"",val); gsub(/"/,"",val)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",val)
      if (val=="" || val=="[]") print "commits: \"" commits "\""
      else                      print "commits: \"" val " " commits "\""
      seen_commits=1; next
    }
    print; next
  }
  { print }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

# --- optional closing note ---
if [[ -n "$REASON" ]]; then
  printf -- '\n- Closed %s (%s): %s\n' "$TODAY" "$STATUS" "$REASON" >> "$FILE"
fi

# --- move to _archive/ ---
mkdir -p "$BACKLOG_DIR/_archive"
DEST="$BACKLOG_DIR/_archive/$(basename "$FILE")"
[[ -e "$DEST" ]] && die "archive collision: $DEST already exists"
mv "$FILE" "$DEST"
ok "Closed $(basename "$FILE") → $STATUS · archived"
[[ -n "$COMMITS_STR" ]] && ok "  commits: $COMMITS_STR"

# --- rebuild index ---
if [[ $NO_INDEX -eq 0 ]]; then
  bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null
  ok "  index rebuilt"
fi

printf '%s\n' "$DEST"
