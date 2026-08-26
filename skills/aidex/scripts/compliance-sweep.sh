#!/usr/bin/env bash
# compliance-sweep.sh — one read-only drift check across every project (BL-038).
#
# The three instruments already existed and each had to be remembered and run by
# hand, per project: validate.py (ratchet-checked .context/ conformance),
# reconcile.sh (audit -> backlog -> plan closure that did not propagate) and
# sweep.sh (done/dropped items still sitting in the active folder). Nothing ran
# them on a cadence, which is the failure mode that let two guards sit dead for
# 19 days and the ADR map sit dead for every installed user.
#
# A clean run is SILENT. Only drift prints, so this is safe to schedule and
# noisy only when it should be. Exit 1 if any project drifted, 0 otherwise.
#
# Read-only: sweep runs in dry-run, reconcile never writes, validate never
# rewrites its baseline without an explicit --baseline. Nothing here mutates a
# project, by design — a scheduled routine that edits is a routine you stop
# trusting.
#
# Usage:
#   compliance-sweep.sh                      # every project under $AIDEX_WORKSPACE_ROOT (default ~/Documents/projects)
#   compliance-sweep.sh --root <dir>         # ...under <dir> instead
#   compliance-sweep.sh <project> [<proj>..] # ...only these, a named list
#   compliance-sweep.sh --verbose            # also name the clean and skipped ones
#
# Cadence and engine are deliberately NOT hardcoded: this is a plain command, so
# schedule it however you already schedule things (a routine, cron, /loop). See
# the aidex SKILL.md row for the wiring.

set -uo pipefail   # not -e: a drifting project must not abort the sweep

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VALIDATE="$SCRIPT_DIR/../../aidex-conventions/scripts/validate.py"
RECONCILE="$SCRIPT_DIR/../../aidex-backlog/scripts/reconcile.sh"
SWEEP="$SCRIPT_DIR/../../aidex-backlog/scripts/sweep.sh"

ROOT="${AIDEX_WORKSPACE_ROOT:-$HOME/Documents/projects}"
VERBOSE=0
PROJECTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)      ROOT="$2"; shift 2 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help)   sed -n '2,27p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "unknown option: $1" >&2; exit 2 ;;
    *)           PROJECTS+=("$1"); shift ;;
  esac
done

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  ROOT="${ROOT/#\~/$HOME}"
  [[ -d "$ROOT" ]] || { echo "no such root: $ROOT" >&2; exit 2; }
  while IFS= read -r d; do PROJECTS+=("$d"); done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
fi

if [[ ${#PROJECTS[@]} -eq 0 ]]; then
  echo "no projects to check" >&2; exit 2
fi

drifted=0; checked=0; skipped=0

for p in "${PROJECTS[@]}"; do
  name="$(basename "$p")"
  if [[ ! -d "$p/.context" ]]; then
    skipped=$((skipped+1))
    [[ $VERBOSE -eq 1 ]] && printf '  --  %s (no .context/)\n' "$name"
    continue
  fi
  checked=$((checked+1))
  report=""

  # 1. Conventions, ratchet-checked: a project with a baseline reports only
  #    violations it has not already accepted.
  v_out="$(python3 "$VALIDATE" "$p/.context" 2>&1)"; v_rc=$?
  if [[ $v_rc -ne 0 ]]; then
    report="$report$(printf '  validate: exit %d\n' "$v_rc")\n"
    report="$report$(printf '%s\n' "$v_out" | grep -E '^\s*\[[a-z-]+\]|violation|NEW' | head -8 | sed 's/^/      /')\n"
  fi

  # 2. Closure that did not propagate. Exit 1 = actionable (category A or index drift).
  r_out="$(cd "$p" && NO_COLOR=1 bash "$RECONCILE" 2>&1)"; r_rc=$?
  if [[ $r_rc -ne 0 ]]; then
    # Stop at the info block: reconcile exits 1 only on close-candidates and
    # index drift, so its "done without commit provenance" list is not drift.
    report="$report  reconcile:\n"
    report="$report$(printf '%s\n' "$r_out" \
      | awk '/Done without commit provenance/{exit} /^  - /{print}' \
      | head -8 | sed 's/^/    /')\n"
  fi

  # 3. Archive-on-close (D-10). sweep.sh exits 0 either way, so count its lines.
  s_out="$(cd "$p" && bash "$SWEEP" 2>&1)"
  s_n="$(printf '%s\n' "$s_out" | grep -c '^\[dry-run\] would archive')"
  if [[ "$s_n" -gt 0 ]]; then
    report="$report$(printf '  sweep: %s done/dropped item(s) still in the active folder\n' "$s_n")\n"
  fi

  if [[ -n "$report" ]]; then
    drifted=$((drifted+1))
    printf '\n%s\n' "$name"
    printf "$report"
  elif [[ $VERBOSE -eq 1 ]]; then
    printf '  OK  %s\n' "$name"
  fi
done

if [[ $drifted -gt 0 ]]; then
  printf '\n%d of %d project(s) drifted (%d without .context/ skipped)\n' \
    "$drifted" "$checked" "$skipped"
  exit 1
fi

[[ $VERBOSE -eq 1 ]] && printf '\n%d project(s) clean, %d skipped\n' "$checked" "$skipped"
exit 0
