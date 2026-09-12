#!/usr/bin/env bash
# Collect every skill's native eval cases into the plugin's eval directory.
#
# `claude plugin eval --eval-dir <dir>` takes a directory NAME below the plugin,
# not a path, so the cases have to be materialised inside the repo root. They are
# copied — never moved — from `skills/<skill>/evals/native/<case>/` into
# `plugin-evals/<skill>--<case>/`, which is gitignored and rebuilt on every run.
#
# The DOUBLE dash in the collected name is load-bearing: it is what keeps
# `run-eval.sh --only plan` from also selecting `plan-exec` cases.
#
# This script no longer builds a copy of the tree. The repo IS the plugin
# (`.claude-plugin/plugin.json`, name `aidex`), so the eval targets the root as
# it ships. The two eval-only rewrites it used to apply are both gone: the
# `~/.claude/skills/` -> `${CLAUDE_PLUGIN_ROOT}/skills/` rewrite (the shipped tree
# carries the placeholder itself since the plugin migration) and the legacy
# trigger-eval probe strip (the blocks were deleted from all 18 SKILL.md — the
# native `tool_used: Skill` grader measures what they measured).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$REPO/plugin-evals"

rm -rf "$OUT"
mkdir -p "$OUT"

cases=0
for dir in "$REPO"/skills/*/evals/native/*/; do
  [ -d "$dir" ] || continue
  skill="$(basename "$(dirname "$(dirname "$(dirname "$dir")")")")"
  case_name="$(basename "$dir")"
  cp -R "$dir" "$OUT/${skill}--${case_name}"
  cases=$((cases + 1))
done

echo "eval dir:  $OUT (gitignored)"
echo "cases:     $cases"
[ "$cases" -gt 0 ] || { echo "ERROR: no cases under skills/*/evals/native/*/" >&2; exit 1; }
