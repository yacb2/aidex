#!/usr/bin/env bash
# reindex-audits.sh — regenerate .context/audits/00-index.md: a roll-up of audit
# RUNS (not findings). Complements 00-inventory.md, which is the finding-level
# board; this index is the run-level state ("which runs exist, open/closed, how
# many findings each").
#
# Unlike the backlog/plans indexes (pure front-matter scans), run state is split:
# each run's index.md carries type/status/dates, while the open/total finding
# counts are derived from 00-inventory.md (the `Audit Runs` column, field 10, and
# `Status`, field 6).
#
# Usage:
#   reindex-audits.sh [--reindex]   # regenerate the index (default action)
#   reindex-audits.sh --check       # read-only: warn + exit 1 if the index is stale
#                                   #   (drifted from run state) or missing; never writes
#
# On success, prints the index path to stdout. Idempotent; never edits findings.
#
# Known limitation: finding counts for runs in a per-methodology `_archive/`
# (e.g. audits/<meth>/_archive/<run>/) are best-effort — nearest_inventory walks
# up one level only, so a count may read 0 when the findings live in the
# methodology inventory or a per-run INVENTORY.md. The run is still surfaced with
# its identity and status intact; only the closed-run count is understated.

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

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# aidex-conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

ROOT="$(find_project_root)"
AUDITS_DIR="$ROOT/.context/audits"
[[ -d "$AUDITS_DIR" ]] || { warn "no audits directory at $AUDITS_DIR"; exit 0; }

INDEX_FILE="$AUDITS_DIR/00-index.md"
TODAY="$(date +%Y-%m-%d)"

INVENTORY=""
[[ -f "$AUDITS_DIR/00-inventory.md" ]] && INVENTORY="$AUDITS_DIR/00-inventory.md"
[[ -z "$INVENTORY" && -f "$AUDITS_DIR/INVENTORY.md" ]] && INVENTORY="$AUDITS_DIR/INVENTORY.md"

# Read run index.md front-matter, \037-separated: status, title, methodology, created, updated.
# `methodology` falls back to legacy `type:` when absent.
read_run_fm() {
  awk '
    BEGIN { FS=": " }
    /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
    fm==1 {
      key=$1
      if (key!="status" && key!="title" && key!="methodology" && key!="type" && key!="created" && key!="updated") next
      sub(/^[^:]*: */, ""); gsub(/^"|"$/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      vals[key]=$0
    }
    END {
      meth = vals["methodology"]; if (meth=="") meth = vals["type"]
      printf "%s\037%s\037%s\037%s\037%s",
        vals["status"], vals["title"], meth, vals["created"], vals["updated"]
    }
  ' "$1"
}

# A run index is index.md or 00-index.md inside a run folder. Prints the filename
# (not full path), or empty if the dir holds neither.
run_index_name() {
  local d="$1"
  [[ -f "$d/index.md" ]] && { printf 'index.md'; return; }
  [[ -f "$d/00-index.md" ]] && { printf '00-index.md'; return; }
  printf ''
}

# Nearest governing inventory for a run dir: its parent's 00-inventory.md (the
# per-methodology layout) else the audits-root inventory. Prints path or empty.
nearest_inventory() {
  local rundir="$1" parent; parent="$(dirname "$rundir")"
  [[ -f "$parent/00-inventory.md" ]] && { printf '%s' "$parent/00-inventory.md"; return; }
  [[ -f "$parent/INVENTORY.md" ]]    && { printf '%s' "$parent/INVENTORY.md"; return; }
  printf '%s' "$INVENTORY"
}

# Does the dir contain any .md file (i.e. looks like audit work, not pure assets)?
has_md() {
  local f
  for f in "$1"/*.md; do [[ -f "$f" ]] && return 0; done
  return 1
}

# Count "<open>\t<total>" findings attributed to a run slug from a given inventory.
# A finding belongs to the run when its `Audit Runs` cell (field 10) contains the
# slug. "open" = status not in the resolved set (same set as close-audit.sh).
# Skips HTML comment example rows. Prints "?\t?" if no inventory.
run_counts() {
  local slug="$1" inv="$2"
  [[ -n "$inv" ]] || { printf '?\t?'; return 0; }
  awk -F'|' -v run="$slug" '
    BEGIN { in_comment=0; open=0; total=0;
            resolved=" closed done escalated fixed dropped wontfix " }
    {
      line=$0
      if (index(line,"<!--")>0) in_comment=1
      if (in_comment) { if (index(line,"-->")>0) in_comment=0; next }
      if (line !~ /^\|/) next
      # Audit Runs is column 7 of 9 (NF==11) since BL-057, column 9 of 11 (NF==13)
      # on older boards. Reading $10 on a 9-column board reads Escalated To, so every
      # run count silently comes out zero.
      id=$2; status=$6; runs=(NF >= 13 ? $10 : $8)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",id)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",status)
      if (id=="" || id=="ID" || id=="—") next
      if (status !~ /open|doing|triaged|escalated|in-progress|closed|dropped|fixed|wontfix|done/) next
      if (index(runs, run)==0) next
      total++
      if (index(resolved, " " status " ")==0) open++
    }
    END { printf "%d\t%d", open, total }
  ' "$inv"
}

declare -a ACTIVE=() ARCHIVED=() UNREC=()
active_n=0 archived_n=0

# Emit one run row. rundir = the run folder; rel = its path relative to audits/.
emit_run() {
  local rundir="$1" rel="$2" arr_name="$3"
  local idxname slug status title methodology created updated fields counts open total link meta line inv
  idxname="$(run_index_name "$rundir")"; [[ -n "$idxname" ]] || return 0
  slug="$(basename "$rundir")"
  fields="$(read_run_fm "$rundir/$idxname")"
  IFS=$'\037' read -r status title methodology created updated <<<"$fields"
  [[ -z "$title" ]] && title="$slug"
  # methodology falls back to the parent methodology-folder name (nested layout)
  if [[ -z "$methodology" ]]; then
    local pn; pn="$(basename "$(dirname "$rundir")")"
    [[ "$pn" != "audits" && "$pn" != "_archive" ]] && methodology="$pn"
  fi
  inv="$(nearest_inventory "$rundir")"
  counts="$(run_counts "$slug" "$inv")"
  IFS=$'\t' read -r open total <<<"$counts"
  link="${rel}/${idxname}"

  meta="${methodology:-?} · ${status:-?}"
  if [[ "$total" == "?" ]]; then meta="${meta} · findings ?"
  else meta="${meta} · ${open} open / ${total} findings"; fi
  [[ -n "$created" ]] && meta="${meta} · ${created}"

  line="- **[${title}](${link})** — ${meta}"
  if [[ "$arr_name" == "ACTIVE" ]]; then
    ACTIVE+=("${created:-0000-00-00}"$'\t'"$line"); active_n=$((active_n+1))
  else
    ARCHIVED+=("${created:-0000-00-00}"$'\t'"$line"); archived_n=$((archived_n+1))
  fi
}

# Classify and walk one directory level. Handles flat runs, per-methodology
# containers (recurse one level), and ad-hoc dirs (surfaced, not dropped).
shopt -s nullglob
for d in "$AUDITS_DIR"/*/; do
  d="${d%/}"; name="$(basename "$d")"
  [[ "$name" == "_archive" || "$name" == "methodology" ]] && continue
  if [[ -n "$(run_index_name "$d")" ]]; then
    emit_run "$d" "$name" ACTIVE
  elif [[ -f "$d/00-inventory.md" || -f "$d/INVENTORY.md" || -f "$d/00-methodology.md" ]]; then
    # methodology container — recurse into its runs
    for r in "$d"/*/; do
      r="${r%/}"; rn="$(basename "$r")"
      [[ "$rn" == "_archive" ]] && continue
      if [[ -n "$(run_index_name "$r")" ]]; then emit_run "$r" "$name/$rn" ACTIVE
      elif has_md "$r"; then UNREC+=("$name/$rn"); fi
    done
    for r in "$d"/_archive/*/; do
      r="${r%/}"; [[ -d "$r" ]] || continue
      [[ -n "$(run_index_name "$r")" ]] && emit_run "$r" "$name/_archive/$(basename "$r")" ARCHIVED
    done
  elif has_md "$d"; then
    UNREC+=("$name")
  fi
done
for r in "$AUDITS_DIR"/_archive/*/; do
  r="${r%/}"; [[ -d "$r" ]] || continue
  [[ -n "$(run_index_name "$r")" ]] && emit_run "$r" "_archive/$(basename "$r")" ARCHIVED
done
shopt -u nullglob

# Sort each section newest-first by the leading date key, then strip the key.
sort_section() {
  [[ $# -eq 0 ]] && return 0
  local line
  while IFS= read -r line; do
    printf '%s\n' "${line#*$'\t'}"
  done < <(printf '%s\n' "$@" | sort -r)
}

NEW_IDX="$(mktemp)"; trap 'rm -f "$NEW_IDX"' EXIT
{
  printf '# Audits\n\n'
  printf '_Auto-generated by `aidex-audit` from run front-matter + `00-inventory.md`. Do not edit by hand._\n\n'
  printf '**Updated:** %s\n' "$TODAY"
  if [[ ${#UNREC[@]} -gt 0 ]]; then
    printf '**Runs:** %d active · %d archived · %d unrecognized\n\n' "$active_n" "$archived_n" "${#UNREC[@]}"
  else
    printf '**Runs:** %d active · %d archived\n\n' "$active_n" "$archived_n"
  fi

  if [[ $active_n -gt 0 ]]; then
    printf '## Active runs\n\n'
    sort_section "${ACTIVE[@]}"
    printf '\n'
  else
    printf '_No active audit runs._\n\n'
  fi

  if [[ ${#UNREC[@]} -gt 0 ]]; then
    printf '## Unrecognized run folders (%d)\n\n' "${#UNREC[@]}"
    printf '_Audit folders with no `index.md`/`00-index.md` run header — not counted above. Add a run index (see `aidex-audit` templates) to track them here:_\n\n'
    for u in "${UNREC[@]}"; do printf -- '- [%s](%s/)\n' "$u" "$u"; done
    printf '\n'
  fi

  printf -- '---\n\n'
  if [[ $archived_n -gt 0 ]]; then
    printf '## Archived runs\n\n'
    printf '_Closed run folders (cycle closed). Findings stay live in [`00-inventory.md`](00-inventory.md):_\n\n'
    sort_section "${ARCHIVED[@]}"
    printf '\n'
  else
    printf '_Archived runs: see [`_archive/`](_archive/) once cycles close._\n'
  fi
} > "$NEW_IDX"

# Compare ignoring the volatile "Updated:" timestamp line (a date bump is not drift).
norm() { sed 's/^\*\*Updated:\*\*.*/**Updated:**/' "$1"; }

if [[ "$MODE" == "check" ]]; then
  if [[ ! -f "$INDEX_FILE" ]]; then
    warn "audits/00-index.md missing — run reindex-audits.sh"
    exit 1
  fi
  if ! diff -q <(norm "$INDEX_FILE") <(norm "$NEW_IDX") >/dev/null; then
    warn "audits/00-index.md is stale (drifted from run state) — run reindex-audits.sh"
    exit 1
  fi
  exit 0
fi

mv "$NEW_IDX" "$INDEX_FILE"
trap - EXIT
ok "Regenerated $INDEX_FILE"
printf '%s\n' "$INDEX_FILE"
