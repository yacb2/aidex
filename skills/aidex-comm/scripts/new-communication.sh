#!/usr/bin/env bash
# new-communication.sh — scaffold a communication log entry in .context/communications/.
# Usage: new-communication.sh <received|sent|meeting|call> <slug> [--channel <email|whatsapp|other>]
#   <received|sent>: async correspondence direction; received goes under received/, sent under sent/.
#   <meeting|call>:  synchronous, multi-party conversation; both go under meetings/ (no direction).
#   <slug>: kebab-case identifier, e.g. "client-pricing-question"
#   --channel: async only; defaults to email. Ignored for meeting/call (the kind is the channel).
#
# Reads the workspace communications style profile (.context/communication-style.md) and
# renders it into the scaffolded body, so voice/sign-off/tone/address/date format are in
# front of whoever writes the body instead of being corrected afterwards (BL-216). A
# project with no profile gets the documented defaults, never an error.
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

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# aidex-conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

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

# --- Communications style profile (BL-216) ---------------------------------------
# Same shape as .context/artifact-style.md: a human-readable markdown file whose
# machine-readable part is the first fenced block under `## Profile`. Five axes, each
# with a shipped default, because a workspace with no profile must still scaffold.
STYLE_PROFILE_REL=".context/communication-style.md"
STYLE_AXES="voice sign_off tone address date_format"

# Shipped defaults, one per axis. A case statement rather than an associative array:
# macOS ships bash 3.2, where `declare -A` does not exist and the assignment fails
# under `set -u` with an unhelpful "unbound variable" (caught in probe, 2026-08-24).
style_default() {
  case "$1" in
    voice)       printf '%s' "first-person singular — never the editorial 'we' for work one person did" ;;
    sign_off)    printf '%s' "none — the message ends with its last paragraph, no signature block" ;;
    tone)        printf '%s' "cordial-professional — one line of courtesy opening and closing, plain vocabulary" ;;
    address)     printf '%s' "mirror the interlocutor's own register" ;;
    date_format) printf '%s' "spelled out in the body's own language (front-matter stays ISO per D-01)" ;;
  esac
}

# Echo the profile's machine-readable part: the first fenced block under `## Profile`.
# Same shape as .context/artifact-style.md — human-readable file, one parsed section.
read_style_profile() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    /^##[[:space:]]+Profile[[:space:]]*$/ { in_section = 1; next }
    in_section && /^##[[:space:]]/        { exit }
    in_section && /^```/                  { in_fence = !in_fence; if (!in_fence) exit; next }
    in_fence                              { print }
  ' "$file"
}

# The value for one axis, or the shipped default when the profile omits it. Keys the
# profile carries that are not axes are ignored rather than rejected: the file is
# documentation first, config second.
style_value() {
  local axis="$1" file="$2" line val=""
  while IFS= read -r line; do
    case "$line" in
      "$axis":*) val="${line#*:}" ;;
      *) continue ;;
    esac
    val="${val# }"
    val="${val%\"}"; val="${val#\"}"
    [[ -n "$val" ]] && { printf '%s' "$val"; return 0; }
  done < <(read_style_profile "$file")
  style_default "$axis"
}

# Render the profile as the guidance block the body template embeds.
style_block() {
  local file="$1" axis
  if [[ -f "$file" ]]; then
    printf '     HOUSE STYLE (from %s — edit it there, not here):\n' "$STYLE_PROFILE_REL"
  else
    printf '     HOUSE STYLE (defaults — no %s in this workspace):\n' "$STYLE_PROFILE_REL"
  fi
  for axis in $STYLE_AXES; do
    printf '       - %-12s %s\n' "$axis:" "$(style_value "$axis" "$file")"
  done
}

# Swap the {{STYLE}} placeholder line for the rendered block. NOT done through
# render_template: that one substitutes with sed, and a literal newline in a sed
# replacement is invalid — a multi-line value would have silently mangled the file.
inject_style() {
  local out="$1" block_file="$2"
  awk -v bf="$block_file" '
    index($0, "{{STYLE}}") {
      while ((getline line < bf) > 0) print line
      close(bf); next
    }
    { print }
  ' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
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
  STYLE_TMP="$(mktemp)"
  style_block "$ROOT/$STYLE_PROFILE_REL" > "$STYLE_TMP"
  inject_style "$OUT" "$STYLE_TMP"
  rm -f "$STYLE_TMP"
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
