#!/usr/bin/env bash
# The routed agents (agents/<name>.md picked by description, not launched by a skill) ship in a
# public plugin as public text: no backlog ids, no owner paths, no workspace name, and every
# routed agent is named `aidex:<name>` (a bare name resolves to nothing for a plugin user; the
# match is case-insensitive, so `Impl-sonnet` at a sentence start fails too). The `name:`
# front-matter line is the one allowed bare use.
#
# ROUTED is checked against the files: it must equal the set of agents/*.md whose description
# starts "Use ", so a 15th routed agent cannot escape the scan.
#
# Run with: bash tests/test-routed-agents-public-text.sh   (AGENTS_DIR=<dir> to point elsewhere)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
AGENTS_DIR="${AGENTS_DIR:-$ROOT/agents}"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

ROUTED=(artifact-sonnet backlog-filer bugfix-opus figure-sonnet gate-runner impl-sonnet lookup-sonnet
        research-sonnet review-diff-opus smoke-sonnet synthesis-sonnet task-general
        verify-browser-opus verify-browser-sonnet)
names="$(IFS='|'; echo "${ROUTED[*]}")"

# the routed list equals the agents whose description starts "Use "
declared="$(grep -lE '^description: Use ' "$AGENTS_DIR"/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.md$//' | sort)"
listed="$(printf '%s\n' "${ROUTED[@]}" | sort)"
[[ "$declared" == "$listed" ]] || err "ROUTED differs from the agents whose description starts 'Use ': $(diff <(echo "$listed") <(echo "$declared") | grep '^[<>]' | tr '\n' ' ')"

for n in "${ROUTED[@]}"; do
  f="$AGENTS_DIR/$n.md"
  [[ -f "$f" ]] || { err "$n.md missing under $AGENTS_DIR"; continue; }
  private="$(grep -nE 'BL-[0-9]|/Users/|aidex_ws' "$f")"
  [[ -z "$private" ]] || err "$n: private string: ${private:0:100}"
  # drop the `name:` line and every `aidex:<x>` mention, then look for a bare routed name
  bare="$(grep -v '^name: ' "$f" | sed -E 's/aidex:[a-zA-Z][a-zA-Z0-9-]*//g' | grep -niE "(^|[^a-z0-9-])($names)([^a-z0-9-]|\$)")"
  [[ -z "$bare" ]] || err "$n: bare routed-agent name (use aidex:<name>): ${bare:0:100}"
done

[[ $fail -eq 0 ]] && echo "PASS: ${#ROUTED[@]} routed agents carry no private strings and name routed agents as aidex:<name>" || exit 1
