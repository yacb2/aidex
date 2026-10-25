#!/usr/bin/env bash
# test-plugin-source-folder.sh — the plugin audit reads each plugin's agents, commands and
# manifest from the folder the plugin actually LOADS from, never from the plugin cache.
#
# Regression (BL-883): plugin-auditor globbed
# `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/agents/*.md` and validated
# `installPath`. For a plugin installed from a directory source (aidex since 2026-09-24)
# both are the stale cache copy: installed_plugins.json records
# installPath = cache/aidex/aidex/1.4.0 while the plugin loads from the checkout. The only
# record of the loaded folder is `readFromFolder` in `claude plugin list --json`
# (installPath stays the right answer when readFromFolder is absent). The context-budget
# reference carried the same cache glob.
#
# Each row: file, start regex, end regex (first match AFTER the start line closes the
# section), literal the section must contain, literal it must not contain ("-" = none).
#
# Run with: bash tests/test-plugin-source-folder.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# file  start-regex  end-regex  required-literal  forbidden-literal ("-" = none)   (five words per row)
ROWS=(
  agents/plugin-auditor.md                     '^## Inputs'                      '^## '  readFromFolder  plugins/cache/
  agents/plugin-auditor.md                     '^### 1\. '                       '^### ' readFromFolder  -
  agents/plugin-auditor.md                     '^### 1\. '                       '^### ' installed_plugins.json  -
  agents/plugin-auditor.md                     '^### 2\. '                       '^### ' '`dir`'         installPath
  agents/plugin-auditor.md                     '^### 3\. '                       '^### ' '`dir`'         -
  agents/plugin-auditor.md                     '^### 7\. '                       '^### ' '`dir`'         installPath
  skills/aidex/references/05-context-budget.md '^- Attribute the row to plugins'  '^- '   readFromFolder  plugins/cache/
)

n=0
for ((i = 0; i < ${#ROWS[@]}; i += 5)); do
  file="${ROWS[i]}" start="${ROWS[i+1]}" end="${ROWS[i+2]}" need="${ROWS[i+3]}" forbid="${ROWS[i+4]}"
  n=$((n + 1))
  path="$REPO_ROOT/$file"
  [[ -f "$path" ]] || { fail "row $n: $file not found"; continue; }
  section="$(S="$start" E="$end" awk 'on && $0 ~ ENVIRON["E"] {exit} on {print} !on && $0 ~ ENVIRON["S"] {on=1; print}' "$path")"
  [[ -n "$section" ]] || { fail "row $n: anchor /$start/ matches nothing in $file"; continue; }
  printf '%s' "$section" | grep >/dev/null -F -- "$need" \
    || fail "row $n: $file section /$start/ lacks $need: ${section:0:160}"
  if [[ "$forbid" != "-" ]] && printf '%s' "$section" | grep >/dev/null -F -- "$forbid"; then
    fail "row $n: $file section /$start/ still reads $forbid (the stale cache for a directory-source plugin)"
  fi
done

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — $n plugin-folder rows resolve from readFromFolder, else installPath"
