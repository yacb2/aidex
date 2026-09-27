#!/usr/bin/env bash
# test-no-legacy-install-path.sh — aidex ships as a plugin since v1.0.0; the pre-plugin
# installer's ~/.aidex/ layout is gone, so a path into it dangles for every plugin user
# (BL-460: five shipped files still named it — a README command, an eval query, two
# comments and a canon paragraph). Only docs/retired/ may describe that layout; anywhere
# else, name the plugin-relative path (${CLAUDE_PLUGIN_ROOT}/…) or the repo path.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SELF="tests/$(basename "${BASH_SOURCE[0]}")"

hits="$(cd "$REPO_ROOT" && grep -rnI '~/\.aidex' . --exclude-dir=.git \
  | sed 's|^\./||' | grep -v '^docs/retired/' | grep -v "^$SELF:")"

if [ -n "$hits" ]; then
  printf 'FAIL: shipped files outside docs/retired name the retired ~/.aidex/ layout:\n%s\n' "$hits"
  exit 1
fi
echo "ok: no shipped file outside docs/retired names ~/.aidex/"
