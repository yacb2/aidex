#!/usr/bin/env bash
# The routed agents ported from the owner's ~/.claude/agents ship as public text: no backlog
# ids, no owner paths, no workspace name, and every other routed agent is named `aidex:<name>`
# (a bare name resolves to nothing for a plugin user). Rules stay; private evidence does not.
#
# Run with: bash tests/test-routed-agents-public-text.sh   (AGENTS_DIR=<dir> to point elsewhere)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
AGENTS_DIR="${AGENTS_DIR:-$ROOT/agents}"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

PORTED=(bugfix-opus review-diff-opus smoke-sonnet synthesis-sonnet task-general verify-browser-opus verify-browser-sonnet)
ROUTED=(artifact-sonnet backlog-filer bugfix-opus figure-sonnet gate-runner impl-sonnet lookup-sonnet
        research-sonnet review-diff-opus smoke-sonnet synthesis-sonnet task-general
        verify-browser-opus verify-browser-sonnet)
names="$(IFS='|'; echo "${ROUTED[*]}")"

for n in "${PORTED[@]}"; do
  f="$AGENTS_DIR/$n.md"
  [[ -f "$f" ]] || { err "$n.md missing under $AGENTS_DIR"; continue; }
  private="$(grep -nE 'BL-[0-9]|/Users/|aidex_ws' "$f")"
  [[ -z "$private" ]] || err "$n: private string: ${private:0:100}"
  # drop the `name:` line and every `aidex:<x>` mention, then look for a bare routed name
  bare="$(grep -v '^name: ' "$f" | sed -E 's/aidex:[a-z][a-z0-9-]*//g' | grep -nE "(^|[^a-z0-9-])($names)([^a-z0-9-]|\$)")"
  [[ -z "$bare" ]] || err "$n: bare routed-agent name (use aidex:<name>): ${bare:0:100}"
done

[[ $fail -eq 0 ]] && echo "PASS: ${#PORTED[@]} ported agents carry no private strings and name routed agents as aidex:<name>" || exit 1
