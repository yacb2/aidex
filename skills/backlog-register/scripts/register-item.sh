#!/usr/bin/env bash
# register-item.sh — create a backlog entry in .context/backlog/.
#
# Usage (non-interactive):
#   register-item.sh --origin <manual|audit|issue|request> [options]
#
# Options:
#   --title "<title>"              title for the entry (required for non-interactive)
#   --finding <id>                 (when --origin audit) finding ID
#   --audit-run <slug>             (when --origin audit) run folder name
#   --issue <id>                   (when --origin issue) issue ID
#   --request <file>               (when --origin request) request file path
#   --priority <P0|P1|P2|P3>       default: P2
#   --estimate <XS|S|M|L|XL>       default: M
#   --status <open|doing|done|dropped>  default: open
#   --slug <kebab-case>            override auto-generated slug
#   --list                         list open entries and exit
#
# Interactive mode (no args): prompts for title, origin, priority.
#
# On success, prints the created file path to stdout.

set -euo pipefail

# --- shared helpers (inlined so this script works standalone if audit's _lib.sh is absent) ---

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m'
  C_DIM=$'\033[2m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
else
  C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_DIM='' C_BOLD='' C_RESET=''
fi

info() { printf '%s%s%s\n' "$C_BLUE" "$*" "$C_RESET" >&2; }
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET" >&2; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
err()  { printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
die()  { err "error: $*"; exit 2; }

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.context" ]]; then printf '%s\n' "$dir"; return 0; fi
    dir="$(dirname "$dir")"
  done
  pwd -P
}

# Convert a title to a kebab-case slug (3–6 meaningful words).
title_to_slug() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' \
    | cut -c1-60 \
    | sed -E 's/-+$//'
}

# --- dispatcher: strip leading "backlog-register" if present ---
if [[ "${1:-}" == "backlog-register" ]]; then shift; fi

# --- parse args ---
ORIGIN=""
TITLE=""
FINDING=""
AUDIT_RUN=""
ISSUE=""
REQUEST=""
PRIORITY="P2"
ESTIMATE="M"
STATUS="open"
SLUG_OVERRIDE=""
LIST_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --origin)      ORIGIN="$2"; shift 2 ;;
    --title)       TITLE="$2"; shift 2 ;;
    --finding)     FINDING="$2"; shift 2 ;;
    --audit-run)   AUDIT_RUN="$2"; shift 2 ;;
    --issue)       ISSUE="$2"; shift 2 ;;
    --request)     REQUEST="$2"; shift 2 ;;
    --priority)    PRIORITY="$2"; shift 2 ;;
    --estimate)    ESTIMATE="$2"; shift 2 ;;
    --status)      STATUS="$2"; shift 2 ;;
    --slug)        SLUG_OVERRIDE="$2"; shift 2 ;;
    --list)        LIST_ONLY=1; shift ;;
    -h|--help)
      sed -n '3,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"

# --- handle --list ---
if [[ $LIST_ONLY -eq 1 ]]; then
  if [[ ! -d "$BACKLOG_DIR" ]]; then
    warn "no backlog directory at $BACKLOG_DIR"
    exit 0
  fi
  printf '%sOpen backlog entries:%s\n\n' "$C_BOLD" "$C_RESET"
  found=0
  for f in "$BACKLOG_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    status="$(awk -F': ' '/^status:/ {gsub(/"/, "", $2); print $2; exit}' "$f" | xargs)"
    [[ "$status" == "open" ]] || continue
    title="$(awk -F': ' '/^title:/ {gsub(/"/, "", $2); print $2; exit}' "$f" | xargs)"
    priority="$(awk -F': ' '/^priority:/ {gsub(/"/, "", $2); print $2; exit}' "$f" | xargs)"
    origin="$(awk -F': ' '/^origin:/ {gsub(/"/, "", $2); print $2; exit}' "$f" | xargs)"
    printf '  %s[%s]%s %s %s(%s)%s\n    %s%s%s\n\n' \
      "$C_YELLOW" "${priority:-??}" "$C_RESET" "$title" "$C_DIM" "$origin" "$C_RESET" \
      "$C_DIM" "$f" "$C_RESET"
    found=1
  done
  [[ $found -eq 0 ]] && printf '  (no open entries)\n'
  exit 0
fi

# --- interactive prompts if missing required fields ---
if [[ -z "$ORIGIN" && -t 0 ]]; then
  printf 'Origin [manual/audit/issue/request] (default: manual): ' >&2
  read -r ORIGIN
  ORIGIN="${ORIGIN:-manual}"
fi
ORIGIN="${ORIGIN:-manual}"

case "$ORIGIN" in
  manual|audit|issue|request) ;;
  *) die "invalid --origin: $ORIGIN (must be manual, audit, issue, or request)" ;;
esac

if [[ -z "$TITLE" && -t 0 ]]; then
  printf 'Title: ' >&2
  read -r TITLE
fi
[[ -z "$TITLE" ]] && die "--title is required (or run interactively)"

if [[ "$PRIORITY" == "P2" && -t 0 && $# -eq 0 ]]; then
  : # keep default silently when running under TTY with no args, already handled
fi

case "$PRIORITY" in P0|P1|P2|P3) ;; *) die "invalid priority: $PRIORITY" ;; esac
case "$ESTIMATE" in XS|S|M|L|XL) ;; *) die "invalid estimate: $ESTIMATE" ;; esac
case "$STATUS"   in open|doing|done|dropped) ;; *) die "invalid status: $STATUS" ;; esac

# --- derive origin_ref ---
ORIGIN_REF=""
case "$ORIGIN" in
  audit)
    [[ -n "$FINDING" ]] || die "--finding <id> is required when --origin audit"
    if [[ -n "$AUDIT_RUN" ]]; then
      ORIGIN_REF="audit/$AUDIT_RUN/$FINDING"
    else
      ORIGIN_REF="audit/$FINDING"
    fi
    ;;
  issue)
    [[ -n "$ISSUE" ]] || die "--issue <id> is required when --origin issue"
    ORIGIN_REF="issue/$ISSUE"
    ;;
  request)
    [[ -n "$REQUEST" ]] || die "--request <file> is required when --origin request"
    ORIGIN_REF="request/$REQUEST"
    ;;
esac

# --- compute slug ---
if [[ -n "$SLUG_OVERRIDE" ]]; then
  SLUG="$SLUG_OVERRIDE"
else
  SLUG="$(title_to_slug "$TITLE")"
fi
[[ -n "$SLUG" ]] || die "could not derive slug from title"

DATE="$(date +%Y%m%d)"
DATE_ISO="$(date +%Y-%m-%d)"
OUT_FILE="$BACKLOG_DIR/$DATE-$SLUG.md"

# Avoid clobbering: if file exists, append a counter
n=2
while [[ -e "$OUT_FILE" ]]; do
  OUT_FILE="$BACKLOG_DIR/$DATE-$SLUG-$n.md"
  n=$((n+1))
done

mkdir -p "$BACKLOG_DIR"

# --- write entry ---
{
  cat <<EOF
---
title: "$TITLE"
status: $STATUS
origin: $ORIGIN
origin_ref: ${ORIGIN_REF:-}
priority: $PRIORITY
estimate: $ESTIMATE
created: $DATE_ISO
updated: $DATE_ISO
---

# $TITLE

## Context

<!-- Why is this worth doing? What problem does it solve? Keep to 2-5 sentences. -->

## Acceptance

- [ ] <!-- concrete, verifiable criterion -->

## Notes

EOF

  if [[ "$ORIGIN" == "audit" ]]; then
    echo "- Origin: audit finding [$FINDING]"
    [[ -n "$AUDIT_RUN" ]] && echo "  - Audit run: \`.context/audits/$AUDIT_RUN/\`"
  fi
} > "$OUT_FILE"

ok "Backlog entry created"
printf '  %s\n' "$OUT_FILE" >&2

# Emit the path to stdout so callers (like /audit escalate) can capture it
printf '%s\n' "$OUT_FILE"
