#!/usr/bin/env bash
# run-all.sh — run every test in the repo, wherever it lives.
#
# Why this exists: the suite is spread over three locations — `tests/test-*.sh`,
# `skills/*/tests/test-*.sh`, and `skills/*/scripts/test_*.{sh,py}`. Sweeps that walked the
# first two silently skipped the third, and on 2026-08-06 an over-maximum SKILL.md body
# reached a commit with the suite reported green because `test_skill_budget.sh` sits in
# `scripts/` (BL-113). A runner that discovers tests cannot develop that blind spot.
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
TESTS=(tests/test-*.sh skills/*/tests/test-*.sh skills/*/scripts/test_*.sh skills/*/scripts/test_*.py)
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
if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf 'failed: %s\n' "${FAILED[*]}"
  exit 1
fi
