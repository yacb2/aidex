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
#   --priority <P0|P1|P2|P3>       default: P2 (code only — see references/01-backlog-conventions.md)
#   --blocked-by "<who/what>"      optional Blocked modifier; priority is kept, item listed under Blocked
#   --estimate <XS|S|M|L|XL>       default: M
#   --status <open|doing|done|dropped>  default: open
#   --slug <kebab-case>            override auto-generated slug
#   --list                         list open entries grouped by priority (P0 → P3 + Blocked)
#   --reindex                      regenerate 00-index.md from front-matter, then exit
#   --no-index                     skip auto-regen of 00-index.md after writing entry
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

# Compute the next sequential backlog id (BL-NNN). Scans active + _archive + _deferred
# so no item's id is ever reused — ids stay stable for commit-trailer refs (D-09).
next_backlog_id() {
  local dir="$1" max=0 n f
  shopt -s nullglob
  for f in "$dir"/*.md "$dir"/_archive/*.md "$dir"/_deferred/*.md; do
    [[ -f "$f" ]] || continue
    n="$(awk '/^---[[:space:]]*$/{c++; if(c==2) exit} c==1 && $1 ~ /^id:/ {v=$2; gsub(/[^0-9]/,"",v); print v; exit}' "$f")"
    [[ -n "$n" ]] && (( 10#$n > max )) && max=$((10#$n))
  done
  shopt -u nullglob
  printf 'BL-%03d' $((max+1))
}

# --- dispatcher: strip leading "aidex-backlog" if present ---
if [[ "${1:-}" == "aidex-backlog" ]]; then shift; fi

# --- parse args ---
ORIGIN=""
TITLE=""
FINDING=""
AUDIT_RUN=""
ISSUE=""
REQUEST=""
PRIORITY=""
BLOCKED_BY=""
ESTIMATE="M"
STATUS="open"
SLUG_OVERRIDE=""
LIST_ONLY=0
REINDEX_ONLY=0
NO_INDEX=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --origin)      ORIGIN="$2"; shift 2 ;;
    --title)       TITLE="$2"; shift 2 ;;
    --finding)     FINDING="$2"; shift 2 ;;
    --audit-run)   AUDIT_RUN="$2"; shift 2 ;;
    --issue)       ISSUE="$2"; shift 2 ;;
    --request)     REQUEST="$2"; shift 2 ;;
    --priority)    PRIORITY="$2"; shift 2 ;;
    --blocked-by)  BLOCKED_BY="$2"; shift 2 ;;
    --estimate)    ESTIMATE="$2"; shift 2 ;;
    --status)      STATUS="$2"; shift 2 ;;
    --slug)        SLUG_OVERRIDE="$2"; shift 2 ;;
    --list)        LIST_ONLY=1; shift ;;
    --reindex)     REINDEX_ONLY=1; shift ;;
    --no-index)    NO_INDEX=1; shift ;;
    -h|--help)
      sed -n '3,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"

# --- regen_index: rebuild 00-index.md from front-matter (canon §"00-index.md") ---
regen_index() {
  local dir="$1"
  [[ -d "$dir" ]] || { warn "no backlog directory at $dir"; return 0; }

  local index_file="$dir/00-index.md"
  local today; today="$(date +%Y-%m-%d)"

  # Single awk pass per file: emit status, title, priority, estimate, blocked_by tab-separated.
  read_fm_fields() {
    awk '
      BEGIN { FS=": " }
      /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
      fm==1 {
        key=$1
        if (key!="status" && key!="title" && key!="priority" && key!="estimate" && key!="blocked_by") next
        sub(/^[^:]*: */, "")
        gsub(/^"|"$/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        vals[key]=$0
      }
      END {
        printf "%s\t%s\t%s\t%s\t%s",
          vals["status"], vals["title"], vals["priority"], vals["estimate"], vals["blocked_by"]
      }
    ' "$1"
  }

  # Closed-section reader: status, title, id, updated, superseded_by, escalated_to.
  read_closed_fields() {
    awk '
      BEGIN { FS=": " }
      /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
      fm==1 {
        key=$1
        if (key!="status" && key!="title" && key!="id" && key!="updated" && key!="superseded_by" && key!="escalated_to") next
        sub(/^[^:]*: */, "")
        gsub(/^"|"$/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        vals[key]=$0
      }
      END {
        printf "%s\t%s\t%s\t%s\t%s\t%s",
          vals["status"], vals["title"], vals["id"], vals["updated"], vals["superseded_by"], vals["escalated_to"]
      }
    ' "$1"
  }

  # Deferred-section reader: title, id, priority, updated, blocked_by.
  read_deferred_fields() {
    awk '
      BEGIN { FS=": " }
      /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
      fm==1 {
        key=$1
        if (key!="title" && key!="id" && key!="priority" && key!="updated" && key!="blocked_by") next
        sub(/^[^:]*: */, "")
        gsub(/^"|"$/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        vals[key]=$0
      }
      END {
        printf "%s\t%s\t%s\t%s\t%s",
          vals["title"], vals["id"], vals["priority"], vals["updated"], vals["blocked_by"]
      }
    ' "$1"
  }

  local -a SEC_P0=() SEC_P1=() SEC_P2=() SEC_P3=() SEC_BLOCKED=()
  local active_count=0 doing_count=0

  local f base title status priority estimate blocked_by line fields
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "00-index.md" ]] && continue

    fields="$(read_fm_fields "$f")"
    IFS=$'\t' read -r status title priority estimate blocked_by <<<"$fields"
    [[ -z "$title" ]] && title="(untitled)"

    case "$status" in
      open|doing) ;;
      *) continue ;;
    esac

    if [[ -n "$blocked_by" ]]; then
      line="- **[${title}](${base})** — ${status} · ${priority:-P?} · blocked_by: \"${blocked_by}\""
      SEC_BLOCKED+=("$line")
      continue
    fi

    [[ "$status" == "doing" ]] && doing_count=$((doing_count+1))
    [[ "$status" == "open" ]]  && active_count=$((active_count+1))

    line="- **[${title}](${base})** — ${status} · ${estimate:-?}"
    case "$priority" in
      P0) SEC_P0+=("$line") ;;
      P1) SEC_P1+=("$line") ;;
      P2) SEC_P2+=("$line") ;;
      P3) SEC_P3+=("$line") ;;
      *)  SEC_P2+=("$line") ;;
    esac
  done

  # Closed section: one-liner per archived item, newest-closed first (D-10).
  local -a CLOSED_SORTED=()
  local cid ctitle cstatus cupdated csuperseded cescalated clabel cline cbase
  if [[ -d "$dir/_archive" ]]; then
    local -a closed_tmp=()
    for f in "$dir"/_archive/*.md; do
      [[ -f "$f" ]] || continue
      cbase="$(basename "$f")"
      [[ "$cbase" == "00-index.md" ]] && continue
      fields="$(read_closed_fields "$f")"
      IFS=$'\t' read -r cstatus ctitle cid cupdated csuperseded cescalated <<<"$fields"
      [[ -z "$ctitle" ]] && ctitle="(untitled)"
      if [[ -n "$csuperseded" ]]; then clabel="superseded → ${csuperseded}"
      elif [[ -n "$cescalated" ]]; then clabel="${cstatus:-done} → ${cescalated}"
      else clabel="${cstatus:-done}"; fi
      cline="- ${cid:+${cid} }[${ctitle}](_archive/${cbase}) — ${clabel}${cupdated:+ · ${cupdated}}"
      # prefix with sort key (updated date, fallback empty sorts last)
      closed_tmp+=("${cupdated:-0000-00-00}"$'\t'"$cline")
    done
    if [[ ${#closed_tmp[@]} -gt 0 ]]; then
      while IFS= read -r line; do
        CLOSED_SORTED+=("${line#*$'\t'}")
      done < <(printf '%s\n' "${closed_tmp[@]}" | sort -r)
    fi
  fi

  # Deferred section: open-but-blocked items parked in _deferred/, newest first.
  local -a DEFERRED_SORTED=()
  local did dtitle dpriority dupdated dblocked dline dbase
  if [[ -d "$dir/_deferred" ]]; then
    local -a deferred_tmp=()
    for f in "$dir"/_deferred/*.md; do
      [[ -f "$f" ]] || continue
      dbase="$(basename "$f")"
      [[ "$dbase" == "00-index.md" ]] && continue
      fields="$(read_deferred_fields "$f")"
      IFS=$'\t' read -r dtitle did dpriority dupdated dblocked <<<"$fields"
      [[ -z "$dtitle" ]] && dtitle="(untitled)"
      dline="- ${did:+${did} }[${dtitle}](_deferred/${dbase}) — ${dpriority:-P?} · blocked_by: \"${dblocked}\"${dupdated:+ · ${dupdated}}"
      deferred_tmp+=("${dupdated:-0000-00-00}"$'\t'"$dline")
    done
    if [[ ${#deferred_tmp[@]} -gt 0 ]]; then
      while IFS= read -r line; do
        DEFERRED_SORTED+=("${line#*$'\t'}")
      done < <(printf '%s\n' "${deferred_tmp[@]}" | sort -r)
    fi
  fi

  {
    printf '# Backlog\n\n'
    printf '_Auto-generated by `aidex-backlog` from front-matter. Do not edit by hand._\n\n'
    printf '**Updated:** %s\n' "$today"
    printf '**Active:** %d · **Blocked:** %d · **Doing:** %d\n\n' "$active_count" "${#SEC_BLOCKED[@]}" "$doing_count"

    emit_section() {
      local heading="$1"; shift
      local first="${1:-}"
      [[ -z "$first" ]] && return
      printf '## %s\n\n' "$heading"
      printf '%s\n' "$@"
      printf '\n'
    }

    [[ ${#SEC_P0[@]}      -gt 0 ]] && emit_section "P0 — Critical" "${SEC_P0[@]}"
    [[ ${#SEC_P1[@]}      -gt 0 ]] && emit_section "P1 — High"     "${SEC_P1[@]}"
    [[ ${#SEC_P2[@]}      -gt 0 ]] && emit_section "P2 — Medium"   "${SEC_P2[@]}"
    [[ ${#SEC_P3[@]}      -gt 0 ]] && emit_section "P3 — Low"      "${SEC_P3[@]}"
    [[ ${#SEC_BLOCKED[@]} -gt 0 ]] && emit_section "Blocked"       "${SEC_BLOCKED[@]}"

    if [[ ${#DEFERRED_SORTED[@]} -gt 0 ]]; then
      printf '## Deferred\n\n'
      printf '_Open but blocked — parked in [`_deferred/`](_deferred/), not in the active queue. Reactivate with `defer`/`reactivate`:_\n\n'
      printf '%s\n' "${DEFERRED_SORTED[@]}"
      printf '\n'
    fi

    printf -- '---\n\n'
    if [[ ${#CLOSED_SORTED[@]} -gt 0 ]]; then
      printf '## Closed\n\n'
      printf '_Closed items (full bodies in [`_archive/`](_archive/)):_\n\n'
      # Window to the most recent 20 closures; older ones live in _archive/, so the
      # index tracks the active queue instead of lifetime throughput (BL-058).
      if [[ ${#CLOSED_SORTED[@]} -gt 20 ]]; then
        printf '%s\n' "${CLOSED_SORTED[@]:0:20}"
        printf '…and %d older closed items — see [`_archive/`](_archive/)\n' "$((${#CLOSED_SORTED[@]} - 20))"
      else
        printf '%s\n' "${CLOSED_SORTED[@]}"
      fi
      printf '\n'
    else
      printf '_Archived items: see [`_archive/`](_archive/)._\n'
    fi
  } > "$index_file"

  ok "Regenerated $index_file"
}

# --- handle --reindex ---
if [[ $REINDEX_ONLY -eq 1 ]]; then
  regen_index "$BACKLOG_DIR"
  exit 0
fi

# --- handle --list (grouped by priority, with Blocked section) ---
if [[ $LIST_ONLY -eq 1 ]]; then
  if [[ ! -d "$BACKLOG_DIR" ]]; then
    warn "no backlog directory at $BACKLOG_DIR"
    exit 0
  fi

  read_field() {
    # trim inside awk — piping through xargs broke on unbalanced quotes (apostrophes)
    awk -F': ' -v key="$1" '
      $1 == key {
        sub(/^[^:]*: */, ""); gsub(/^"|"$/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit
      }
    ' "$2"
  }

  declare -a P0=() P1=() P2=() P3=() PUNK=() BLOCKED=()
  for f in "$BACKLOG_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    status="$(read_field status "$f")"
    [[ "$status" == "open" ]] || continue
    title="$(read_field title "$f")"
    priority="$(read_field priority "$f")"
    origin="$(read_field origin "$f")"
    blocked="$(read_field blocked_by "$f")"
    line="$(printf '  - %s %s(%s)%s\n      %s%s%s' \
      "${title:-(untitled)}" "$C_DIM" "${origin:-?}" "$C_RESET" \
      "$C_DIM" "$f" "$C_RESET")"
    if [[ -n "$blocked" ]]; then
      BLOCKED+=("$(printf '  - [%s] %s — blocked by: %s\n      %s%s%s' \
        "${priority:-??}" "${title:-(untitled)}" "$blocked" "$C_DIM" "$f" "$C_RESET")")
      continue
    fi
    case "$priority" in
      P0) P0+=("$line") ;;
      P1) P1+=("$line") ;;
      P2) P2+=("$line") ;;
      P3) P3+=("$line") ;;
      *)  PUNK+=("$(printf '  - [%s] %s\n      %s%s%s' \
            "${priority:-??}" "${title:-(untitled)}" "$C_DIM" "$f" "$C_RESET")") ;;
    esac
  done

  print_section() {
    local title="$1" color="$2"; shift 2
    local items=("$@")
    [[ ${#items[@]} -eq 0 ]] && return
    printf '\n%s%s%s\n' "$color$C_BOLD" "$title" "$C_RESET"
    printf '%s\n' "${items[@]}"
  }

  printf '%sOpen backlog entries (grouped by priority):%s\n' "$C_BOLD" "$C_RESET"
  print_section "P0 — Critical"   "$C_RED"    "${P0[@]:-}"
  print_section "P1 — High"       "$C_YELLOW" "${P1[@]:-}"
  print_section "P2 — Medium"     "$C_BLUE"   "${P2[@]:-}"
  print_section "P3 — Low"        "$C_DIM"    "${P3[@]:-}"
  print_section "Blocked (third-party)" "$C_DIM" "${BLOCKED[@]:-}"
  print_section "Unclassified (legacy — run migrate-priorities.sh)" "$C_RED" "${PUNK[@]:-}"

  total=$((${#P0[@]} + ${#P1[@]} + ${#P2[@]} + ${#P3[@]} + ${#PUNK[@]} + ${#BLOCKED[@]}))
  [[ $total -eq 0 ]] && printf '\n  (no open entries)\n'
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

if [[ -z "$PRIORITY" && -t 0 ]]; then
  printf '\n%sPriority taxonomy:%s\n' "$C_BOLD" "$C_RESET" >&2
  printf '  %sP0%s — Critical   Production bug · security breach · CI blocked · data loss        (this week)\n' "$C_RED" "$C_RESET" >&2
  printf '  %sP1%s — High       Blocking flow · data quality · severe regression · external SLA  (2 weeks)\n' "$C_YELLOW" "$C_RESET" >&2
  printf '  %sP2%s — Medium     Important non-blocking · scoped tech debt · significant UX       (next release)\n' "$C_BLUE" "$C_RESET" >&2
  printf '  %sP3%s — Low        Nice-to-have · cosmetic refactor · pull-driven                   (no date)\n' "$C_DIM" "$C_RESET" >&2
  printf '\nPriority [P0/P1/P2/P3] (default: P2): ' >&2
  read -r PRIORITY
  PRIORITY="${PRIORITY:-P2}"
fi
PRIORITY="${PRIORITY:-P2}"

case "$PRIORITY" in
  P0|P1|P2|P3) ;;
  p0|p1|p2|p3) PRIORITY="$(echo "$PRIORITY" | tr '[:lower:]' '[:upper:]')" ;;
  *) die "invalid priority: '$PRIORITY' (must be P0, P1, P2, or P3 — see references/01-backlog-conventions.md)" ;;
esac
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

DATE_ISO="$(date +%Y-%m-%d)"
OUT_FILE="$BACKLOG_DIR/$DATE_ISO-$SLUG.md"

# Avoid clobbering: if file exists, append a counter
n=2
while [[ -e "$OUT_FILE" ]]; do
  OUT_FILE="$BACKLOG_DIR/$DATE_ISO-$SLUG-$n.md"
  n=$((n+1))
done

mkdir -p "$BACKLOG_DIR"

# --- assign stable short id (BL-NNN) for commit-trailer references (D-09) ---
ITEM_ID="$(next_backlog_id "$BACKLOG_DIR")"

# --- write entry ---
{
  cat <<EOF
---
title: "$TITLE"
id: $ITEM_ID
status: $STATUS
created: $DATE_ISO
updated: $DATE_ISO
origin: $ORIGIN
origin_ref: ${ORIGIN_REF:-}
priority: $PRIORITY
estimate: $ESTIMATE
blocked_by: "$BLOCKED_BY"
escalated_to: ""
commits: ""
---

# $TITLE

## Context

<!-- Why is this worth doing? What problem does it solve? Keep to 2-5 sentences. -->

## Acceptance

<!-- Optional at registration for a parked idea; required before open->doing. -->
Done means:

- <!-- concrete, verifiable criterion -->

## Notes

EOF

  if [[ "$ORIGIN" == "audit" ]]; then
    echo "- Origin: audit finding [$FINDING]"
    [[ -n "$AUDIT_RUN" ]] && echo "  - Audit run: \`.context/audits/$AUDIT_RUN/\` (path uses pre-D-02 layout if no methodology prefix)"
  fi
} > "$OUT_FILE"

ok "Backlog entry created"
printf '  %s\n' "$OUT_FILE" >&2

if [[ $NO_INDEX -eq 0 ]]; then
  regen_index "$BACKLOG_DIR"
fi

# Emit the path to stdout so callers (like /aidex-audit escalate) can capture it
printf '%s\n' "$OUT_FILE"
