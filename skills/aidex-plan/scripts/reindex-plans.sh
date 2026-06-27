#!/usr/bin/env bash
# reindex-plans.sh — regenerate .context/plans/00-index.md from each plan's
# front-matter. Mirrors the backlog 00-index.md pattern (a roll-up of state across
# all plans), but for plans: active (open/doing) grouped first, closed plans rolled
# up from _archive/.
#
# A plan is either a single file (plans/YYYY-MM-DD-<slug>.md) or a modular folder
# (plans/YYYY-MM-DD-<slug>/00-index.md holds the front-matter). The top-level
# plans/00-index.md (this file's output) is NEVER read as a plan.
#
# Usage:
#   reindex-plans.sh [--reindex]   # regenerate the index (default action)
#   reindex-plans.sh --check       # read-only: warn + exit 1 if the index is stale
#                                  #   (drifted from front-matter) or missing; never writes
#
# On success, prints the index path to stdout. Idempotent; never edits plan bodies.

set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_RESET=$'\033[0m'
else C_GREEN='' C_YELLOW='' C_RESET=''; fi
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET" >&2; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }

MODE=write
case "${1:-}" in
  -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
  --check) MODE=check ;;
  --reindex|"") ;;
  *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  pwd -P
}

ROOT="$(find_project_root)"
PLANS_DIR="$ROOT/.context/plans"
[[ -d "$PLANS_DIR" ]] || { warn "no plans directory at $PLANS_DIR"; exit 0; }

INDEX_FILE="$PLANS_DIR/00-index.md"
TODAY="$(date +%Y-%m-%d)"

# Read selected front-matter fields from a plan's fm file, tab-separated:
#   status, title, current-phase, updated, superseded_by
read_fm_fields() {
  awk '
    BEGIN { FS=": " }
    /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
    fm==1 {
      key=$1
      if (key!="status" && key!="title" && key!="current-phase" && key!="updated" && key!="superseded_by") next
      sub(/^[^:]*: */, ""); gsub(/^"|"$/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      vals[key]=$0
    }
    END {
      printf "%s\037%s\037%s\037%s\037%s",
        vals["status"], vals["title"], vals["current-phase"], vals["updated"], vals["superseded_by"]
    }
  ' "$1"
}

# Count phase files (NN-*.md, excluding 00-index.md) in a modular plan dir.
count_phases() {
  local dir="$1" n=0 f
  shopt -s nullglob
  for f in "$dir"/[0-9][0-9]-*.md; do
    [[ "$(basename "$f")" == "00-index.md" ]] && continue
    n=$((n+1))
  done
  shopt -u nullglob
  printf '%d' "$n"
}

# Resolve the fm file, link path, and phase total for one plan target.
# Sets globals: FM_FILE LINK PHASES
resolve_plan() {
  local target="$1" prefix="$2"
  if [[ -d "$target" ]]; then
    FM_FILE="$target/00-index.md"
    LINK="${prefix}$(basename "$target")/00-index.md"
    PHASES="$(count_phases "$target")"
  else
    FM_FILE="$target"
    LINK="${prefix}$(basename "$target")"
    PHASES=0
  fi
}

declare -a SEC_DOING=() SEC_OPEN=() CLOSED_EXTRA=()
active_count=0 doing_count=0

# Build the active list from single-file plans (plans/*.md, skip 00-index.md) and
# modular plans (plans/*/00-index.md). _archive/ handled separately below.
collect_active() {
  local f status title phase updated superseded line plabel
  shopt -s nullglob
  # single-file plans
  for f in "$PLANS_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "00-index.md" ]] && continue
    resolve_plan "$f" ""
    emit_active_row
  done
  # modular plans
  for f in "$PLANS_DIR"/*/00-index.md; do
    [[ -f "$f" ]] || continue
    resolve_plan "$(dirname "$f")" ""
    emit_active_row
  done
  shopt -u nullglob
}

emit_active_row() {
  local status title phase updated superseded fields plabel line
  fields="$(read_fm_fields "$FM_FILE")"
  IFS=$'\037' read -r status title phase updated superseded <<<"$fields"
  [[ -z "$title" ]] && title="(untitled)"
  # A plan hand-set to done/dropped but still in the active dir (not yet archived)
  # would otherwise vanish from the index. Surface it under Closed with a hint.
  case "$status" in
    open|doing) ;;
    done|dropped)
      CLOSED_EXTRA+=("${updated:-0000-00-00}"$'\t'"- [${title}](${LINK}) — ${status} · not archived (run close-plan.sh)${updated:+ · ${updated}}")
      return 0 ;;
    *) return 0 ;;
  esac

  if [[ "$PHASES" -gt 0 && -n "$phase" ]]; then plabel="phase ${phase}/${PHASES}"
  elif [[ -n "$phase" ]]; then plabel="phase ${phase}"
  elif [[ "$PHASES" -gt 0 ]]; then plabel="${PHASES} phases"
  else plabel=""; fi

  line="- **[${title}](${LINK})** — ${status}"
  [[ -n "$plabel" ]] && line="${line} · ${plabel}"
  [[ -n "$updated" ]] && line="${line} · updated ${updated}"

  if [[ "$status" == "doing" ]]; then
    SEC_DOING+=("$line"); doing_count=$((doing_count+1))
  else
    SEC_OPEN+=("$line"); active_count=$((active_count+1))
  fi
}

# Closed plans from _archive/, newest-closed (by updated) first.
declare -a CLOSED_SORTED=()
collect_closed() {
  local f status title phase updated superseded fields clabel cline base tmp=()
  # Seed with done/dropped plans still in the active dir (collected by collect_active).
  [[ ${#CLOSED_EXTRA[@]} -gt 0 ]] && tmp+=("${CLOSED_EXTRA[@]}")
  shopt -s nullglob
  for f in "$PLANS_DIR"/_archive/*.md "$PLANS_DIR"/_archive/*/00-index.md; do
    [[ -f "$f" ]] || continue
    if [[ "$(basename "$f")" == "00-index.md" ]]; then
      base="$(basename "$(dirname "$f")")/00-index.md"; base="_archive/$base"
    else
      base="_archive/$(basename "$f")"
    fi
    fields="$(read_fm_fields "$f")"
    IFS=$'\037' read -r status title phase updated superseded <<<"$fields"
    [[ -z "$title" ]] && title="(untitled)"
    if [[ -n "$superseded" ]]; then clabel="superseded → ${superseded}"
    else clabel="${status:-done}"; fi
    cline="- [${title}](${base}) — ${clabel}${updated:+ · ${updated}}"
    tmp+=("${updated:-0000-00-00}"$'\t'"$cline")
  done
  shopt -u nullglob
  if [[ ${#tmp[@]} -gt 0 ]]; then
    while IFS= read -r line; do CLOSED_SORTED+=("${line#*$'\t'}"); done \
      < <(printf '%s\n' "${tmp[@]}" | sort -r)
  fi
}

collect_active
collect_closed

NEW_IDX="$(mktemp)"; trap 'rm -f "$NEW_IDX"' EXIT
{
  printf '# Plans\n\n'
  printf '_Auto-generated by `aidex-plan` from front-matter. Do not edit by hand._\n\n'
  printf '**Updated:** %s\n' "$TODAY"
  printf '**Open:** %d · **Doing:** %d · **Closed:** %d\n\n' "$active_count" "$doing_count" "${#CLOSED_SORTED[@]}"

  if [[ ${#SEC_DOING[@]} -gt 0 ]]; then
    printf '## Doing\n\n'; printf '%s\n' "${SEC_DOING[@]}"; printf '\n'
  fi
  if [[ ${#SEC_OPEN[@]} -gt 0 ]]; then
    printf '## Open\n\n'; printf '%s\n' "${SEC_OPEN[@]}"; printf '\n'
  fi
  if [[ ${#SEC_DOING[@]} -eq 0 && ${#SEC_OPEN[@]} -eq 0 ]]; then
    printf '_No active plans._\n\n'
  fi

  printf -- '---\n\n'
  if [[ ${#CLOSED_SORTED[@]} -gt 0 ]]; then
    printf '## Closed\n\n'
    printf '_Closed plans (full bodies in [`_archive/`](_archive/)):_\n\n'
    printf '%s\n' "${CLOSED_SORTED[@]}"
    printf '\n'
  else
    printf '_Archived plans: see [`_archive/`](_archive/)._\n'
  fi
} > "$NEW_IDX"

# Compare ignoring the volatile "Updated:" timestamp line (a date bump is not drift).
norm() { sed 's/^\*\*Updated:\*\*.*/**Updated:**/' "$1"; }

if [[ "$MODE" == "check" ]]; then
  if [[ ! -f "$INDEX_FILE" ]]; then
    warn "plans/00-index.md missing — run reindex-plans.sh"
    exit 1
  fi
  if ! diff -q <(norm "$INDEX_FILE") <(norm "$NEW_IDX") >/dev/null; then
    warn "plans/00-index.md is stale (drifted from plan front-matter) — run reindex-plans.sh"
    exit 1
  fi
  exit 0
fi

mv "$NEW_IDX" "$INDEX_FILE"
trap - EXIT
ok "Regenerated $INDEX_FILE"
printf '%s\n' "$INDEX_FILE"
