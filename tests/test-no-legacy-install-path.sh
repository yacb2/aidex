#!/usr/bin/env bash
# test-no-legacy-install-path.sh — aidex ships as a plugin since v1.0.0; the pre-plugin
# installer's ~/.aidex/ layout is gone, so a path into it dangles for every plugin user
# (BL-460: five shipped files still named it — a README command, an eval query, two
# comments and a canon paragraph). Only docs/retired/ may describe that layout; anywhere
# else, name the plugin-relative path (${CLAUDE_PLUGIN_ROOT}/…) or the repo path.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SELF="tests/$(basename "${BASH_SOURCE[0]}")"

# git grep: one pass, and --exclude-standard keeps gitignored scratch dirs (_tmp/, plugin-evals/)
# out of the scan; --no-index reads the working tree, so it needs no committed state.
hits="$(git -C "$REPO_ROOT" grep --no-index --exclude-standard -nIE '~/\.aidex' -- . ':(exclude)docs/retired' ":(exclude)$SELF")"

# Sentinel: a scan that saw no file proves nothing (ROOT under a gitignored dir blanks it).
git -C "$REPO_ROOT" grep --no-index --exclude-standard -lI . -- . >/dev/null \
  || { echo "FAIL: scanned no files under $REPO_ROOT"; exit 1; }

if [ -n "$hits" ]; then
  printf 'FAIL: shipped files outside docs/retired name the retired ~/.aidex/ layout:\n%s\n' "$hits"
  exit 1
fi
echo "ok: no shipped file outside docs/retired names ~/.aidex/"
