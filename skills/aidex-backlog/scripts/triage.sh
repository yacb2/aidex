#!/usr/bin/env bash
# triage.sh — the backlog's health in one read-only pass.
#
# The three checks already existed as separate scripts, so knowing whether the backlog was
# healthy meant remembering to run all three and reading three unrelated outputs. This runs
# them together and prints one report:
#
#   ids       duplicate or nonconforming BL-NNN ids       (register-item.sh --check-ids)
#   archive   done/dropped items still in the active dir  (sweep.sh --check)
#   drift     open items whose plan is done, done items with no commit  (reconcile.sh)
#
# READ-ONLY. Every check runs in its reporting mode and the fix commands are printed, never
# executed — including the index regeneration, which is why the id check uses --check-ids
# rather than --reindex.
#
# Exit 1 when any check found something actionable, so it can gate CI or a hook.
#
# Usage: triage.sh [--quiet]     # --quiet prints only the summary line and the fixes

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/../../aidex-conventions/scripts/_lib.sh" 2>/dev/null || {
  find_project_root() {
    local dir; dir="$(pwd -P)"
    while [[ "$dir" != "/" ]]; do
      [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
      dir="$(dirname "$dir")"
    done
    pwd -P
  }
}

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"

if [[ ! -d "$BACKLOG_DIR" ]]; then
  printf 'no backlog at %s — nothing to triage\n' "$BACKLOG_DIR"
  exit 0
fi

say() { [[ $QUIET -eq 1 ]] || printf '%s\n' "$*"; }

PROBLEMS=()   # one "<check>: <headline>" per failing check
FIXES=()      # the command that resolves each

run_check() {
  # run_check <name> <headline> <fix-command> <command...>
  local name="$1" headline="$2" fix="$3"; shift 3
  local out rc
  # `|| rc=$?`, never a bare `rc=$?`: _lib.sh turns on `set -e`, and a checker whose whole
  # job is to run commands that fail would abort on the first one that did.
  out="$("$@" 2>&1)" && rc=0 || rc=$?
  if [[ $rc -eq 0 ]]; then
    say "  [ok]   $name"
    return 0
  fi
  say "  [!]    $name — $headline"
  [[ $QUIET -eq 1 || -z "$out" ]] || printf '%s\n' "$out" | sed 's/^/           /'
  PROBLEMS+=("$name: $headline")
  FIXES+=("$fix")
  return 1
}

say "backlog triage — $BACKLOG_DIR"
say ""

run_check "ids" "duplicate or nonconforming BL-NNN id" \
  "bash $SCRIPT_DIR/migrate-ids.sh --apply    # then fix any hand-authored id by hand" \
  bash "$SCRIPT_DIR/register-item.sh" --check-ids || true

run_check "archive" "done/dropped items never moved to _archive/ (D-10)" \
  "bash $SCRIPT_DIR/sweep.sh --apply" \
  bash "$SCRIPT_DIR/sweep.sh" --check || true

run_check "drift" "closure that did not propagate across artifacts" \
  "close the named items with close-item.sh, or record the missing commit" \
  bash "$SCRIPT_DIR/reconcile.sh" || true

say ""
if [[ ${#PROBLEMS[@]} -eq 0 ]]; then
  say "clean — ids conform, nothing unarchived, no cross-artifact drift"
  exit 0
fi

printf '%d of 3 checks found something actionable:\n' "${#PROBLEMS[@]}"
for i in "${!PROBLEMS[@]}"; do
  printf '  - %s\n' "${PROBLEMS[$i]}"
  printf '      fix: %s\n' "${FIXES[$i]}"
done
printf '\nNothing was changed — triage only reports.\n'
exit 1
