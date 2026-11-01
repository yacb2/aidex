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
#   C) roll-up index drift — a plans/audits 00-index.md that no longer matches its files.
#
#   D) PR-state drift — a backlog item's `pr:` entries (pr/<repo>#<n>@<state>, a comma
#      list; backlog tracker profile) disagree with its status. No `gh`, no fetch:
#      D1  a done item with a pr entry still @draft, @open or @approved;
#      D2  an open/doing item with a pr entry not @merged/@closed while a squash title
#          ending `(#<n>)` is in `git -C <root>/<repo> log --remotes` (as fresh as the last
#          `git fetch`; a missing <repo> checkout gives no row), or whose every pr entry is
#          already @merged/@closed.
#
# Exit: 1 if any category-A (actionable) or category-C (stale index) drift exists, else 0.
# Categories B and D are informational and never change the exit. Never writes.

set -euo pipefail

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
PLANS_DIR="$ROOT/.context/plans"
AUDITS_DIR="$ROOT/.context/audits"

fm() { awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":"{sub(/^[^:]*:[[:space:]]*/,""); gsub(/^"|"$/,""); print; exit}' "$1"; }

# status of a plan referenced as plan/<slug> (or bare <slug>): archived | <status> | missing
plan_status() {
  local ref="$1" slug; slug="${ref#plan/}"; slug="${slug%/}"; slug="${slug%.md}"
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
    # escalated_to may be a comma list (a plan plus cross-repo refs): the item is a close
    # candidate when it has at least one plan and every plan it names is finished.
    plans=0 live=0 ps=""
    while IFS= read -r ref; do
      ref="${ref#"${ref%%[![:space:]]*}"}"; ref="${ref%"${ref##*[![:space:]]}"}"
      [[ -n "$ref" ]] || continue
      one="$(plan_status "$ref")"
      case "$one" in
        missing) ;;
        done|archived|dropped) plans=$((plans+1)); ps="$one" ;;
        *) live=1 ;;
      esac
    done < <(printf '%s\n' "$esc" | tr ',' '\n')
    if [[ $plans -gt 0 && $live -eq 0 ]]; then
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
  [[ -n "$com" && "$com" != "[]" ]] && return 0
  id="$(fm "$f" id)"
  local name; name="$(basename "$f")"
  [[ "$name" == "00-index.md" ]] && name="$(basename "$(dirname "$f")")/"
  INFO_B+=("${kind}: ${id:+${id} }${name}")
}
if [[ -d "$BACKLOG_DIR" || -d "$PLANS_DIR" ]]; then
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
RP="$SCRIPT_DIR/../../plan/scripts/reindex-plans.sh"
RA="$SCRIPT_DIR/../../audit/scripts/reindex-audits.sh"
if [[ -x "$RP" && -d "$PLANS_DIR" ]]; then
  msg="$(NO_COLOR=1 bash "$RP" --check 2>&1)" || DRIFT_C+=("${msg:-plans index stale}")
fi
if [[ -x "$RA" && -d "$AUDITS_DIR" ]]; then
  msg="$(NO_COLOR=1 bash "$RA" --check 2>&1)" || DRIFT_C+=("${msg:-audits index stale}")
fi

# --- D: PR-state drift (pr: field vs item status) — reads local git only, edits nothing ---
declare -a DRIFT_D=()
# squash_title <repo-dir> <n>: the first remote-ref subject ending `(#<n>)`; the closing
# paren anchors the number, so #1 never matches (#12). Only a checkout (<dir>/.git) is read:
# git -C on a plain directory climbs to an enclosing repo, or exits 128 and, under pipefail,
# would end this script. A missing dir or a non-checkout prints nothing.
squash_title() {
  [[ -e "$1/.git" ]] || return 0
  { git -C "$1" log --remotes --format=%s 2>/dev/null || true; } \
    | awk -v t="(#$2)" '{ s=$0; sub(/[[:space:]]+$/,"",s) } length(s)>=length(t) && substr(s,length(s)-length(t)+1)==t { print; exit }'
}
check_pr_drift() {
  local f="$1" st prs id e repo n state live="" all=1 any=0 title
  prs="$(fm "$f" pr)"; [[ -n "$prs" ]] || return 0
  st="$(fm "$f" status)"; id="$(fm "$f" id)"; id="${id:-?}"
  while IFS= read -r e; do
    e="${e//[[:space:]]/}"; e="${e#pr/}"
    [[ "$e" =~ ^([A-Za-z0-9._-]+)#([0-9]+)(@([a-z]+))?$ ]] || continue
    repo="${BASH_REMATCH[1]}" n="${BASH_REMATCH[2]}" state="${BASH_REMATCH[4]}"
    any=1
    case "$state" in merged|closed) continue ;; esac
    all=0
    case "$st" in
      done)
        case "$state" in draft|open|approved) live="${live:+$live, }$repo#$n@$state" ;; esac ;;
      open|doing)
        [[ "$repo" == . || "$repo" == .. ]] && continue
        title="$(squash_title "$ROOT/$repo" "$n")"
        [[ -n "$title" ]] && DRIFT_D+=("D2 $id ($(basename "$f")) — status=$st, pr $repo#$n@${state:-?} but $repo log --remotes has \"$title\" ⇒ record @merged and close it") ;;
    esac
  done < <(printf '%s\n' "$prs" | tr ',' '\n')
  [[ -n "$live" ]] && DRIFT_D+=("D1 $id ($(basename "$f")) — status=done but pr $live is still live ⇒ reopen it or record the PR state")
  if [[ $any -eq 1 && $all -eq 1 ]]; then
    case "$st" in open|doing) DRIFT_D+=("D2 $id ($(basename "$f")) — status=$st but every pr is merged/closed ⇒ close it") ;; esac
  fi
  return 0
}
if [[ -d "$BACKLOG_DIR" ]]; then
  shopt -s nullglob
  for f in "$BACKLOG_DIR"/*.md "$BACKLOG_DIR"/_archive/*.md; do
    [[ "$(basename "$f")" == "00-index.md" ]] && continue
    check_pr_drift "$f"
  done
  shopt -u nullglob
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
if [[ ${#DRIFT_D[@]} -gt 0 ]]; then
  printf '\n%sPR-state drift (pr: vs status; D2 is as fresh as the last git fetch):%s\n' "$C_YELLOW$C_BOLD" "$C_RESET"
  printf '  - %s\n' "${DRIFT_D[@]}"
fi
if [[ ${#INFO_B[@]} -gt 0 ]]; then
  printf '\n%sDone without commit provenance (info — pre-D-09 items are expected here):%s\n' "$C_DIM" "$C_RESET"
  printf '  - %s\n' "${INFO_B[@]}"
fi
if [[ ${#CAND_A[@]} -eq 0 && ${#DRIFT_C[@]} -eq 0 && ${#DRIFT_D[@]} -eq 0 && ${#INFO_B[@]} -eq 0 ]]; then
  printf '\n%sNo drift detected — tracking chain is consistent.%s\n' "$C_GREEN" "$C_RESET"
fi
echo

[[ ${#CAND_A[@]} -gt 0 || ${#DRIFT_C[@]} -gt 0 ]] && exit 1 || exit 0
