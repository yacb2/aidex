#!/usr/bin/env bash
# close-plan.sh — atomically close a plan (D-10): set status, record resolving
# commit(s), stamp `updated`, move the plan (modular dir or single file) to
# plans/_archive/. Handles both single-file and modular (dir + 00-index.md) plans.
#
# Usage:
#   close-plan.sh <slug | path> [options]
#
# Options:
#   --status <done|dropped>     default: done
#   --commit <sha>              resolving commit (repeatable). When work was
#                               escalated to this plan, commits live HERE (D-09).
#   --superseded-by <type/ref>  mark superseded (status stays; modifier records it)
#   --reason "<text>"           appended under a closing note
#
# After closing, run `reconcile.sh` (Phase 6) to surface upstream backlog/findings
# that this plan resolved and may now be closeable.

set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_RED=$'\033[31m' C_RESET=$'\033[0m'
else C_GREEN='' C_RED='' C_RESET=''; fi
ok()  { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET" >&2; }
die() { printf '%serror: %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; exit 2; }

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  pwd -P
}

TARGET="" STATUS="done" SUPERSEDED="" REASON=""
COMMITS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)        STATUS="$2"; shift 2 ;;
    --commit)        COMMITS+=("$2"); shift 2 ;;
    --superseded-by) SUPERSEDED="$2"; shift 2 ;;
    --reason)        REASON="$2"; shift 2 ;;
    -h|--help)       sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)              die "unknown option: $1" ;;
    *)               TARGET="$1"; shift ;;
  esac
done

[[ -n "$TARGET" ]] || die "target required: <slug | path>"
case "$STATUS" in done|dropped) ;; *) die "invalid --status: $STATUS (done|dropped)";; esac

ROOT="$(find_project_root)"
PLANS_DIR="$ROOT/.context/plans"

# --- resolve target to a plan (dir or single file) and its front-matter file ---
PLAN_PATH="" FM_FILE=""
if [[ -d "$TARGET" ]]; then PLAN_PATH="$TARGET"
elif [[ -f "$TARGET" ]]; then PLAN_PATH="$TARGET"
elif [[ -d "$PLANS_DIR/$TARGET" ]]; then PLAN_PATH="$PLANS_DIR/$TARGET"
elif [[ -f "$PLANS_DIR/$TARGET" ]]; then PLAN_PATH="$PLANS_DIR/$TARGET"
elif [[ -f "$PLANS_DIR/$TARGET.md" ]]; then PLAN_PATH="$PLANS_DIR/$TARGET.md"
else die "cannot resolve plan: $TARGET"; fi

if [[ -d "$PLAN_PATH" ]]; then
  FM_FILE="$PLAN_PATH/00-index.md"
  [[ -f "$FM_FILE" ]] || die "modular plan has no 00-index.md: $PLAN_PATH"
else
  FM_FILE="$PLAN_PATH"
fi

# guard: must live under plans/ active (not already in _archive)
case "$PLAN_PATH" in
  */_archive/*) die "plan already archived: $PLAN_PATH" ;;
esac

TODAY="$(date +%Y-%m-%d)"
COMMITS_STR="${COMMITS[*]:-}"

awk -v status="$STATUS" -v today="$TODAY" -v sup="$SUPERSEDED" -v commits="$COMMITS_STR" '
  BEGIN { d=0; infm=0; seen_sup=0; seen_commits=0 }
  /^---[[:space:]]*$/ {
    d++
    if (d==1) { infm=1; print; next }
    if (d==2) {
      if (sup!="" && !seen_sup) print "superseded_by: " sup
      if (commits!="" && !seen_commits) print "commits: \"" commits "\""
      infm=0; print; next
    }
  }
  infm==1 {
    if ($0 ~ /^status:/)  { print "status: " status; next }
    if ($0 ~ /^updated:/) { print "updated: " today; next }
    if (sup!="" && $0 ~ /^superseded_by:/) { print "superseded_by: " sup; seen_sup=1; next }
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
' "$FM_FILE" > "$FM_FILE.tmp" && mv "$FM_FILE.tmp" "$FM_FILE"

[[ -n "$REASON" ]] && printf -- '\n> Closing note (%s): %s\n' "$TODAY" "$REASON" >> "$FM_FILE"

mkdir -p "$PLANS_DIR/_archive"
DEST="$PLANS_DIR/_archive/$(basename "$PLAN_PATH")"
[[ -e "$DEST" ]] && die "archive collision: $DEST already exists"
mv "$PLAN_PATH" "$DEST"
ok "Closed plan $(basename "$PLAN_PATH") → $STATUS · archived"
[[ -n "$COMMITS_STR" ]] && ok "  commits: $COMMITS_STR"
printf '%s\n' "$DEST"
