#!/usr/bin/env bash
# test-render-template.sh — render_template (_lib.sh) keeps the template's bytes outside
# the placeholders, its final newline included. It read with `$(cat)` and wrote with
# `printf '%s'`, so every rendered artifact (audits, loop/workflow specs, worktree
# overview) lost its final newline (conventions-scripts-c41).
#
# Layer: the shared function itself, sourced — every caller inherits the defect from here.
# Run with: bash skills/conventions/scripts/test-render-template.sh
set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_lib.sh"
set +e
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf 'title: {{SLUG}}\nbody\n' > "$TMP/nl.tpl"
( render_template "$TMP/nl.tpl" "$TMP/nl.out" SLUG=my-slug )
got="$(cat "$TMP/nl.out"; printf x)"
[[ "$got" == $'title: my-slug\nbody\nx' ]] || fail "a template ending in a newline rendered as: ${got%x}"

printf 'no newline {{SLUG}}' > "$TMP/raw.tpl"
( render_template "$TMP/raw.tpl" "$TMP/raw.out" SLUG=s )
got="$(cat "$TMP/raw.out"; printf x)"
[[ "$got" == 'no newline sx' ]] || fail "a template with no final newline gained or lost bytes: ${got%x}"

if [[ "$failures" -gt 0 ]]; then printf '\n%d check(s) failed\n' "$failures"; exit 1; fi
echo "OK — render_template keeps the final newline"
