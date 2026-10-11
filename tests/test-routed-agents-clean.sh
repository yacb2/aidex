#!/usr/bin/env bash
# Routed agents (agents/<name>.md picked by description, not launched by a skill) ship in a
# public plugin, so they carry no owner-private content and name each other as `aidex:<name>`.
# Fails when a file listed in PORTED contains `BL-`, `/Users/`, `aidex_ws`, or a bare name of
# one of the 14 routed agents (a plugin agent is addressed `aidex:<name>`; the bare form
# resolves to nothing for a plugin user). The `name:` front-matter line is the one allowed bare use.
# To cover more files, append them to PORTED.
#
# Run with: bash tests/test-routed-agents-clean.sh   (ROOT=<dir> to point at another tree)

set -uo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

PORTED=(artifact-sonnet backlog-filer figure-sonnet gate-runner impl-sonnet lookup-sonnet research-sonnet)
ROUTED=(artifact-sonnet backlog-filer bugfix-opus figure-sonnet gate-runner impl-sonnet lookup-sonnet
        research-sonnet review-diff-opus smoke-sonnet synthesis-sonnet task-general
        verify-browser-opus verify-browser-sonnet)

for a in "${PORTED[@]}"; do
  f="$ROOT/agents/$a.md"
  [[ -f "$f" ]] || { err "agents/$a.md is missing"; continue; }
  body="$(grep -vE '^name: ' "$f")"
  while IFS= read -r hit; do err "agents/$a.md has private string: $hit"; done \
    < <(grep -nE 'BL-[0-9]|/Users/|aidex_ws' <<<"$body")
  for n in "${ROUTED[@]}"; do
    while IFS= read -r hit; do err "agents/$a.md names $n without aidex: prefix: $hit"; done \
      < <(grep -nE "(^|[^a-z0-9:-])$n([^a-z0-9-]|$)" <<<"$body")
  done
done

[[ $fail -eq 0 ]] && echo "PASS: ported routed agents carry no private strings and use aidex:<name>" || exit 1
