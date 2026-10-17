#!/usr/bin/env bash
# test_arbiter_policy_lockstep.sh — guard canon<->template arbiter policy drift.
#
# The arbiter policy is canonical in the ARBITER block of workflow-core.md and re-embedded in the
# workflow templates (skills/*/assets/workflows/*.workflow.js, as ARBITER_PROMPT). The
# durability-arbiter agent doc that used to be the second host was retired 2026-10-05.
# test_workflow_core_drift.sh locks canon<->assets byte-for-byte; this test asserts the canon block
# still carries all five decision tiers and the verdict enum (the drift test already guarantees every
# template's block equals it), so a tier dropped from the canon fails loudly. It does NOT
# require identical wording.
#
# Run:   bash skills/conventions/scripts/test_arbiter_policy_lockstep.sh
# Args:  optional [canon_path] overrides the default (used to self-test the guard).
# Exit:  0 if every host carries every marker; 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CANON="${1:-$REPO_ROOT/skills/conventions/references/workflow-core.md}"

[ -f "$CANON" ] || { echo "FAIL: canon not found: $CANON" >&2; exit 1; }

# Canonical ARBITER block only (not the whole canon doc).
extract_arbiter() {
  awk '
    $0 == "// === ARBITER:START ===" { grab=1; next }
    $0 == "// === ARBITER:END ==="   { if (grab) exit }
    grab { print }
  ' "$1"
}

CANON_BLOCK="$(extract_arbiter "$CANON")"
[ -n "$CANON_BLOCK" ] || { echo "FAIL: no ARBITER block between markers in $CANON" >&2; exit 1; }

# Decision tiers + verdict enum that BOTH hosts must carry (fixed strings, case-insensitive).
MARKERS=(
  "Deny-class"
  "Stop condition"
  "Unauthorized publication"
  "Mandated step"
  "Safe + additive"
  "CONTINUE"
  "ASK"
  "STOP"
)

FAIL=0
check() {
  local label="$1" text="$2" m
  for m in "${MARKERS[@]}"; do
    if ! printf '%s' "$text" | grep >/dev/null -Fi -- "$m"; then
      echo "  FAIL: $label missing arbiter policy marker: \"$m\"" >&2
      FAIL=$((FAIL+1))
    fi
  done
}

check "canon ARBITER block" "$CANON_BLOCK"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "arbiter-policy-lockstep: OK — canon block carries all ${#MARKERS[@]} markers (5 tiers + verdict enum)"
else
  echo "arbiter-policy-lockstep: $FAIL missing — a one-sided policy edit drifted the hosts"
fi
[ "$FAIL" -eq 0 ]
