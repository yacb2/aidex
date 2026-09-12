#!/usr/bin/env bash
# Assemble the whole aidex skill suite into ONE plugin directory that
# `claude plugin eval` can target, and collect every skill's native eval cases
# into its eval dir.
#
# Why a wrapper: pointing `claude plugin eval` at a bare skill folder loads it as
# an inline plugin but never exposes the skill to the Skill tool. A plugin with a
# `skills/` subtree does expose it.
#
# Output: _tmp/evalkit/ (gitignored, disposable).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$REPO/_tmp/evalkit"

rm -rf "$OUT"
mkdir -p "$OUT/.claude-plugin" "$OUT/plugin-evals"
cp -R "$REPO/skills" "$OUT/skills"

cat > "$OUT/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "aidex-suite",
  "version": "0.1.0",
  "description": "Eval wrapper bundling the whole aidex skill suite"
}
JSON

# 1. Make cross-skill references resolvable inside the eval sandbox.
#    The shipped skills point at ~/.claude/skills/... — an absolute path into the
#    real HOME, which the eval sandbox replaces. ${CLAUDE_PLUGIN_ROOT} expands to
#    the wrapper dir and the Read succeeds (verified in a run trace).
#    This rewrite is eval-only: installed skills are NOT a plugin and have no
#    CLAUDE_PLUGIN_ROOT, so it must never be committed back into skills/.
rewritten=0
while IFS= read -r f; do
  if grep -q '~/.claude/skills/' "$f"; then
    perl -pi -e 's{~/\.claude/skills/}{\$\{CLAUDE_PLUGIN_ROOT\}/skills/}g' "$f"
    rewritten=$((rewritten + 1))
  fi
done < <(find "$OUT/skills" -name '*.md')

# 2. Strip the legacy trigger-eval probe block. It asks the model to run
#    printenv/touch as its first action, and models refuse it as a prompt
#    injection (observed in aidex-bugfix and aidex-decision runs). The native
#    `tool_used: Skill` grader replaces what it measured.
stripped=0
while IFS= read -r f; do
  if grep -q 'Trigger-eval probe (test-only)' "$f"; then
    perl -0pi -e 's/^> \*\*Trigger-eval probe \(test-only\)\.\*\*.*?\n\n//ms' "$f"
    stripped=$((stripped + 1))
  fi
done < <(find "$OUT/skills" -name 'SKILL.md')

# 3. Collect cases: skills/<skill>/evals/native/<case>/ -> plugin-evals/<skill>-<case>/
cases=0
for dir in "$REPO"/skills/*/evals/native/*/; do
  [ -d "$dir" ] || continue
  skill="$(basename "$(dirname "$(dirname "$(dirname "$dir")")")")"
  case_name="$(basename "$dir")"
  cp -R "$dir" "$OUT/plugin-evals/${skill}--${case_name}"
  cases=$((cases + 1))
done

echo "wrapper:   $OUT"
echo "skills:    $(find "$OUT/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
echo "rewritten: $rewritten file(s) with ~/.claude/skills/ paths"
echo "stripped:  $stripped probe block(s)"
echo "cases:     $cases"
[ "$cases" -gt 0 ] || { echo "ERROR: no cases under skills/*/evals/native/*/" >&2; exit 1; }
