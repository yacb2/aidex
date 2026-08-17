#!/usr/bin/env bash
# run-all.sh — run every test in the repo, wherever it lives.
#
# Why this exists: the suite is spread over several locations — `tests/test-*.sh`,
# `skills/*/tests/test-*.sh`, and `skills/*/scripts/test[-_]*.{sh,py}`. Sweeps that walked
# the first two silently skipped the third, and on 2026-08-06 an over-maximum SKILL.md body
# reached a commit with the suite reported green because `test_skill_budget.sh` sits in
# `scripts/` (BL-113). A runner that discovers tests cannot develop that blind spot.
#
# It developed one anyway. The `scripts/` globs matched `test_*` only, so every
# HYPHENATED test under `skills/*/scripts/` was invisible — 17 of them, including
# `test-find-project-root.sh`, whose whole job is to fail when a script defines a
# private `find_project_root`. That guard was unwired the day it was written, and
# the runner still reported green. Naming style is not a reason to skip a test.
#
# Docker-dependent tests are opted into, not discovered: nine aidex-worktree
# tests need a live daemon and take minutes, and folding them in by default would
# turn a seconds-long daemon-free suite into one that cannot run on a laptop with
# Docker closed. `RUN_DOCKER_TESTS=1 tests/run-all.sh` includes them.
#
# Usage:
#   tests/run-all.sh            # quiet: one line per test, failures reprinted in full
#   tests/run-all.sh --verbose  # stream every test's output as it runs
#
# Exit 0 only when every test passes.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_ROOT"

VERBOSE=0
[[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && VERBOSE=1

shopt -s nullglob
TESTS=(tests/test-*.sh skills/*/tests/test-*.sh
       skills/*/scripts/test_*.sh skills/*/scripts/test_*.py
       skills/aidex-conventions/scripts/test-*.sh)
if [[ "${RUN_DOCKER_TESTS:-0}" == "1" ]]; then
  TESTS+=(skills/aidex-worktree/scripts/test-*.sh)
else
  DOCKER_SKIPPED=(skills/aidex-worktree/scripts/test-*.sh)
fi
DOCKER_SKIPPED=("${DOCKER_SKIPPED[@]:-}")
[[ -z "${DOCKER_SKIPPED[0]:-}" ]] && DOCKER_SKIPPED=()
shopt -u nullglob

PASS=0
FAILED=()
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

for t in "${TESTS[@]}"; do
  # Python tests import sibling modules by relative name, so run them from their own dir.
  case "$t" in
    *.py) ( cd "$(dirname "$t")" && python3 "$(basename "$t")" ) >"$LOG" 2>&1 ;;
    *)    bash "$t" >"$LOG" 2>&1 ;;
  esac
  rc=$?
  if [[ $rc -eq 0 ]]; then
    PASS=$((PASS + 1))
    printf 'PASS  %s\n' "$t"
    [[ $VERBOSE -eq 1 ]] && cat "$LOG"
  else
    FAILED+=("$t")
    printf 'FAIL  %s (exit %d)\n' "$t" "$rc"
    cat "$LOG"
  fi
done

printf '\n%d/%d passed\n' "$PASS" "${#TESTS[@]}"
# A skipped test is announced, never silent: "65/65 passed" over a set that
# quietly excluded a whole family is exactly the claim this runner exists to
# stop making.
if [[ ${#DOCKER_SKIPPED[@]} -gt 0 ]]; then
  printf 'skipped %d docker-dependent test(s) — run with RUN_DOCKER_TESTS=1 to include them\n' \
    "${#DOCKER_SKIPPED[@]}"
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf 'failed: %s\n' "${FAILED[*]}"
  exit 1
fi
