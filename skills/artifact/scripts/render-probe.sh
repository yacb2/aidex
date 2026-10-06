#!/usr/bin/env bash
# render-probe.sh — the rendered-geometry gate that runs AFTER check-artifact.sh.
# check-artifact reads source; this loads the page headless (Playwright Chromium,
# 1280 and 390 px) and fails on what the reader sees: text over text, svg text
# outside its svg, content spilling out of or cut by its box, a table of one to three
# columns wider than the box it scrolls in, svg text under the 11 px floor at 390 px,
# an unfilled stroked rect whose edge crosses an svg text, a fixed control over
# body text, horizontal page scroll; and the three render contract classes
# (text-style-drift, figure-text-contrast in both schemes, svg-label-outside-its-box).
# text-style-drift's svg font-family half runs only under --contract text-style-drift:
# it stays out of the default run until the owner answers whether author font
# overrides in figures are allowed (no canon forbids them yet).
# The checks live in render-probe.mjs.
#
# Playwright is resolved from $AIDEX_PLAYWRIGHT_DIR (a directory holding
# node_modules/playwright), then from the global npm root. Neither having it is a
# failure with the install command, never a skip: a gate that passes because it
# could not look is the defect it exists to catch.
#
# Usage: render-probe.sh [--shots <dir>] [--contract <slug>] [--invariants] <page.html>...
#   --shots <dir>      also write <name>-1280.png and <name>-390.png (full page), viewport-height
#                      tiles <name>-<width>-t01.png ... and <name>-shots.json (tiles in order,
#                      the data-id items each holds, ids in page order, files written this run
#                      with a run stamp); stdout gets `SHOTS run=<stamp> files=<n>` and one
#                      `SHOT <path>` per file
#   --contract <slug>  run only that contract class; the last stdout line is
#                      `CONTRACT <slug> findings=<n>` (absent on a crash)
#   --invariants       a different mode: evaluate the rendered-DOM invariants of
#                      tests/invariants/catalog.md at 1280 px (no geometry checks). Prints one
#                      `INV <id> <page> <detail>` per violation and a last line
#                      `INVARIANTS pages=<n> violations=<m>`; exit 1 when m > 0.
# Exit 0 = clean. Exit 1 = at least one defect (each printed). Exit 2 = usage error.
# Exit 3 = Playwright or its Chromium missing (the install command is printed).
# Exit 4 = the probe crashed (any other launch error, a page that failed to load, an
# exception while measuring, no verdict within AIDEX_PROBE_DEADLINE seconds per page,
# default 60); the cause is on stderr. Never read as clean or as defects.

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
