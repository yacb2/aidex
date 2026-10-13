#!/usr/bin/env bash
# test-new-communication.sh — a scaffolded body.md ends exactly as its template ends,
# final newline included (BL-780). new-communication.sh kept a private render_template
# that read with `$(cat)` and wrote with `printf '%s'`, so meeting/call bodies (which go
# straight from render_template to disk) lost the template's final newline. sent/received
# were masked: inject_style rewrites the file through awk, which re-adds it.
#
# Layer: the script itself, run in a temp project — the defect is in which render_template
# the script ends up calling, so only the real entry point observes it.
# Run with: bash skills/comm/tests/test-new-communication.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)/new-communication.sh"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/.git"

# Both templates end in `-->\n`; the rendered body must end in exactly that, so a lost
# newline and a doubled one both fail.
for kind in meeting call sent received; do
  body="$(cd "$ROOT" && NO_COLOR=1 bash "$SCRIPT" "$kind" "tail-$kind" 2>/dev/null)" \
    || { fail "$kind: scaffolding exited non-zero"; continue; }
  tail="$(tail -c 4 "$body"; printf x)"
  [[ "$tail" == $'-->\nx' ]] || fail "$kind: body.md does not end with the template's '-->\\n' (last bytes: ${tail%x})"
done

if [[ $FAILURES -gt 0 ]]; then
  printf '\n%d kind(s) failed\n' "$FAILURES"
  exit 1
fi
printf 'OK — new-communication.sh keeps the template final newline for all four kinds\n'
