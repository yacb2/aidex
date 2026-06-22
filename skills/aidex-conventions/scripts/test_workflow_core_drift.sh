#!/usr/bin/env bash
# test_workflow_core_drift.sh — drift-lock for the single-sourced Workflow CORE.
#
# Decision 2026-06-22-plan-exec-workflow-reusable-form (Q1): the Workflow tool forbids
# `import`, so each asset embeds the canonical CORE block verbatim. This test extracts the
# block between // === CORE:START === and // === CORE:END === from the canonical doc and
# from every asset, and fails on any byte mismatch (whitespace-sensitive first cut;
# normalization is a flagged Phase-3 refinement).
#
# Run:  bash skills/aidex-conventions/scripts/test_workflow_core_drift.sh
# Exit: 0 if every asset's CORE matches canonical; 1 otherwise.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CANON="$REPO_ROOT/skills/aidex-conventions/references/workflow-core.md"

# Extract the lines strictly between the two markers (first occurrence).
extract_core() {
  awk '
    /\/\/ === CORE:START ===/ { grab=1; next }
    /\/\/ === CORE:END ===/   { if (grab) exit }
    grab { print }
  ' "$1"
}

[ -f "$CANON" ] || { echo "FAIL: canonical CORE not found: $CANON" >&2; exit 1; }

CANON_BLOCK="$(extract_core "$CANON")"
[ -n "$CANON_BLOCK" ] || { echo "FAIL: no CORE block between markers in $CANON" >&2; exit 1; }

# Find every workflow asset across all skills (portable: macOS ships bash 3.2, no mapfile).
ASSETS=()
while IFS= read -r f; do
  ASSETS+=("$f")
done < <(find "$REPO_ROOT/skills" -type f -path '*/assets/workflows/*.workflow.js' | sort)
[ "${#ASSETS[@]}" -gt 0 ] || { echo "FAIL: no workflow assets found under skills/*/assets/workflows/" >&2; exit 1; }

PASS=0
FAIL=0
for asset in "${ASSETS[@]}"; do
  rel="${asset#"$REPO_ROOT"/}"
  block="$(extract_core "$asset")"
  if [ -z "$block" ]; then
    echo "  FAIL: $rel — no CORE block between markers" >&2
    FAIL=$((FAIL+1))
    continue
  fi
  if diff <(printf '%s' "$CANON_BLOCK") <(printf '%s' "$block") >/dev/null; then
    echo "  ok:   $rel"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $rel — CORE drifted from canonical (run diff to inspect)" >&2
    diff <(printf '%s' "$CANON_BLOCK") <(printf '%s' "$block") | sed 's/^/        /' >&2
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "drift-lock: $PASS ok, $FAIL drifted (canonical: skills/aidex-conventions/references/workflow-core.md)"
[ "$FAIL" -eq 0 ]
