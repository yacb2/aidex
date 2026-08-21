#!/usr/bin/env bash
# check-worktree-isolation.sh — one command: is this project's worktree setup
# sound, across every surface a worktree can leak through?
#
# WHY AN UMBRELLA EXISTS AT ALL
#
# `check-compose-isolation.sh` was written first, and it is good. Every defect
# found in the 2026-08-21 audit lived OUTSIDE it — services that never start,
# host-process ports, host env files, test-runner defaults — and the reason none
# of them was caught is not that the checks were wrong. It is that there was no
# single command anyone ran. Four scripts nobody remembers is the same failure
# as one comment nobody re-reads, which is the failure this whole plan is about.
#
# So this file adds no logic of its own. Each check keeps its own script and its
# own test; this one sequences them and aggregates. Adding a check here without
# adding it to a script is how the umbrella would start lying.
#
# DOCTRINE, PRESERVED VERBATIM FROM THE BOOTSTRAP: every finding is a BLOCKER,
# not a warning. A worktree that "mostly" isolates is one that silently drove
# dev's stack on the run nobody was watching.
#
# Usage:
#   check-worktree-isolation.sh [project-root]   # this project
#   check-worktree-isolation.sh --census         # every project with a config
#
# Exit 0 = every surface holds. Exit 1 = findings (each check printed its own).

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$(cd "$SELF_DIR/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

CENSUS=false
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --census) CENSUS=true; shift ;;
    -h|--help) sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

# Deliberately NOT fail-fast. The bootstrap author wants the whole picture in one
# pass: stopping at the first blocker turns a five-minute fix into five rounds of
# run-fix-rerun, and that is how a checker stops being run.
run_all_for() {  # run_all_for <project-root> -> 0 clean, 1 findings
  local root="$1" rc=0

  # 1. compose addressing — image / container_name / published ports / volumes.
  #    Runs from the project root because it defaults to ./docker-compose.yml.
  if [[ -f "$root/docker-compose.yml" ]]; then
    ( cd "$root" && bash "$SELF_DIR/check-compose-isolation.sh" ) || rc=1
  fi

  # 2. host-process ports — a linked script that can bind or KILL dev's ports.
  bash "$SELF_DIR/check-worktree-ports.sh" "$root" || rc=1

  # 3. test-runner entry points — a harness that reaches dev's stack when
  #    invoked directly rather than through the project's own wrapper.
  bash "$SELF_DIR/check-worktree-runner.sh" "$root" || rc=1

  return $rc
}

if $CENSUS; then
  rc=0; seen=0
  CENSUS_ROOT="${AIDEX_PROJECTS_DIR:-$HOME/Documents/projects}"
  for cfg in "$CENSUS_ROOT"/*/.context/worktrees/config.env; do
    [[ -f "$cfg" ]] || continue
    seen=$((seen + 1))
    root="${cfg%/.context/worktrees/config.env}"
    printf '\n=== %s\n' "$(basename "$root")"
    run_all_for "$root" || rc=1
  done
  # Enumerating zero projects is not a pass. This command is a phase gate, and a
  # path that matches nothing would print green forever on any other machine.
  if [[ $seen -eq 0 ]]; then
    err "census examined 0 projects under $CENSUS_ROOT — nothing was checked."
    err "Set AIDEX_PROJECTS_DIR to the directory holding the projects."
    exit 2
  fi
  printf '\n'
  [[ $rc -eq 0 ]] && ok "worktree isolation: $seen project(s), every surface holds"
  exit $rc
fi

ROOT="${TARGET:-$(find_project_root)}"
run_all_for "$ROOT" || exit 1
ok "worktree isolation OK: $(basename "$ROOT") — compose, host ports and test runners all hold"
