#!/usr/bin/env bash
# start-item.sh — the open → doing transition, and the structural route into
# RED→GREEN for bug work.
#
# Usage:
#   start-item.sh <BL-id | filename | path> [--no-index]
#
# Sets `status: doing`, stamps `updated`, rebuilds the index, and — when the
# item's front-matter carries `type: bug` — prints the RED→GREEN handoff.
#
# Why this exists (BL-134). Across 103 eligible bug items, `aidex-bugfix` fired
# on 3. It was not losing to silence (only 4 items ran with no skill at all): it
# was losing the race to `aidex-backlog`, first on 23. Its trigger describes a
# bug-*report* conversation, but a tracked bug item is entered through the
# backlog lifecycle instead — a doorway the work no longer walks through. The
# remedy is a front-matter condition, not a reworded description: `type: bug` is
# already in the file, so the route is deterministic and needs no phrase match.
#
# Options:
#   --no-index    skip index regeneration

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

TARGET="" NO_INDEX=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-index) NO_INDEX=1; shift ;;
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)         die "unknown option: $1" ;;
    *)          TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || die "target required: <BL-id | filename | path>"

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

read_field() {
  awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":"{
    sub(/^[^:]*:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"
}

# --- resolve target to an active backlog item ---
FILE=""
if [[ "$TARGET" =~ ^[Bb][Ll]-[0-9]+$ ]]; then
  TARGET_UC="$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')"
  for f in "$BACKLOG_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(read_field "$f" id)" == "$TARGET_UC" ]] && { FILE="$f"; break; }
  done
  # A deferred item is open-but-blocked, not startable — say which, don't guess.
  if [[ -z "$FILE" ]]; then
    for f in "$BACKLOG_DIR"/_deferred/*.md; do
      [[ -f "$f" ]] || continue
      [[ "$(read_field "$f" id)" == "$TARGET_UC" ]] && \
        die "$TARGET_UC is deferred (blocked). Run: defer-item.sh reactivate $TARGET_UC"
    done
    die "no active backlog item with id $TARGET_UC (already closed?)"
  fi
elif [[ -f "$TARGET" ]]; then
  FILE="$TARGET"
elif [[ -f "$BACKLOG_DIR/$TARGET" ]]; then
  FILE="$BACKLOG_DIR/$TARGET"
else
  die "cannot resolve target: $TARGET"
fi

[[ "$(dirname "$FILE")" == "$BACKLOG_DIR" ]] || die "target is not an active backlog item: $FILE"

TODAY="$(date +%Y-%m-%d)"

# --- status -> doing, stamp updated (idempotent: re-starting a `doing` item is a no-op) ---
awk -v today="$TODAY" '
  BEGIN { d=0; infm=0 }
  /^---[[:space:]]*$/ { d++; if (d==1) infm=1; else if (d==2) infm=0; print; next }
  infm==1 {
    if ($0 ~ /^status:/)  { print "status: doing"; next }
    if ($0 ~ /^updated:/) { print "updated: " today; next }
    print; next
  }
  { print }
' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

TYPE="$(read_field "$FILE" type)"
TITLE="$(read_field "$FILE" title)"
ID="$(read_field "$FILE" id)"

ok "Started ${ID:-$(basename "$FILE")} → doing · ${TITLE}"

if [[ $NO_INDEX -eq 0 ]]; then
  bash "$SCRIPT_DIR/register-item.sh" --reindex >/dev/null
  ok "  index rebuilt"
fi

# --- the route: type: bug is the mechanical entry into RED->GREEN ---
if [[ "$TYPE" == "bug" ]]; then
  cat >&2 <<'ROUTE'

--------------------------------------------------------------------
BUG ITEM (type: bug) — enter the RED->GREEN procedure now
--------------------------------------------------------------------
This is bug work. The regression test is written BEFORE the fix, and
is not optional. Follow aidex-bugfix (skills/aidex-bugfix/SKILL.md):

  1. Investigate the root cause (do not guess)
  2. Write the regression test - it must FAIL
  3. Confirm it fails for the RIGHT reason (the message names the
     buggy behavior, not an import/syntax/setup error)
  4. Implement the minimum fix
  5. Confirm GREEN - capture the output as proof
  6. Run the surrounding suite (no regressions)
  7. Commit test + fix together

On close, record the proof: one commit-body line naming the RED
failure and the GREEN command + result, or `proof_links` for a
larger capture. close-item.sh warns when a bug item closes without it.

Exception: purely visual/CSS bugs - aidex-bugfix, "Exception" section.
--------------------------------------------------------------------
ROUTE
elif [[ -z "$TYPE" ]]; then
  warn "  no 'type' in front-matter — if this is bug work, set type: bug and re-run"
fi

printf '%s\n' "$FILE"
