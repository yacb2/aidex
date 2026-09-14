#!/usr/bin/env bash
# Every subagent definition sets `model:` explicitly (BL-403, 2026-09-14).
#
# An agent file without a model line inherits the orchestrator's model; on the Work Hours
# chain that turned Fable/Opus into the de facto default for mechanical subagents. The rule
# lives in references/04-model-tiering.md; this guard makes an omission fail the suite.
#
# Run with: bash skills/plan-exec/tests/test-agents-set-model.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
failures=0
for f in "$ROOT"/skills/*/agents/*.md; do
  case "$f" in *.eval.md) continue ;; esac   # eval logs, not definitions
  head -1 "$f" | grep -q '^---$' || { printf 'FAIL: %s has no front matter\n' "${f#"$ROOT"/}"; failures=$((failures+1)); continue; }
  awk 'NR>1 && /^---$/ {exit} NR>1 {print}' "$f" | grep -q '^model: *[a-z]' \
    || { printf 'FAIL: %s sets no model: (inherits the orchestrator model)\n' "${f#"$ROOT"/}"; failures=$((failures+1)); }
done
[[ $failures -eq 0 ]] && echo "PASS: every agent definition sets model:" || exit 1
