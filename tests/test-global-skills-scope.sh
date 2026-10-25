#!/usr/bin/env bash
# test-global-skills-scope.sh — every place the audit lists the GLOBAL skills it scans
# names ~/.claude/skills/, where the user's own global skills live.
#
# Regression (BL-868 siblings): the plugin path sweep (75f77955) rewrote every
# `~/.claude/skills/` to `${CLAUDE_PLUGIN_ROOT}/skills/`. Where the old path meant aidex's
# own install location that was right; where it meant "the user's global skills" it
# silently dropped ~/.claude/skills/ from the audit. The plugin root stays a legitimate
# scan target (aidex's own skills), so the contract is "~/.claude/skills/ is listed", not
# "the plugin root is absent". symlink-checker's row lives in test-symlink-checker.sh.
#
# Each row: file, start regex, end regex (first match AFTER the start line closes the
# section), literal the section must contain. A missing file or an anchor that matches
# nothing is its own FAIL, so a reworded heading cannot turn a row into a silent pass.
#
# Run with: bash tests/test-global-skills-scope.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# file  start-regex  end-regex  required-literal   (four words per row)
ROWS=(
  agents/skills-auditor.md                     '^## Scopes to Scan'                       '^## '        '`~/.claude/skills/`'
  agents/skills-auditor.md                     '^- \*\*\[SG\]'                           '^- \*\*\['   '`~/.claude/skills/`'
  skills/aidex/SKILL.md                        '^\| \*\*Skills\*\* \|'                  '^\|'         '`~/.claude/skills/`'
  skills/aidex/SKILL.md                        '^Check for:'                              '^```'        '~/.claude/skills/'
  skills/aidex/references/05-context-budget.md '^### 6\. Stack-irrelevant global skills'  '^##'         '`~/.claude/skills/`'
)

n=0
for ((i = 0; i < ${#ROWS[@]}; i += 4)); do
  file="${ROWS[i]}" start="${ROWS[i+1]}" end="${ROWS[i+2]}" need="${ROWS[i+3]}"
  n=$((n + 1))
  path="$REPO_ROOT/$file"
  [[ -f "$path" ]] || { fail "row $n: $file not found"; continue; }
  section="$(S="$start" E="$end" awk 'on && $0 ~ ENVIRON["E"] {exit} on {print} !on && $0 ~ ENVIRON["S"] {on=1; print}' "$path")"
  [[ -n "$section" ]] || { fail "row $n: anchor /$start/ matches nothing in $file"; continue; }
  printf '%s' "$section" | grep >/dev/null -F -- "$need" \
    || fail "row $n: $file section /$start/ does not list $need (the user's global skills): ${section:0:160}"
done

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — $n global-skills scan lists name ~/.claude/skills/"
