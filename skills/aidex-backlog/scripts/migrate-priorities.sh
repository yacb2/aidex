#!/usr/bin/env bash
# migrate-priorities.sh — normalize legacy backlog priorities to P0–P3 codes.
#
# Idempotent: re-running on an already-migrated backlog is a no-op.
#
# What it touches:
#   - `**Priority**: <text>` lines in the body  → moves to YAML front-matter as `priority: PX`
#   - `priority: <legacy>` lines in front-matter → rewrites to `priority: PX`
#   - Adds `blocked_by: ""` field if missing.
#
# Legacy mapping:
#   Critical | Urgent | URGENT         → P0
#   High | high                        → P1
#   Medium | medium | Planned          → P2
#   Low | low                          → P3
#   anything else                      → reported as "needs manual review" (NOT touched)
#
# Usage:
#   migrate-priorities.sh              # default: DRY-RUN — print what would change
#   migrate-priorities.sh --apply      # write the changes
#   migrate-priorities.sh --dir <path> # operate on a custom backlog dir
#
# Dry-run by default, like sweep.sh and migrate-ids.sh beside it in the same
# table: a bare invocation used to rewrite front-matter in place with no preview
# and no prompt, the opposite polarity of its neighbours.

set -euo pipefail

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

DRY_RUN=1
DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)   DRY_RUN=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;   # accepted, and now redundant
    --dir)     DIR="$2"; shift 2 ;;
    -h|--help) sed -n '3,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if [[ -z "$DIR" ]]; then
  DIR="$(find_project_root)/.context/backlog"
fi
[[ -d "$DIR" ]] || die "no backlog directory at $DIR"

normalize() {
  case "$1" in
    P0|P1|P2|P3)                       echo "$1" ;;
    Critical|Urgent|URGENT|critical)   echo "P0" ;;
    High|high|HIGH)                    echo "P1" ;;
    Medium|medium|MEDIUM|Planned|planned) echo "P2" ;;
    Low|low|LOW)                       echo "P3" ;;
    *) return 1 ;;
  esac
}

changed=0
untouched=0
needs_review=0
no_frontmatter=0

for f in "$DIR"/*.md; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f")"
  [[ "$base" == _* ]] && continue
  [[ "$base" == 00-index.md ]] && continue

  # Detect whether file has YAML front-matter (first non-empty line is `---`).
  first_line="$(awk 'NF{print; exit}' "$f")"
  has_frontmatter=0
  [[ "$first_line" == "---" ]] && has_frontmatter=1

  yaml_prio="$(awk '
    /^---$/ { fm++; next }
    fm == 1 && /^priority:[[:space:]]/ {
      sub(/^priority:[[:space:]]*/, "")
      gsub(/^"|"$/, "")
      print; exit
    }
  ' "$f" | xargs)"

  body_prio="$(awk -F': ' '/^\*\*Priority\*\*:/ { sub(/^\*\*Priority\*\*:[[:space:]]*/, ""); print; exit }' "$f" | xargs)"

  raw=""
  source=""
  if [[ -n "$yaml_prio" ]]; then raw="$yaml_prio"; source="yaml"
  elif [[ -n "$body_prio" ]]; then raw="$body_prio"; source="body"
  else
    untouched=$((untouched+1)); continue
  fi

  # Without YAML front-matter the awk pass below can't rewrite — flag for manual conversion.
  if [[ $has_frontmatter -eq 0 ]]; then
    warn "  ! $f: no YAML front-matter (priority '$raw' lives in body) — needs manual conversion to YAML"
    no_frontmatter=$((no_frontmatter+1))
    continue
  fi

  # Extract Blocked annotation if embedded: "(Blocked: terceros)" or "blocked by: X"
  detected_blocked=""
  if [[ "$raw" =~ [Bb]locked[[:space:]]*(by)?[[:space:]]*:[[:space:]]*([^\)]+) ]]; then
    detected_blocked="$(printf '%s' "${BASH_REMATCH[2]}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/\)$//')"
  fi

  # Strip parenthetical notes like "Medium (tech debt — affects ...)" — keep just the head token.
  head_token="$(printf '%s' "$raw" | awk '{print $1}' | sed 's/[(),]//g')"

  if ! new="$(normalize "$head_token")"; then
    warn "  ? $f: priority '$raw' — needs manual review"
    needs_review=$((needs_review+1))
    continue
  fi

  # Already canonical and in YAML, and blocked_by present? Skip.
  has_blocked="$(awk '/^---$/ {fm++; next} fm==1 && /^blocked_by:/ {print "1"; exit}' "$f")"
  if [[ "$source" == "yaml" && "$raw" == "$new" && "$has_blocked" == "1" ]]; then
    untouched=$((untouched+1)); continue
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    note="${detected_blocked:+ (+ blocked_by: $detected_blocked)}"
    info "  → would migrate $f: [$source] '$raw' → '$new'$note"
    changed=$((changed+1))
    continue
  fi

  tmp="$(mktemp)"
  awk -v new="$new" -v add_blocked="${has_blocked:+0}${has_blocked:-1}" -v blocked_val="$detected_blocked" '
    BEGIN { fm = 0; wrote_prio = 0; wrote_blocked = 0 }
    /^---$/ {
      fm++
      if (fm == 2 && wrote_prio == 0) {
        print "priority: " new
        wrote_prio = 1
      }
      if (fm == 2 && add_blocked == "1" && wrote_blocked == 0) {
        printf "blocked_by: \"%s\"\n", blocked_val
        wrote_blocked = 1
      }
      print; next
    }
    fm == 1 && /^priority:/ {
      print "priority: " new
      wrote_prio = 1
      next
    }
    fm == 1 && /^blocked_by:/ {
      if (blocked_val != "") printf "blocked_by: \"%s\"\n", blocked_val
      else print
      wrote_blocked = 1
      next
    }
    fm >= 2 && /^\*\*Priority\*\*:/ { next }
    { print }
  ' "$f" > "$tmp"

  mv "$tmp" "$f"
  note="${detected_blocked:+ (+ blocked_by: $detected_blocked)}"
  ok "  ✓ migrated $f: '$raw' → '$new'$note"
  changed=$((changed+1))
done

printf '\n%sSummary:%s migrated=%d  untouched=%d  needs_review=%d  no_frontmatter=%d%s\n' \
  "$C_BOLD" "$C_DIM" "$changed" "$untouched" "$needs_review" "$no_frontmatter" "$C_RESET" >&2

[[ $DRY_RUN -eq 1 ]] && info "(dry-run — no files written)"
exit 0
