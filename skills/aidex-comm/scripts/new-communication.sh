#!/usr/bin/env bash
# new-communication.sh — scaffold a communication log entry in .context/communications/.
# Usage: new-communication.sh <received|sent|meeting|call> <slug> [--channel <email|whatsapp|other>]
#   <received|sent>: async correspondence direction; received goes under received/, sent under sent/.
#   <meeting|call>:  synchronous, multi-party conversation; both go under meetings/ (no direction).
#   <slug>: kebab-case identifier, e.g. "client-pricing-question"
#   --channel: async only; defaults to email. Ignored for meeting/call (the kind is the channel).
#
# Scaffolds .context/communications/<folder>/<YYYY-MM-DD>-<slug>/body.md from the template.
# received entries default to status=sent (a record); sent entries default to status=draft;
# meeting/call entries default to status=sent (they already happened).
# Self-contained: inlines its helpers so it does not depend on a sibling _lib.sh.
# Refuses to overwrite. On success, prints the created file path to stdout.

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

usage() {
  cat <<EOF >&2
Usage: /aidex-comm new <received|sent|meeting|call> <slug> [--channel <email|whatsapp|other>]

Examples:
  /aidex-comm new received client-pricing-question --channel email
  /aidex-comm new sent followup-proposal --channel whatsapp
  /aidex-comm new meeting access-core-kickoff
  /aidex-comm new call supplier-delivery-date
EOF
  exit 2
}

# Strip leading "new" dispatched by the skill.
if [[ "${1:-}" == "new" ]]; then shift; fi

KIND="${1:-}"
SLUG="${2:-}"
CHANNEL="email"

# Consume positionals, then parse the optional flag.
[[ -n "$KIND" && -n "$SLUG" ]] || usage
shift 2 || usage
while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel) CHANNEL="${2:-}"; shift 2 || die "--channel needs a value" ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1" ;;
  esac
done

is_valid_slug "$SLUG" || die "invalid slug: $SLUG (use kebab-case: lowercase letters, digits, hyphens)"

# Resolve folder, template, channel and initial status from the kind.
#   received/sent → async, directional, body.md.template (from/to)
#   meeting/call  → synchronous, non-directional, meeting.md.template (participants)
case "$KIND" in
  received) FOLDER="received"; TEMPLATE="body.md.template";    SYNC=0; STATUS="sent"  ;;
  sent)     FOLDER="sent";     TEMPLATE="body.md.template";    SYNC=0; STATUS="draft" ;;
  meeting)  FOLDER="meetings"; TEMPLATE="meeting.md.template"; SYNC=1; STATUS="sent"; CHANNEL="meeting" ;;
  call)     FOLDER="meetings"; TEMPLATE="meeting.md.template"; SYNC=1; STATUS="sent"; CHANNEL="call"    ;;
  *) die "kind must be 'received', 'sent', 'meeting', or 'call' (got: $KIND)" ;;
esac

# --channel is an async-only modifier. For meeting/call the channel is fixed to the kind.
if [[ "$SYNC" -eq 0 ]]; then
  case "$CHANNEL" in
    email|whatsapp|other) ;;
    *) die "invalid channel for $KIND: $CHANNEL (use email|whatsapp|other; for calls/meetings use 'new call' / 'new meeting')" ;;
  esac
fi

ROOT="$(find_project_root)"
DATE_ISO="$(today_iso)"
ENTRY_DIR="$ROOT/.context/communications/$FOLDER/$DATE_ISO-$SLUG"
OUT="$ENTRY_DIR/body.md"

[[ -e "$OUT" ]] && die "refusing to overwrite existing file: $OUT"
mkdir -p "$ENTRY_DIR"

if [[ "$SYNC" -eq 1 ]]; then
  render_template "$TEMPLATES_DIR/$TEMPLATE" "$OUT" \
    CHANNEL="$CHANNEL" STATUS="$STATUS" SLUG="$SLUG" DATE="$DATE_ISO"
else
  render_template "$TEMPLATES_DIR/$TEMPLATE" "$OUT" \
    CHANNEL="$CHANNEL" DIRECTION="$KIND" STATUS="$STATUS" SLUG="$SLUG" DATE="$DATE_ISO"
fi

ok "Communication scaffolded: $OUT"
if [[ "$SYNC" -eq 1 ]]; then
  cat >&2 <<EOF

Next steps:
  1. Fill participants (and organizer), subject, and write the notes in the conversation's native language.
  2. Drop any attachments alongside body.md in: $ENTRY_DIR/  (transcript, recording link, slides)
  3. Cross-link any request/decision this spawned via 'related'.
EOF
else
  cat >&2 <<EOF

Next steps:
  1. Fill from/to/subject and write the body in the communication's native language.
  2. Drop any attachments alongside body.md in: $ENTRY_DIR/
  3. For a sent draft: when it goes out, set status: sent and update 'updated'.
EOF
fi

# Machine-readable path on stdout.
printf '%s\n' "$OUT"
