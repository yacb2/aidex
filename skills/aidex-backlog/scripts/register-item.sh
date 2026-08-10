#!/usr/bin/env bash
# register-item.sh — create a backlog entry in .context/backlog/.
#
# Usage (non-interactive):
#   register-item.sh --origin <manual|audit|issue|request|communication> [options]
#
# Options:
#   --title "<title>"              title for the entry (required for non-interactive)
#   --finding <id>                 (when --origin audit) finding ID
#   --audit-run <slug>             (when --origin audit) run folder name
#   --issue <id>                   (when --origin issue) issue ID
#   --request <file>               (when --origin request) request file path
#   --communication <folder>       (when --origin communication) the communication folder
#                                  (received|sent|meetings)/<YYYY-MM-DD>-<slug>
#   --priority <P0|P1|P2|P3>       default: P2 (code only — see references/01-backlog-conventions.md)
#   --type <bug|improvement|task|idea>  work kind (default: task) — a facet, one queue
#   --blocked-by "<who/what>"      optional Blocked modifier; priority is kept, item listed under Blocked
#   --estimate <XS|S|M|L|XL>       default: M
#   --status <open|doing|done|dropped>  default: open
#   --slug <kebab-case>            override auto-generated slug
#   --escalate-to <target-repo>    register a linked counterpart in another repo's backlog
#                                  (source gets escalated_to, target gets origin — see
#                                  --source-id to stamp an existing item instead of a new stub)
#   --source-id <BL-id>            (with --escalate-to) stamp this existing item as the source
#   --list                         list open entries grouped by priority (P0 → P3 + Blocked)
#   --reindex                      regenerate 00-index.md from front-matter, then exit
#                                  (exits 1 if any id is duplicated or is not a BL-NNN shape)
#   --check-ids                    run only that id guard, read-only (no index write); exit 1 on any problem
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

# Escape a value for a double-quoted YAML scalar.
#
# Without this, `--title` and `--blocked-by` land raw inside `key: "$VALUE"`. A title
# containing a newline followed by `---` terminates the front-matter early: every key
# after it (id included) becomes body prose, the id reader returns empty, and the id is
# re-minted for the next item. A double quote closes the scalar and lets a second key be
# injected, which a last-write-wins parser honours. Found 2026-08-10 by aidex-review.
yaml_escape() {
  printf '%s' "$1" \
    | tr '\n\r\t' '   ' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Convert a title to a kebab-case slug (3–6 meaningful words). The newline strip is
# load-bearing: sed is line-oriented, so without it a multi-line title produced a
# filename containing literal newlines.
title_to_slug() {
  printf '%s' "$1" \
    | tr '\n\r' '  ' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' \
    | cut -c1-60 \
    | sed -E 's/-+$//'
}

# Emit every assigned id as "<number><TAB><path>", one per line. Scans active +
# _archive + _deferred so no item's id is ever reused — ids stay stable for
# commit-trailer refs (D-09).
scan_backlog_ids() {
  local dir="$1" n f
  shopt -s nullglob
  for f in "$dir"/*.md "$dir"/_archive/*.md "$dir"/_deferred/*.md; do
    [[ -f "$f" ]] || continue
    n="$(awk '/^---[[:space:]]*$/{c++; if(c==2) exit} c==1 && $1 ~ /^id:/ {v=$2; gsub(/[^0-9]/,"",v); print v; exit}' "$f")"
    [[ -n "$n" ]] && printf '%s\t%s\n' "$((10#$n))" "$f"
  done
  shopt -u nullglob
}

# Compute the next sequential backlog id (BL-NNN) — one above the highest assigned.
# Only ids already in the sequence's own shape count toward the max: a hand-authored
# `BL-20260610` would otherwise push the sequence into the millions, and every id
# minted after it would be nonconforming too. Legacy ids sit in a different
# namespace, so skipping them can never reuse one.
#
# The window is 3-to-5 digits, not exactly 3. `printf 'BL-%03d'` is a MINIMUM width, so
# at max=999 it mints BL-1000 — which an exactly-three-digit filter then rejects, leaving
# max pinned at 999 and BL-1000 re-minted for every later item, forever. Five digits keeps
# the runway to BL-99999 while still skipping a date-shaped legacy id (BL-20260610, eight
# digits), which is the case this filter exists for. Found 2026-08-10 by aidex-review.
next_backlog_id() {
  local dir="$1" max=0 rawid n
  while IFS=$'\t' read -r rawid _; do
    [[ "$rawid" =~ ^BL-([0-9]{3,5})$ ]] || continue
    n="$((10#${BASH_REMATCH[1]}))"
    (( n > max )) && max=$n
  done < <(scan_backlog_raw_ids "$dir")
  printf 'BL-%03d' $((max+1))
}

# Emit every assigned id VERBATIM as "<raw-id><TAB><path>", one per line. Unlike
# scan_backlog_ids (which strips to the numeric part for max/next), this keeps the
# id exactly as written so the shape can be checked.
scan_backlog_raw_ids() {
  local dir="$1" v f
  shopt -s nullglob
  for f in "$dir"/*.md "$dir"/_archive/*.md "$dir"/_deferred/*.md; do
    [[ -f "$f" ]] || continue
    v="$(awk '/^---[[:space:]]*$/{c++; if(c==2) exit} c==1 && $1 ~ /^id:/ {print $2; exit}' "$f")"
    [[ -n "$v" ]] && printf '%s\t%s\n' "$v" "$f"
  done
  shopt -u nullglob
}

# Report id integrity problems. Two failure modes, both from hand-authored entries
# (this script never produces either — next_backlog_id always mints BL-NNN above
# the highest it can see):
#   1. Duplicate id — two pairs sat undetected in echo_lab for weeks (BL-186 and
#      BL-193, found 2026-07-22).
#   2. Nonconforming id — an id not matching ^BL-[0-9]{3}$ (ns_backoffice's
#      hand-authored `BL-20260610` makes next_backlog_id mint `BL-20260611`,
#      inflating the sequence). The digit-strip in scan_backlog_ids hides this
#      from the duplicate check, so it needs its own raw-shape pass.
# Returns 1 when any problem exists, so --reindex can fail the run.
report_duplicate_ids() {
  local dir="$1" ids dup=0 n files rawid f
  ids="$(scan_backlog_ids "$dir")"
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    files="$(printf '%s\n' "$ids" | awk -F'\t' -v i="$n" '$1==i { printf "%s ", $2 }')"
    warn "$(printf 'duplicate id BL-%03d → %s' "$n" "${files% }")"
    dup=1
  done < <(printf '%s\n' "$ids" | cut -f1 | sort -n | uniq -d)
  while IFS=$'\t' read -r rawid f; do
    [[ -n "$rawid" ]] || continue
    # Same 3-to-5 window as next_backlog_id. Kept in lockstep deliberately: with an
    # exactly-three-digit test here, the BL-1000 that next_backlog_id legitimately mints
    # past BL-999 would be minted correctly and then reported as nonconforming.
    if [[ ! "$rawid" =~ ^BL-[0-9]{3,5}$ ]]; then
      warn "$(printf 'nonconforming id %s → %s (expected BL-NNN)' "$rawid" "$f")"
      dup=1
    fi
  done < <(scan_backlog_raw_ids "$dir")
  return $dup
}

# --- cross-project routing helpers (BL-035 handshake) ---

# Find the active/deferred/archived entry carrying the given BL id; echo its path.
resolve_source_by_id() {
  local dir="$1" want="$2" f id
  shopt -s nullglob
  for f in "$dir"/*.md "$dir"/_deferred/*.md "$dir"/_archive/*.md; do
    [[ -f "$f" ]] || continue
    id="$(awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$f")"
    if [[ "$id" == "$want" ]]; then printf '%s\n' "$f"; shopt -u nullglob; return 0; fi
  done
  shopt -u nullglob
  return 1
}

# Set an entry's escalated_to (and bump updated) in place, inserting the key when the
# entry does not carry it yet.
#
# The insert branch is the fix for a silent no-op: with only a rewrite branch, stamping a
# hand-authored item that never had an `escalated_to:` key wrote nothing at all while the
# caller still printed "Stamped source ... -> escalated_to: ...". The result was a one-way
# handshake — the counterpart pointed back, the source had no forward link. The sibling
# close-item.sh already used the insert-if-missing idiom. Found 2026-08-10 by aidex-review.
stamp_escalated_to() {
  local f="$1" ref="$2" today
  today="$(date +%Y-%m-%d)"
  awk -v ref="$ref" -v today="$today" '
    BEGIN { d=0; seen=0 }
    /^---[[:space:]]*$/ {
      d++
      if (d==2 && !seen) print "escalated_to: \"" ref "\""
      print; next
    }
    d==1 && /^escalated_to:/ { print "escalated_to: \"" ref "\""; seen=1; next }
    d==1 && /^updated:/      { print "updated: " today; next }
    { print }
  ' "$f" > "$f.tmp" || die "could not rewrite $f"
  [[ -s "$f.tmp" ]] || die "stamping $f produced an empty file"
  mv "$f.tmp" "$f"
}

# The ONE entry template. Both writers render through this: they were hand-maintained
# copies that had already drifted in three flags, in empty-slug handling, and in the
# Acceptance comment. Found 2026-08-10 by aidex-review.
#
# The two differences between the call sites are real, so they are parameters, not
# branches: `context` is the unfilled template prompt on the normal path and a written
# note on the escalate path, and `notes` carries the audit provenance lines that only
# the normal path has.
#
# Args: out id title status origin origin_ref priority type estimate blocked_by
#       escalated_to context notes
emit_backlog_entry() {
  local out="$1" id="$2" title="$3" status="$4" origin="$5" origin_ref="$6" \
        priority="$7" type="$8" estimate="$9" blocked_by="${10}" escalated_to="${11}" \
        context="${12}" notes="${13}"
  local date_iso esc_title esc_blocked body_title
  date_iso="$(date +%Y-%m-%d)"
  esc_title="$(yaml_escape "$title")"
  esc_blocked="$(yaml_escape "$blocked_by")"
  # The H1 takes the flattened title, never the YAML-escaped one. Both copies used the
  # escaped form in both places, so `a "quoted" word` rendered as `a \"quoted\" word` in
  # the markdown body. Only newlines need flattening here; a quote is legal markdown.
  body_title="$(printf '%s' "$title" | tr '\n\r\t' '   ')"
  # Deliberately NO `mkdir -p "$(dirname "$out")"`: the backlog directory is the caller's
  # to create, and creating $out's parent here would silently accept a `--slug` containing
  # a slash, filing the item in a subdirectory where the index glob and the id scanner
  # cannot see it — so its id would later be re-minted. The failed write is the correct
  # outcome for that input.
  {
    cat <<EOF
---
title: "$esc_title"
id: $id
status: $status
created: $date_iso
updated: $date_iso
origin: $origin
origin_ref: ${origin_ref:-}
priority: $priority
type: $type
estimate: $estimate
blocked_by: "$esc_blocked"
escalated_to: "$escalated_to"
commits: ""
---

# $body_title

## Context

$context

## Acceptance

<!-- Optional at registration for a parked idea; required before open->doing. -->
Done means:

- <!-- concrete, verifiable criterion -->

## Notes

EOF
    # `if`, never `[[ -n "$notes" ]] && printf`: as the last command of this group the
    # && form returns 1 on an empty value, the group inherits it, and the `|| die` below
    # then reports "could not write" on a file that was written correctly. That was a
    # live defect on the audit path — `--origin audit` with no `--audit-run` exited 2
    # having written the item, spending its id and returning no path.
    if [[ -n "$notes" ]]; then printf '%s\n' "$notes"; fi
  } > "$out" || die "could not write $out"
  # `set -e` does NOT abort on a redirect failure of a compound command, so this guard
  # is what stops a failed write from reporting success.
  [[ -s "$out" ]] || die "wrote nothing to $out"
}

# Write a compact backlog entry (used by --escalate-to for both the source stub
# and the cross-repo counterpart). Echoes the created path on stdout.
emit_backlog_stub() {
  local dir="$1" id="$2" title="$3" origin="$4" origin_ref="$5" priority="$6" type="$7" escalated_to="$8" note="$9"
  # Carried through rather than hardcoded: --estimate/--status/--blocked-by used to pass
  # their validation gates and then be silently overwritten here, so a declared-blocked
  # P0 item landed in the active queue as `open · M`. Found 2026-08-10 by aidex-review.
  local estimate="${10:-M}" status="${11:-open}" blocked_by="${12:-}"
  local date_iso slug id_seg out
  date_iso="$(date +%Y-%m-%d)"
  slug="$(title_to_slug "$title")"; [[ -n "$slug" ]] || slug="item"
  id_seg="$(printf '%s' "$id" | tr 'A-Z' 'a-z')"
  mkdir -p "$dir" || die "could not create $dir"
  out="$dir/$date_iso-$id_seg-$slug.md"
  emit_backlog_entry "$out" "$id" "$title" "$status" "$origin" "${origin_ref:-}" \
    "$priority" "$type" "$estimate" "$blocked_by" "$escalated_to" "$note" ""
  printf '%s\n' "$out"
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
COMMUNICATION=""
PRIORITY=""
TYPE=""
BLOCKED_BY=""
ESTIMATE="M"
STATUS="open"
SLUG_OVERRIDE=""
ESCALATE_TO=""
SOURCE_ID=""
LIST_ONLY=0
REINDEX_ONLY=0
CHECK_IDS_ONLY=0
NO_INDEX=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --origin)      ORIGIN="$2"; shift 2 ;;
    --title)       TITLE="$2"; shift 2 ;;
    --finding)     FINDING="$2"; shift 2 ;;
    --audit-run)   AUDIT_RUN="$2"; shift 2 ;;
    --issue)       ISSUE="$2"; shift 2 ;;
    --request)     REQUEST="$2"; shift 2 ;;
    --communication) COMMUNICATION="$2"; shift 2 ;;
    --priority)    PRIORITY="$2"; shift 2 ;;
    --type)        TYPE="$2"; shift 2 ;;
    --blocked-by)  BLOCKED_BY="$2"; shift 2 ;;
    --estimate)    ESTIMATE="$2"; shift 2 ;;
    --status)      STATUS="$2"; shift 2 ;;
    --slug)        SLUG_OVERRIDE="$2"; shift 2 ;;
    --escalate-to) ESCALATE_TO="$2"; shift 2 ;;
    --source-id)   SOURCE_ID="$2"; shift 2 ;;
    --list)        LIST_ONLY=1; shift ;;
    --reindex)     REINDEX_ONLY=1; shift ;;
    --check-ids)   CHECK_IDS_ONLY=1; shift ;;
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

  # Single awk pass per file: emit status, title, priority, estimate, blocked_by, id tab-separated.
  read_fm_fields() {
    awk '
      BEGIN { FS=": " }
      /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
      fm==1 {
        key=$1
        if (key!="status" && key!="title" && key!="priority" && key!="estimate" && key!="blocked_by" && key!="id") next
        sub(/^[^:]*: */, "")
        gsub(/^"|"$/, "")
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        vals[key]=$0
      }
      END {
        printf "%s\037%s\037%s\037%s\037%s\037%s",
          vals["status"], vals["title"], vals["priority"], vals["estimate"], vals["blocked_by"], vals["id"]
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
        printf "%s\037%s\037%s\037%s\037%s\037%s",
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
        printf "%s\037%s\037%s\037%s\037%s",
          vals["title"], vals["id"], vals["priority"], vals["updated"], vals["blocked_by"]
      }
    ' "$1"
  }

  local -a SEC_P0=() SEC_P1=() SEC_P2=() SEC_P3=() SEC_BLOCKED=()
  local active_count=0 doing_count=0

  local f base title status priority estimate blocked_by id idp line fields
  for f in "$dir"/*.md; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "00-index.md" ]] && continue

    fields="$(read_fm_fields "$f")"
    IFS=$'\037' read -r status title priority estimate blocked_by id <<<"$fields"
    [[ -z "$title" ]] && title="(untitled)"
    # The ID is the key every conversation uses; surface it, but degrade to the plain
    # title line when it is missing or malformed (BL-127).
    idp=""
    [[ -n "$id" ]] && idp="**${id}** · "

    case "$status" in
      open|doing) ;;
      *) continue ;;
    esac

    if [[ -n "$blocked_by" ]]; then
      line="- ${idp}**[${title}](${base})** — ${status} · ${priority:-P?} · blocked_by: \"${blocked_by}\""
      SEC_BLOCKED+=("$line")
      continue
    fi

    [[ "$status" == "doing" ]] && doing_count=$((doing_count+1))
    [[ "$status" == "open" ]]  && active_count=$((active_count+1))

    line="- ${idp}**[${title}](${base})** — ${status} · ${estimate:-?}"
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
      IFS=$'\037' read -r cstatus ctitle cid cupdated csuperseded cescalated <<<"$fields"
      [[ -z "$ctitle" ]] && ctitle="(untitled)"
      if [[ -n "$csuperseded" ]]; then clabel="superseded → ${csuperseded}"
      elif [[ -n "$cescalated" ]]; then clabel="${cstatus:-done} → ${cescalated}"
      else clabel="${cstatus:-done}"; fi
      cline="- ${cid:+**${cid}** · }[${ctitle}](_archive/${cbase}) — ${clabel}${cupdated:+ · ${cupdated}}"
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
      IFS=$'\037' read -r dtitle did dpriority dupdated dblocked <<<"$fields"
      [[ -z "$dtitle" ]] && dtitle="(untitled)"
      dline="- ${did:+**${did}** · }[${dtitle}](_deferred/${dbase}) — ${dpriority:-P?} · blocked_by: \"${dblocked}\"${dupdated:+ · ${dupdated}}"
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

  # Last statement: its status becomes regen_index's, so callers can act on it.
  report_duplicate_ids "$dir"
}

# --- handle --check-ids (the reindex id guard, without writing the index) ---
# `triage` needs the duplicate/nonconforming verdict while staying read-only, and
# --reindex cannot give it that: it regenerates 00-index.md as a side effect.
if [[ $CHECK_IDS_ONLY -eq 1 ]]; then
  report_duplicate_ids "$BACKLOG_DIR" || exit 1
  exit 0
fi

# --- handle --reindex ---
if [[ $REINDEX_ONLY -eq 1 ]]; then
  regen_index "$BACKLOG_DIR" || exit 1
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
    #
    # The front-matter boundary is load-bearing, and this was the one reader missing it
    # — read_fm_fields, read_closed_fields and read_deferred_fields all track it. Without
    # it `$1 == key` matches body prose too. A generated item is immune (it always carries
    # every key, and the first match wins), so only a hand-authored item with the key
    # absent from its header reaches the defect: a line in the body starting `blocked_by:`
    # then moved the item out of the active queue into Blocked, from prose alone.
    # Found 2026-08-10 by aidex-review.
    awk -F': ' -v key="$1" '
      /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
      fm==1 && $1 == key {
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

  # `${arr[@]+"${arr[@]}"}` and NOT `"${arr[@]:-}"`: the latter expands an empty array
  # to one empty-string argument, so print_section saw ${#items[@]} == 1, its own
  # empty guard never fired, and a list with a single P2 item printed six headings —
  # five of them over nothing. This form expands to zero arguments while still being
  # safe under `set -u` on bash 3.2. Found 2026-08-10 by aidex-review.
  printf '%sOpen backlog entries (grouped by priority):%s\n' "$C_BOLD" "$C_RESET"
  print_section "P0 — Critical"   "$C_RED"    ${P0[@]+"${P0[@]}"}
  print_section "P1 — High"       "$C_YELLOW" ${P1[@]+"${P1[@]}"}
  print_section "P2 — Medium"     "$C_BLUE"   ${P2[@]+"${P2[@]}"}
  print_section "P3 — Low"        "$C_DIM"    ${P3[@]+"${P3[@]}"}
  print_section "Blocked (third-party)" "$C_DIM" ${BLOCKED[@]+"${BLOCKED[@]}"}
  print_section "Unclassified (legacy — preview: migrate-priorities.sh, write: --apply)" "$C_RED" ${PUNK[@]+"${PUNK[@]}"}

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
  manual|audit|issue|request|communication) ;;
  *) die "invalid --origin: $ORIGIN (must be manual, audit, issue, request, or communication)" ;;
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

# --- type facet (one queue, a work-kind facet — ADR 2026-07-23) ---
if [[ -z "$TYPE" && -t 0 ]]; then
  printf '\n%sType facet%s (bug fix · improvement · task · idea):\n' "$C_BOLD" "$C_RESET" >&2
  printf 'Type [bug/improvement/task/idea] (default: task): ' >&2
  read -r TYPE
  TYPE="${TYPE:-task}"
fi
TYPE="${TYPE:-task}"
TYPE="$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')"
case "$TYPE" in
  bug|improvement|task|idea) ;;
  *) die "invalid type: '$TYPE' (must be bug, improvement, task, or idea — see references/01-backlog-conventions.md)" ;;
esac

case "$ESTIMATE" in XS|S|M|L|XL) ;; *) die "invalid estimate: $ESTIMATE" ;; esac
case "$STATUS"   in open|doing|done|dropped) ;; *) die "invalid status: $STATUS" ;; esac

# --- derive origin_ref ---
ORIGIN_REF=""
case "$ORIGIN" in
  audit)
    [[ -n "$FINDING" ]] || die "--finding <id> is required when --origin audit"
    if [[ -n "$AUDIT_RUN" ]]; then
      # D-02 groups runs by methodology: audits/<methodology>/<run>/. Emitting
      # audit/<run>/<finding> produces a ref that can never resolve — validate.py
      # strips the finding id and looks for audits/<run>/, which does not exist
      # under the grouped layout. Resolve the methodology off disk; fall back to
      # the flat form only for genuinely ungrouped (pre-D-02) runs.
      AUDIT_REL="$AUDIT_RUN"
      if [[ -d "$ROOT/.context/audits" ]]; then
        for _m in "$ROOT"/.context/audits/*/"$AUDIT_RUN"; do
          [[ -d "$_m" ]] || continue
          AUDIT_REL="$(basename "$(dirname "$_m")")/$AUDIT_RUN"
          break
        done
      fi
      ORIGIN_REF="audit/$AUDIT_REL/$FINDING"
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
    # --request takes a path for convenience, but a cross-ref is a `<type>/<filename>`
    # marker, never a filesystem path (D-03, BL-055): a stored path breaks the moment
    # the item is read from anywhere but the directory it was registered from.
    REQUEST_FILE="$(basename "$REQUEST")"
    ORIGIN_REF="request/$REQUEST_FILE"
    if [[ ! -e "$ROOT/.context/requests/$REQUEST_FILE" \
       && ! -e "$ROOT/.context/requests/_archive/$REQUEST_FILE" ]]; then
      warn "warning: origin_ref $ORIGIN_REF resolves to no file under .context/requests/"
    fi
    ;;
  communication)
    # A meeting produces action items; this is the hop that turns one into tracked work
    # without losing where it came from. Same marker discipline as request: the ref is
    # `communication/<YYYY-MM-DD>-<slug>`, the folder name, never a path (D-03).
    [[ -n "$COMMUNICATION" ]] || die "--communication <folder> is required when --origin communication"
    COMM_DIR="$(basename "${COMMUNICATION%/}")"
    [[ "$COMM_DIR" == "body.md" ]] && COMM_DIR="$(basename "$(dirname "${COMMUNICATION%/}")")"
    ORIGIN_REF="communication/$COMM_DIR"
    comm_found=0
    for _kind in received sent meetings; do
      [[ -e "$ROOT/.context/communications/$_kind/$COMM_DIR" ]] && comm_found=1
    done
    [[ $comm_found -eq 1 ]] \
      || warn "warning: origin_ref $ORIGIN_REF resolves to no folder under .context/communications/{received,sent,meetings}/"
    ;;
esac

# --- handle --escalate-to (BL-035 cross-project routing handshake) ---
# Register a linked pair: the discovering repo carries escalated_to: <target>/BL-NNN,
# the target repo carries origin: <source>/BL-MMM. Both indexes are regenerated.
# A cross-repo escalated_to (target prefix is a repo, not an artifact type) is an
# EXTERNAL ref: validate.py accepts <repo>/BL-NNN on format and skips the existence
# check, since the target is not on this filesystem tree (BL-070, 00-global §3.1).
if [[ -n "$ESCALATE_TO" ]]; then
  TARGET_ROOT="$ESCALATE_TO"
  [[ -d "$TARGET_ROOT" ]]           || die "--escalate-to: target repo not found: $TARGET_ROOT"
  [[ -d "$TARGET_ROOT/.context" ]]  || die "--escalate-to: target has no .context/: $TARGET_ROOT"
  TARGET_BACKLOG="$TARGET_ROOT/.context/backlog"
  mkdir -p "$TARGET_BACKLOG"
  SRC_NAME="$(basename "$ROOT")"
  TGT_NAME="$(basename "$(cd "$TARGET_ROOT" && pwd -P)")"
  [[ "$SRC_NAME" != "$TGT_NAME" ]] || die "--escalate-to: source and target are the same repo ($SRC_NAME)"
  TARGET_ID="$(next_backlog_id "$TARGET_BACKLOG")"

  # SOURCE side: stamp an existing item, or register a fresh stub.
  if [[ -n "$SOURCE_ID" ]]; then
    SRC_FILE="$(resolve_source_by_id "$BACKLOG_DIR" "$SOURCE_ID")" \
      || die "--source-id: no item with id $SOURCE_ID in $BACKLOG_DIR"
    stamp_escalated_to "$SRC_FILE" "$TGT_NAME/$TARGET_ID"
    SRC_REF="$SOURCE_ID"
    ok "Stamped source $SOURCE_ID → escalated_to: $TGT_NAME/$TARGET_ID"
  else
    SRC_ID="$(next_backlog_id "$BACKLOG_DIR")"
    SRC_FILE="$(emit_backlog_stub "$BACKLOG_DIR" "$SRC_ID" "$TITLE" "$ORIGIN" "$ORIGIN_REF" \
      "$PRIORITY" "$TYPE" "$TGT_NAME/$TARGET_ID" \
      "Escalated to $TGT_NAME — work is tracked at $TGT_NAME/$TARGET_ID." \
      "$ESTIMATE" "$STATUS" "$BLOCKED_BY")"
    SRC_REF="$SRC_ID"
    ok "Registered source stub $SRC_REF (escalated_to: $TGT_NAME/$TARGET_ID)"
  fi
  printf '  %s\n' "$SRC_FILE" >&2

  # TARGET side: the counterpart carries the cross-repo origin (origin is not a
  # validate.py cross-ref field, so this stays clean in the target's validate run).
  TGT_FILE="$(emit_backlog_stub "$TARGET_BACKLOG" "$TARGET_ID" "$TITLE" "$SRC_NAME/$SRC_REF" "" \
    "$PRIORITY" "$TYPE" "" \
    "Discovered in $SRC_NAME (origin: $SRC_NAME/$SRC_REF); routed here for execution.")"
  ok "Registered counterpart $TARGET_ID in $TGT_NAME (origin: $SRC_NAME/$SRC_REF)"
  printf '  %s\n' "$TGT_FILE" >&2

  # Regenerate both indexes; a pre-existing dup/nonconforming id must not abort.
  regen_index "$BACKLOG_DIR" >/dev/null 2>&1 || true
  regen_index "$TARGET_BACKLOG" >/dev/null 2>&1 || true

  printf '%s\n' "$SRC_FILE"
  printf '%s\n' "$TGT_FILE"
  exit 0
fi

# --- compute slug ---
if [[ -n "$SLUG_OVERRIDE" ]]; then
  SLUG="$SLUG_OVERRIDE"
else
  SLUG="$(title_to_slug "$TITLE")"
fi
[[ -n "$SLUG" ]] || die "could not derive slug from title"

DATE_ISO="$(date +%Y-%m-%d)"
mkdir -p "$BACKLOG_DIR"

# --- assign stable short id (BL-NNN) for commit-trailer references (D-09) ---
# Minted before the filename because the name carries it. No clobber guard is
# needed: the id is unique across active + _archive + _deferred by construction.
ITEM_ID="$(next_backlog_id "$BACKLOG_DIR")"
OUT_FILE="$BACKLOG_DIR/$DATE_ISO-$(printf '%s' "$ITEM_ID" | tr 'A-Z' 'a-z')-$SLUG.md"

# --- audit provenance, appended under ## Notes ---
NOTES_BLOCK=""
if [[ "$ORIGIN" == "audit" ]]; then
  NOTES_BLOCK="- Origin: audit finding [$FINDING]"
  # $AUDIT_REL, not raw $AUDIT_RUN: the methodology was already resolved off disk when
  # origin_ref was derived, and re-deriving here dropped it — emitting
  # `.context/audits/<run>/`, a path that cannot exist under the D-02 grouped layout.
  # The ref was correct and the human-readable path beside it pointed nowhere. The
  # fallback keeps genuinely ungrouped pre-D-02 runs working.
  # Found 2026-08-10 by aidex-review.
  if [[ -n "$AUDIT_RUN" ]]; then
    NOTES_BLOCK="$NOTES_BLOCK
  - Audit run: \`.context/audits/${AUDIT_REL:-$AUDIT_RUN}/\` (path uses pre-D-02 layout if no methodology prefix)"
  fi
fi

# --- write entry (through the one template — see emit_backlog_entry) ---
emit_backlog_entry "$OUT_FILE" "$ITEM_ID" "$TITLE" "$STATUS" "$ORIGIN" "${ORIGIN_REF:-}" \
  "$PRIORITY" "$TYPE" "$ESTIMATE" "$BLOCKED_BY" "" \
  "<!-- Why is this worth doing? What problem does it solve? Keep to 2-5 sentences. -->" \
  "$NOTES_BLOCK"

ok "Backlog entry created"
printf '  %s\n' "$OUT_FILE" >&2

if [[ $NO_INDEX -eq 0 ]]; then
  # A pre-existing duplicate must not fail a registration — the entry is already
  # written, and aborting here would only lose the caller's path on stdout.
  regen_index "$BACKLOG_DIR" || true
fi

# Emit the path to stdout so callers (like /aidex-audit escalate) can capture it
printf '%s\n' "$OUT_FILE"
