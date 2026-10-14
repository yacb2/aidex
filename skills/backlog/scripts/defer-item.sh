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
# reactivate: _deferred/  → active root · clears blocked_by · stamps updated

set -euo pipefail

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_backlog-lib.sh"

# --- dispatcher: strip leading "backlog" if present ---
[[ "${1:-}" == "backlog" ]] && shift

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


# The reason is yaml_escape'd (_backlog-lib.sh) and passed to awk through ENVIRON, never `-v` (awk -v
# re-reads backslash escapes, so `C:\new` became a newline inside the front matter).

# Rewrite item $1 with awk (remaining args) through a private temp next to it that
# carries its mode (cp -p), renamed over it: a shared `$FILE.tmp` let one writer
# truncate the file another was about to move into place.
rewrite() {
  local file="$1" tmp=""; shift
  tmp="$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX")" && cp -p "$file" "$tmp" \
    && awk "$@" "$file" > "$tmp" && mv -f "$tmp" "$file" || { rm -f "$tmp"; die "could not rewrite $file"; }
}

TODAY="$(date +%Y-%m-%d)"

if [[ "$ACTION" == "defer" ]]; then
  [[ -n "$REASON" ]] || die "--reason \"<blocker>\" is required when deferring"
  FILE="$(resolve_backlog_target "$BACKLOG_DIR" "$TARGET" read_id fuzzy)"
  [[ -n "$FILE" && -f "$FILE" ]] || die "cannot resolve active backlog item: $TARGET"
  [[ "$(dirname "$FILE")" == "$BACKLOG_DIR" ]] || die "target is not an active backlog item: $FILE"
  DEST="$DEFERRED_DIR/$(basename "$FILE")"
  [[ -e "$DEST" ]] && die "_deferred collision: $DEST already exists"

  # set/append blocked_by + stamp updated; status → open (a `doing` item deferred
  # mid-sweep is not being worked any more — it kept `doing` on 2026-08-28)
  DI_REASON="$(yaml_escape "$REASON")" rewrite "$FILE" -v today="$TODAY" '
    BEGIN { d=0; infm=0; seen_blocked=0; reason=ENVIRON["DI_REASON"] }
    d==1 && /^status:[[:space:]]*"?doing"?[[:space:]]*$/ { print "status: open"; next }
    /^---[[:space:]]*$/ {
      d++
      if (d==1) { infm=1; print; next }
      if (d==2) { if (!seen_blocked) print "blocked_by: \"" reason "\""; infm=0; print; next }
    }
    infm==1 {
      if ($0 ~ /^updated:/) { print "updated: " today; next }
      if ($0 ~ /^blocked_by:/) {
        # a quoted value is already escaped: drop only its wrapping quotes
        val=$0; sub(/^blocked_by:[[:space:]]*/,"",val); sub(/[[:space:]]+$/,"",val)
        # (a raw inner quote left by an older writer is escaped, not carried)
        if (val ~ /^".*"$/) {
          val=substr(val, 2, length(val)-2); out=""
          for (i=1; i<=length(val); i++) {
            c=substr(val, i, 1)
            if (c=="\\" && i<length(val)) { out=out c substr(val, i+1, 1); i++ }
            else if (c=="\\" || c=="\"") out=out "\\" c
            else out=out c
          }
          val=out
        } else gsub(/"/,"",val)
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",val)
        if (val=="") print "blocked_by: \"" reason "\""
        else         print "blocked_by: \"" val "; " reason "\""
        seen_blocked=1; next
      }
      print; next
    }
    { print }
  '

  mkdir -p "$DEFERRED_DIR"
  mv "$FILE" "$DEST"
  ok "Deferred $(basename "$FILE") → _deferred/ · blocked_by: \"$REASON\""

elif [[ "$ACTION" == "reactivate" ]]; then
  [[ -d "$DEFERRED_DIR" ]] || die "no _deferred/ directory at $DEFERRED_DIR"
  FILE="$(resolve_backlog_target "$DEFERRED_DIR" "$TARGET" read_id fuzzy)"
  [[ -n "$FILE" && -f "$FILE" ]] || die "cannot resolve deferred item: $TARGET"
  [[ "$(dirname "$FILE")" == "$DEFERRED_DIR" ]] || die "target is not a deferred item: $FILE"
  DEST="$BACKLOG_DIR/$(basename "$FILE")"
  [[ -e "$DEST" ]] && die "active collision: $DEST already exists"

  # clear blocked_by + stamp updated (status already open)
  rewrite "$FILE" -v today="$TODAY" '
    BEGIN { d=0; infm=0 }
    /^---[[:space:]]*$/ { d++; if (d<=1) { infm=1 } else { infm=0 }; print; next }
    infm==1 {
      if ($0 ~ /^updated:/)    { print "updated: " today; next }
      if ($0 ~ /^blocked_by:/) { print "blocked_by: \"\""; next }
      print; next
    }
    { print }
  '

  mv "$FILE" "$DEST"
  ok "Reactivated $(basename "$FILE") → active queue"
fi

# --- rebuild index ---
if [[ $NO_INDEX -eq 0 ]]; then
  # --reindex exits 4 AFTER writing the index (id guard); any other non-zero exit is a stale index
  IDX_RC=0
  bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null || IDX_RC=$?
  if [[ $IDX_RC -eq 0 ]]; then
    ok "  index rebuilt"
  elif [[ $IDX_RC -eq 4 ]]; then
    warn "  index rebuilt, but reindex reported an id problem (exit $IDX_RC)"; IDX_RC=0
  else
    warn "  index is stale (reindex exit $IDX_RC); rebuild it with: bash $SCRIPT_DIR/register-item.sh --reindex"
  fi
fi

printf '%s\n' "$DEST"
exit "${IDX_RC:-0}"
