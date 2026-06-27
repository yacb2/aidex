#!/usr/bin/env bash
# reconcile.sh — read-only drift detector across the tracking chain
# (audit → backlog → plan). Surfaces closure that did not propagate, so "is it
# really closed?" becomes a by-exception check instead of a constant manual one.
#
# Shared cross-artifact script (invokable directly or by the lifecycle skills).
#
# Detects:
#   A) propagate-close candidates — an active backlog item (open/doing) whose
#      escalated_to plan is already done/archived ⇒ the item should be closed.
#   B) done-without-commits — a done backlog item / plan with empty `commits:`
#      and no superseded_by/escalated_to ⇒ closure asserted without provenance
#      (informational; pre-D-09 items legitimately lack commits).
#
# Exit: 1 if any category-A (actionable) drift exists, else 0. Never writes.

set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_YELLOW=$'\033[33m' C_DIM=$'\033[2m' C_BOLD=$'\033[1m' C_GREEN=$'\033[32m' C_RESET=$'\033[0m'
else C_YELLOW='' C_DIM='' C_BOLD='' C_GREEN='' C_RESET=''; fi

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  pwd -P
}

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
PLANS_DIR="$ROOT/.context/plans"
AUDITS_DIR="$ROOT/.context/audits"

fm() { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":"{sub(/^[^:]*:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }

# status of a plan referenced as plan/<slug> (or bare <slug>): archived | <status> | missing
plan_status() {
  local ref="$1" slug; slug="${ref#plan/}"; slug="${slug%/}"
  [[ -d "$PLANS_DIR/_archive/$slug" || -f "$PLANS_DIR/_archive/$slug.md" || -f "$PLANS_DIR/_archive/$slug" ]] && { echo "archived"; return; }
  if [[ -f "$PLANS_DIR/$slug/00-index.md" ]]; then fm "$PLANS_DIR/$slug/00-index.md" status; return; fi
  if [[ -f "$PLANS_DIR/$slug.md" ]]; then fm "$PLANS_DIR/$slug.md" status; return; fi
  echo "missing"
}

declare -a CAND_A=() INFO_B=()

# --- A: active backlog whose escalated_to plan is done/archived ---
if [[ -d "$BACKLOG_DIR" ]]; then
  shopt -s nullglob
  for f in "$BACKLOG_DIR"/*.md; do
    [[ "$(basename "$f")" == "00-index.md" ]] && continue
    st="$(fm "$f" status)"; esc="$(fm "$f" escalated_to)"; id="$(fm "$f" id)"
    case "$st" in open|doing) ;; *) continue ;; esac
    [[ -n "$esc" ]] || continue
    ps="$(plan_status "$esc")"
    if [[ "$ps" == "done" || "$ps" == "archived" || "$ps" == "dropped" ]]; then
      CAND_A+=("${id:-?} ($(basename "$f")) — status=$st but plan ${esc} is ${ps} ⇒ close it")
    fi
  done
  shopt -u nullglob
fi

# --- B: done artifacts with no commit provenance ---
check_done_no_commits() {
  local f="$1" kind="$2" st sup esc com id
  st="$(fm "$f" status)"; [[ "$st" == "done" ]] || return 0
  sup="$(fm "$f" superseded_by)"; esc="$(fm "$f" escalated_to)"; com="$(fm "$f" commits)"
  [[ -n "$sup" || -n "$esc" ]] && return 0   # provenance is the link, not a commit
  [[ -n "$com" ]] && return 0
  id="$(fm "$f" id)"
  local name; name="$(basename "$f")"
  [[ "$name" == "00-index.md" ]] && name="$(basename "$(dirname "$f")")/"
  INFO_B+=("${kind}: ${id:+${id} }${name}")
}
if [[ -d "$BACKLOG_DIR" ]]; then
  shopt -s nullglob
  for f in "$BACKLOG_DIR"/*.md "$BACKLOG_DIR"/_archive/*.md; do
    [[ "$(basename "$f")" == "00-index.md" ]] && continue
    check_done_no_commits "$f" "backlog"
  done
  for d in "$PLANS_DIR"/*/ "$PLANS_DIR"/_archive/*/; do
    [[ -f "$d/00-index.md" ]] && check_done_no_commits "$d/00-index.md" "plan"
  done
  for f in "$PLANS_DIR"/*.md "$PLANS_DIR"/_archive/*.md; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in
      00-index.md|*.bak.md) continue ;;   # top-level roll-up / index backup, not a plan
    esac
    check_done_no_commits "$f" "plan"
  done
  shopt -u nullglob
fi

# --- C: roll-up index freshness — delegate to each reindexer's read-only --check ---
# Keeps reconcile read-only: the reindex scripts compare the on-disk index against
# what the front-matter would regenerate, and never write in --check mode.
declare -a DRIFT_C=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RP="$SCRIPT_DIR/../../aidex-plan/scripts/reindex-plans.sh"
RA="$SCRIPT_DIR/../../aidex-audit/scripts/reindex-audits.sh"
if [[ -x "$RP" && -d "$PLANS_DIR" ]]; then
  msg="$(NO_COLOR=1 bash "$RP" --check 2>&1)" || DRIFT_C+=("${msg:-plans index stale}")
fi
if [[ -x "$RA" && -d "$AUDITS_DIR" ]]; then
  msg="$(NO_COLOR=1 bash "$RA" --check 2>&1)" || DRIFT_C+=("${msg:-audits index stale}")
fi

echo
printf '%sReconcile — tracking drift%s\n' "$C_BOLD" "$C_RESET"
if [[ ${#CAND_A[@]} -gt 0 ]]; then
  printf '\n%sClose candidates (plan done, backlog still open):%s\n' "$C_YELLOW$C_BOLD" "$C_RESET"
  printf '  - %s\n' "${CAND_A[@]}"
fi
if [[ ${#DRIFT_C[@]} -gt 0 ]]; then
  printf '\n%sRoll-up index drift (regenerate to refresh):%s\n' "$C_YELLOW$C_BOLD" "$C_RESET"
  printf '  - %s\n' "${DRIFT_C[@]}"
fi
if [[ ${#INFO_B[@]} -gt 0 ]]; then
  printf '\n%sDone without commit provenance (info — pre-D-09 items are expected here):%s\n' "$C_DIM" "$C_RESET"
  printf '  - %s\n' "${INFO_B[@]}"
fi
if [[ ${#CAND_A[@]} -eq 0 && ${#DRIFT_C[@]} -eq 0 && ${#INFO_B[@]} -eq 0 ]]; then
  printf '\n%sNo drift detected — tracking chain is consistent.%s\n' "$C_GREEN" "$C_RESET"
fi
echo

[[ ${#CAND_A[@]} -gt 0 || ${#DRIFT_C[@]} -gt 0 ]] && exit 1 || exit 0
