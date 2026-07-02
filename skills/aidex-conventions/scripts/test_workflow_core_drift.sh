#!/usr/bin/env bash
# test_workflow_core_drift.sh — drift-lock for the single-sourced Workflow blocks.
#
# Decision 2026-06-22-plan-exec-workflow-reusable-form (Q1): the Workflow tool forbids
# `import`, so each asset embeds the canonical blocks verbatim. This test extracts each
# named block (between `// === <NAME>:START ===` and `// === <NAME>:END ===`) from the
# canonical doc and from every asset, and fails on any byte mismatch.
#
# Two blocks are checked: CORE (the durability core) and ARBITER (the batch arbiter prompt,
# single-sourced in Phase 4 — see workflow-core.md "Canonical ARBITER block").
#
# Run:  bash skills/aidex-conventions/scripts/test_workflow_core_drift.sh
# Exit: 0 if every asset's blocks match canonical; 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CANON="$REPO_ROOT/skills/aidex-conventions/references/workflow-core.md"

# Extract the lines strictly between `// === <NAME>:START ===` and `// === <NAME>:END ===`
# (first occurrence). $1 = file, $2 = block name.
extract_block() {
  awk -v name="$2" '
    $0 == "// === " name ":START ===" { grab=1; next }
    $0 == "// === " name ":END ==="   { if (grab) exit }
    grab { print }
  ' "$1"
}

[ -f "$CANON" ] || { echo "FAIL: canonical doc not found: $CANON" >&2; exit 1; }

# Find every workflow asset across all skills (portable: macOS ships bash 3.2, no mapfile).
ASSETS=()
while IFS= read -r f; do
  ASSETS+=("$f")
done < <(find "$REPO_ROOT/skills" -type f -path '*/assets/workflows/*.workflow.js' | sort)
[ "${#ASSETS[@]}" -gt 0 ] || { echo "FAIL: no workflow assets found under skills/*/assets/workflows/" >&2; exit 1; }

BLOCKS=("CORE" "ARBITER")
PASS=0
FAIL=0

for block in "${BLOCKS[@]}"; do
  canon_block="$(extract_block "$CANON" "$block")"
  if [ -z "$canon_block" ]; then
    echo "FAIL: no $block block between markers in $CANON" >&2
    FAIL=$((FAIL+1))
    continue
  fi
  for asset in "${ASSETS[@]}"; do
    rel="${asset#"$REPO_ROOT"/}"
    block_text="$(extract_block "$asset" "$block")"
    if [ -z "$block_text" ]; then
      echo "  FAIL: $rel — no $block block between markers" >&2
      FAIL=$((FAIL+1))
      continue
    fi
    if diff <(printf '%s' "$canon_block") <(printf '%s' "$block_text") >/dev/null; then
      echo "  ok:   $rel [$block]"
      PASS=$((PASS+1))
    else
      echo "  FAIL: $rel — $block drifted from canonical (run diff to inspect)" >&2
      diff <(printf '%s' "$canon_block") <(printf '%s' "$block_text") | sed 's/^/        /' >&2
      FAIL=$((FAIL+1))
    fi
  done
done

# Structural assertions (director pattern, 2026-07-02): every asset that builds a
# plan-phase implementer must use WORK_SCHEMA (so runPhase's director/pending_actions
# paths actually receive structured reports), and the canonical CORE must carry the
# director + publication carriers.
if ! grep -q "blocked_reason" <(extract_block "$CANON" "CORE") || \
   ! grep -q "pending_actions" <(extract_block "$CANON" "CORE"); then
  echo "  FAIL: canonical CORE lost the director carriers (blocked_reason / pending_actions)" >&2
  FAIL=$((FAIL+1))
else
  echo "  ok:   canonical CORE carries director + pending_actions paths"
  PASS=$((PASS+1))
fi
for asset in "${ASSETS[@]}"; do
  rel="${asset#"$REPO_ROOT"/}"
  # Only assets that define a plan-phase implementer closure are bound to WORK_SCHEMA.
  if grep -qE "makeImplement|implement: \(feedback" "$asset"; then
    if grep -q "schema: WORK_SCHEMA" "$asset"; then
      echo "  ok:   $rel [implementer uses WORK_SCHEMA]"
      PASS=$((PASS+1))
    else
      echo "  FAIL: $rel — implementer closure without schema: WORK_SCHEMA (director pattern broken)" >&2
      FAIL=$((FAIL+1))
    fi
  fi
done

echo ""
echo "drift-lock: $PASS ok, $FAIL drifted (canonical: skills/aidex-conventions/references/workflow-core.md)"
[ "$FAIL" -eq 0 ]
