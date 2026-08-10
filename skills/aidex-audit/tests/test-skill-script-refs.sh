#!/usr/bin/env bash
# test-skill-script-refs.sh — every script path SKILL.md names must resolve, and none
# may be built by interpolation.
#
#   1. resolvable    — every literal `scripts/<name>` in SKILL.md exists on disk
#   2. no-interp     — no `scripts/${VAR}` form appears; an interpolated path is
#                      unverifiable by construction, and BL-147 is what that costs:
#                      `scripts/${ACTION}.sh` named six scripts that never existed.
#
# Scoped to aidex-audit on purpose — widening SKILL_FILES to the other skills is a
# one-line change, and their own reference drift is not this test's to carry.
#
# Run: bash skills/aidex-audit/tests/test-skill-script-refs.sh
# Exit: 0 if both checks pass, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILES=("$SCRIPT_DIR/../SKILL.md")

PASS=0
FAIL=0
RESULTS=()

check_resolvable() {
  local skill="$1"
  local base; base="$(dirname "$skill")"
  local disp; disp="$(basename "$(cd "$base" && pwd)")/SKILL.md"
  local missing=()
  local ref
  while IFS= read -r ref; do
    [[ -f "$base/$ref" ]] || missing+=("$ref")
  done < <(grep -oE 'scripts/[A-Za-z0-9_.-]+\.(sh|py)' "$skill" | sort -u)

  if [[ "${#missing[@]}" -eq 0 ]]; then
    PASS=$((PASS+1)); RESULTS+=("PASS [resolvable: $disp]")
  else
    FAIL=$((FAIL+1))
    RESULTS+=("FAIL [resolvable: $disp]: ${#missing[@]} path(s) do not exist")
    for ref in "${missing[@]}"; do RESULTS+=("    $ref"); done
  fi
}

check_no_interp() {
  local skill="$1"
  local disp; disp="$(basename "$(cd "$(dirname "$skill")" && pwd)")/SKILL.md"
  local hits
  hits="$(grep -nE 'scripts/\$' "$skill")"
  if [[ -z "$hits" ]]; then
    PASS=$((PASS+1)); RESULTS+=("PASS [no-interp: $disp]")
  else
    FAIL=$((FAIL+1))
    RESULTS+=("FAIL [no-interp: $disp]: interpolated script path(s)")
    while IFS= read -r line; do RESULTS+=("    $line"); done <<<"$hits"
  fi
}

for skill in "${SKILL_FILES[@]}"; do
  check_resolvable "$skill"
  check_no_interp "$skill"
done

printf '\n'
for r in "${RESULTS[@]}"; do
  printf '%s\n' "$r"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
