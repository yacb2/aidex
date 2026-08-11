#!/usr/bin/env bash
# test-skill-script-refs.sh — every script path SKILL.md names must resolve, and none
# may be built by interpolation.
#
#   1. resolvable    — every literal `scripts/<name>` in SKILL.md exists on disk
#   2. no-interp     — no `scripts/${VAR}` form appears; an interpolated path is
#                      unverifiable by construction, and BL-147 is what that costs:
#                      `scripts/${ACTION}.sh` named six scripts that never existed.
#   3. hint-lockstep — every command the sub-actions table documents also appears in
#                      `argument-hint`. That string is what autocomplete shows when the
#                      user types `/aidex-audit`, so a command missing from it is
#                      invisible at the one moment someone is choosing what to run —
#                      how coverage-matrix, coverage-sweep and affected-tests shipped
#                      undiscoverable (BL-155). The table is the single owner of
#                      command → script (BL-147), so it is the source and the hint is
#                      what gets checked, never the reverse.
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

check_hint_lockstep() {
  local skill="$1"
  local disp; disp="$(basename "$(cd "$(dirname "$skill")" && pwd)")/SKILL.md"
  local hint; hint="$(grep -m1 '^argument-hint:' "$skill")"
  local cmds=() cmd
  # The table rows, not the prose: a row's first cell opens `| `/aidex-audit <cmd>`.
  # The bare help row has a backtick where the command would be, so it drops out.
  while IFS= read -r cmd; do cmds+=("$cmd"); done \
    < <(grep -oE '^\| `/aidex-audit [a-z-]+' "$skill" | awk '{print $3}' | sort -u)

  # An empty command list or a missing hint line passes the loop below vacuously.
  if [[ -z "$hint" || "${#cmds[@]}" -lt 3 ]]; then
    FAIL=$((FAIL+1))
    RESULTS+=("FAIL [hint-lockstep: $disp]: read ${#cmds[@]} command(s) from the table, hint line ${hint:+found}${hint:-missing}")
    return
  fi

  local missing=()
  for cmd in "${cmds[@]}"; do
    grep -qE "(^|[^A-Za-z-])${cmd}([^A-Za-z-]|$)" <<<"$hint" || missing+=("$cmd")
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    PASS=$((PASS+1)); RESULTS+=("PASS [hint-lockstep: $disp]: ${#cmds[@]} commands, all in argument-hint")
  else
    FAIL=$((FAIL+1))
    RESULTS+=("FAIL [hint-lockstep: $disp]: ${#missing[@]} documented command(s) absent from argument-hint")
    for cmd in "${missing[@]}"; do RESULTS+=("    $cmd"); done
  fi
}

for skill in "${SKILL_FILES[@]}"; do
  check_resolvable "$skill"
  check_no_interp "$skill"
  check_hint_lockstep "$skill"
done

printf '\n'
for r in "${RESULTS[@]}"; do
  printf '%s\n' "$r"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
