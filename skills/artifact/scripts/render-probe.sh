#!/usr/bin/env bash
# render-probe.sh — the rendered-geometry gate that runs AFTER check-artifact.sh.
# check-artifact reads source; this loads the page headless (Playwright Chromium,
# 1280 and 390 px) and fails on what the reader sees: text over text, svg text
# outside its svg, content spilling out of or cut by its box, a fixed control over
# body text, horizontal page scroll. The checks live in render-probe.mjs.
#
# Playwright is resolved from $AIDEX_PLAYWRIGHT_DIR (a directory holding
# node_modules/playwright), then from the global npm root. Neither having it is a
# failure with the install command, never a skip: a gate that passes because it
# could not look is the defect it exists to catch.
#
# Usage: render-probe.sh [--shots <dir>] <page.html>...
#   --shots <dir>  also write <name>-1280.png and <name>-390.png, full page
# Exit 0 = clean. Exit 1 = at least one defect (each printed). Exit 2 = usage error.
# Exit 3 = Playwright or its Chromium missing (the install command is printed).
# Exit 4 = the probe crashed (any other launch error, a page that failed to load, an
# exception while measuring); the cause is on stderr. Never read as clean or as defects.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

command -v node >/dev/null 2>&1 || {
  echo "render-probe: node not found. Install Node.js, then: npm i -g playwright" >&2
  exit 3
}

module=""
if [[ -n "${AIDEX_PLAYWRIGHT_DIR:-}" && -f "$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright/package.json" ]]; then
  module="$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright"
else
  global="$(npm root -g 2>/dev/null || true)"
  [[ -n "$global" && -f "$global/playwright/package.json" ]] && module="$global/playwright"
fi
if [[ -z "$module" ]]; then
  echo "render-probe: Playwright not found (AIDEX_PLAYWRIGHT_DIR, then the global npm root). Install it with: npm i -g playwright" >&2
  exit 3
fi

AIDEX_PLAYWRIGHT_MODULE="$(dirname "$module")" exec node "$SCRIPT_DIR/render-probe.mjs" "$@"
