#!/usr/bin/env bash
# test_arbiter_policy_lockstep.sh — guard batch<->interactive arbiter policy drift.
#
# The batch arbiter prompt (the canonical ARBITER block in workflow-core.md, re-embedded into the
# workflow assets) is a backtick-free RENDERING of the interactive agent prompt
# (agents/durability-arbiter.md). Byte-identity between the two is impossible — the markdown agent
# doc's backticks + ```json fence would terminate a JS template literal — so
# test_workflow_core_drift.sh can only lock canon<->assets, not canon<->agent-doc. This test closes
# that residual: it asserts BOTH texts still carry all five decision tiers and the verdict enum, so a
# ONE-SIDED policy edit (a tier dropped from one host but not the other) fails loudly. It does NOT
# require identical wording — only that no tier silently disappears from a host.
#
# Run:   bash skills/aidex-conventions/scripts/test_arbiter_policy_lockstep.sh
# Args:  optional [canon_path] [agent_path] override the defaults (used to self-test the guard).
# Exit:  0 if both texts carry every marker; 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CANON="${1:-$REPO_ROOT/skills/aidex-conventions/references/workflow-core.md}"
AGENT="${2:-$REPO_ROOT/skills/aidex-conventions/agents/durability-arbiter.md}"

[ -f "$CANON" ] || { echo "FAIL: canon not found: $CANON" >&2; exit 1; }
[ -f "$AGENT" ] || { echo "FAIL: agent doc not found: $AGENT" >&2; exit 1; }

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
AGENT_TEXT="$(cat "$AGENT")"

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
    if ! printf '%s' "$text" | grep -Fiq -- "$m"; then
      echo "  FAIL: $label missing arbiter policy marker: \"$m\"" >&2
      FAIL=$((FAIL+1))
    fi
  done
}

check "canon ARBITER block" "$CANON_BLOCK"
check "durability-arbiter.md" "$AGENT_TEXT"

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "arbiter-policy-lockstep: OK — both hosts carry all ${#MARKERS[@]} markers (5 tiers + verdict enum)"
else
  echo "arbiter-policy-lockstep: $FAIL missing — a one-sided policy edit drifted the two hosts"
fi
[ "$FAIL" -eq 0 ]
