#!/usr/bin/env bash
# defer-item.sh — move a backlog item to/from backlog/_deferred/ (open-but-blocked).
# Deferred items keep `status: open` but have `blocked_by` populated; they are not
# in the active queue and NOT in _archive/ (archive is terminal: done/dropped).
#
# Usage:
#   defer-item.sh defer <BL-id | slug | filename | path> --reason "<blocker>"
#   defer-item.sh reactivate <BL-id | slug | filename | path>
#
# Options:
#   --reason "<text>"   (defer) the external blocker; sets/appends `blocked_by`. Required.
#   --no-index          skip index regeneration
#
# defer:      active root → _deferred/  · sets blocked_by · stamps updated
# reactivate: _deferred/  → active root · stamps updated (blocked_by left as-is for trail)

set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_RESET=$'\033[0m'
else C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''; fi
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET" >&2; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
die()  { printf '%serror: %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 2; }

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# aidex-conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

# --- dispatcher: strip leading "aidex-backlog" if present ---
[[ "${1:-}" == "aidex-backlog" ]] && shift

ACTION="${1:-}"; shift || true
case "$ACTION" in
  defer|reactivate) ;;
  -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
  *) die "first argument must be: defer | reactivate" ;;
esac

TARGET="" REASON="" NO_INDEX=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason)   REASON="$2"; shift 2 ;;
    --no-index) NO_INDEX=1; shift ;;
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)         die "unknown option: $1" ;;
    *)          TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || die "target required: <BL-id | slug | filename | path>"

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
DEFERRED_DIR="$BACKLOG_DIR/_deferred"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read_id() { awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$1"; }

# --- resolve target to a file within the expected source directory ---
resolve_in() {
  local srcdir="$1" file=""
  if [[ "$TARGET" =~ ^[Bb][Ll]-[0-9]+$ ]]; then
    local target_uc; target_uc="$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')"
    for f in "$srcdir"/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(read_id "$f")" == "$target_uc" ]] && { file="$f"; break; }
    done
  elif [[ -f "$TARGET" ]]; then
    file="$TARGET"
  elif [[ -f "$srcdir/$TARGET" ]]; then
    file="$srcdir/$TARGET"
  elif [[ -f "$srcdir/$TARGET.md" ]]; then
    file="$srcdir/$TARGET.md"
  else
    # slug match: any active/deferred file whose name ends in -<slug>.md
    for f in "$srcdir"/*"$TARGET".md "$srcdir"/*"$TARGET"*.md; do
      [[ -f "$f" ]] && { file="$f"; break; }
    done
  fi
  printf '%s\n' "$file"
}

TODAY="$(date +%Y-%m-%d)"

if [[ "$ACTION" == "defer" ]]; then
  [[ -n "$REASON" ]] || die "--reason \"<blocker>\" is required when deferring"
  FILE="$(resolve_in "$BACKLOG_DIR")"
  [[ -n "$FILE" && -f "$FILE" ]] || die "cannot resolve active backlog item: $TARGET"
  [[ "$(dirname "$FILE")" == "$BACKLOG_DIR" ]] || die "target is not an active backlog item: $FILE"

  # set/append blocked_by + stamp updated (status stays open)
  awk -v today="$TODAY" -v reason="$REASON" '
    BEGIN { d=0; infm=0; seen_blocked=0 }
    /^---[[:space:]]*$/ {
      d++
      if (d==1) { infm=1; print; next }
      if (d==2) { if (!seen_blocked) print "blocked_by: \"" reason "\""; infm=0; print; next }
    }
    infm==1 {
      if ($0 ~ /^updated:/) { print "updated: " today; next }
      if ($0 ~ /^blocked_by:/) {
        val=$0; sub(/^blocked_by:[[:space:]]*/,"",val); gsub(/"/,"",val)
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",val)
        if (val=="") print "blocked_by: \"" reason "\""
        else         print "blocked_by: \"" val "; " reason "\""
        seen_blocked=1; next
      }
      print; next
    }
    { print }
  ' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

  mkdir -p "$DEFERRED_DIR"
  DEST="$DEFERRED_DIR/$(basename "$FILE")"
  [[ -e "$DEST" ]] && die "_deferred collision: $DEST already exists"
  mv "$FILE" "$DEST"
  ok "Deferred $(basename "$FILE") → _deferred/ · blocked_by: \"$REASON\""

elif [[ "$ACTION" == "reactivate" ]]; then
  [[ -d "$DEFERRED_DIR" ]] || die "no _deferred/ directory at $DEFERRED_DIR"
  FILE="$(resolve_in "$DEFERRED_DIR")"
  [[ -n "$FILE" && -f "$FILE" ]] || die "cannot resolve deferred item: $TARGET"
  [[ "$(dirname "$FILE")" == "$DEFERRED_DIR" ]] || die "target is not a deferred item: $FILE"

  # clear blocked_by + stamp updated (status already open)
  awk -v today="$TODAY" '
    BEGIN { d=0; infm=0 }
    /^---[[:space:]]*$/ { d++; if (d<=1) { infm=1 } else { infm=0 }; print; next }
    infm==1 {
      if ($0 ~ /^updated:/)    { print "updated: " today; next }
      if ($0 ~ /^blocked_by:/) { print "blocked_by: \"\""; next }
      print; next
    }
    { print }
  ' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

  DEST="$BACKLOG_DIR/$(basename "$FILE")"
  [[ -e "$DEST" ]] && die "active collision: $DEST already exists"
  mv "$FILE" "$DEST"
  ok "Reactivated $(basename "$FILE") → active queue"
fi

# --- rebuild index ---
if [[ $NO_INDEX -eq 0 ]]; then
  bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null
  ok "  index rebuilt"
fi

printf '%s\n' "$DEST"
