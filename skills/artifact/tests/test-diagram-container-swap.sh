#!/usr/bin/env bash
# test-diagram-container-swap.sh — two wrapped-row figures of different widths on
# one page (BL-525), in headless Chromium at 1440 and 1280: every figure has
# exactly one svg whose computed display is not none. Guards the container-query
# swap of `dg-full` against a later figure's default-hide beating an earlier
# figure's show (the earlier one then rendered nothing). Layer: browser, because
# the CSS cascade is what decides; no string test can see source-order wins.
#
# The page is built with spec_build.py, so it carries today's kit and today's
# `full_css`. Needs Playwright the way render-probe.sh finds it; without it the
# test prints SKIP and exits 2 (run-all.sh reports a skip, never a pass).
#
# Run with: bash skills/artifact/tests/test-diagram-container-swap.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS="$(cd "$HERE/../scripts" && pwd -P)"

module=""
if [[ -n "${AIDEX_PLAYWRIGHT_DIR:-}" && -f "$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright/package.json" ]]; then
  module="$AIDEX_PLAYWRIGHT_DIR/node_modules/playwright"
else
  g="$(npm root -g 2>/dev/null || true)"
  [[ -n "$g" && -f "$g/playwright/package.json" ]] && module="$g/playwright"
fi
if [[ -z "$module" ]]; then
  echo "SKIP: Playwright not found (set AIDEX_PLAYWRIGHT_DIR or npm i -g playwright)"
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Figure A: one row ~948 wide (wrapped at 720). Figure B: one row ~730.
python3 - "$TMP/spec.md" <<'PY'
import sys
a = ["m%d: paso número %d" % (i, i) for i in range(6)] \
    + ["m%d -> m%d" % (i, i + 1) for i in range(5)]
b = ["a: " + "W" * 44, "b: y", "a -> b"]
fence = lambda i, body: "::: diagram {#d%d shape=row title=\"F%d\"}\n%s\n:::\n" % (i, i, "\n".join(body))
open(sys.argv[1], "w", encoding="utf-8").write(fence(1, a) + "\n" + fence(2, b))
PY
( cd "$TMP" && PYTHONDONTWRITEBYTECODE=1 python3 "$SCRIPTS/spec_build.py" "$TMP/spec.md" --title swap -o "$TMP/page.html" ) >/dev/null 2>&1 \
  || { echo "FAIL: spec_build.py refused the two-figure spec" >&2; exit 1; }

cat > "$TMP/probe.mjs" <<'JS'
import { createRequire } from 'node:module';
const { chromium } = createRequire(process.argv[2] + '/package.json')('playwright');
const browser = await chromium.launch();
let bad = 0;
for (const width of [1440, 1280]) {
  const page = await browser.newPage({ viewport: { width, height: 900 } });
  await page.goto('file://' + process.argv[3]);
  const rows = await page.evaluate(() => [...document.querySelectorAll('figure')].map(f => ({
    id: f.id,
    visible: [...f.querySelectorAll('svg')].filter(s => getComputedStyle(s).display !== 'none')
      .map(s => s.getAttribute('class')),
    total: f.querySelectorAll('svg').length,
  })));
  for (const r of rows) {
    // The drawing each figure must show: d1's one row (949) fits the 952
    // column at 1440 but not the 888 one at 1280; d2's (730) fits both.
    const want = { 1440: { d1: 'dg-w949', d2: 'dg-w730' },
                   1280: { d1: 'dg-wide', d2: 'dg-w730' } }[width][r.id];
    const good = r.visible.length === 1
      && r.visible[0].split(' ').includes(want);
    if (!good) bad++;
    console.log(`${good ? '  ok' : '  FAIL'}: ${width}px figure ${r.id}: ${r.visible.length} of ${r.total} svgs shown (${r.visible.join(', ')}), want ${want}`);
  }
  if (rows.length !== 2) { bad++; console.log(`  FAIL: ${width}px expected 2 figures, got ${rows.length}`); }
  await page.close();
}
await browser.close();
process.exit(bad ? 1 : 0);
JS
node "$TMP/probe.mjs" "$module" "$TMP/page.html"
