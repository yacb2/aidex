#!/usr/bin/env bash
# test-diagram-centered.sh — a diagram narrower than the column sits centred in it
# (BL-675): at 1280 px the svg's left and right offsets inside its <figure> differ by
# at most 2 px, and the drawing is not upscaled (narrower than the figure).
# Layer: browser, because the cascade and flex auto margins decide, not a string.
# SKIP (exit 2) without Playwright, the way test-diagram-container-swap.sh does.
# Run with: bash skills/artifact/tests/test-diagram-centered.sh
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
[[ -n "$module" ]] || { echo "SKIP: Playwright not found (set AIDEX_PLAYWRIGHT_DIR or npm i -g playwright)"; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf '::: diagram {#d1 shape=row title="Narrow"}\na: x\nb: y\na -> b\n:::\n' > "$TMP/spec.md"
( cd "$TMP" && PYTHONDONTWRITEBYTECODE=1 python3 "$SCRIPTS/spec_build.py" "$TMP/spec.md" --title t -o "$TMP/page.html" ) >/dev/null 2>&1 \
  || { echo "FAIL: spec_build.py refused the narrow diagram spec" >&2; exit 1; }
cat > "$TMP/probe.mjs" <<'JS'
import { createRequire } from 'node:module';
const { chromium } = createRequire(process.argv[2] + '/package.json')('playwright');
const b = await chromium.launch();
const pg = await b.newPage({ viewport: { width: 1280, height: 900 } });
await pg.goto('file://' + process.argv[3]);
const m = await pg.evaluate(() => {
  const f = document.querySelector('figure#d1');
  const s = [...f.querySelectorAll('svg')].find(x => getComputedStyle(x).display !== 'none');
  const r = f.getBoundingClientRect(), q = s.getBoundingClientRect();
  return { left: q.left - r.left, right: r.right - q.right, svgW: q.width, figW: r.width };
});
await b.close();
const good = Math.abs(m.left - m.right) <= 2 && m.svgW < m.figW;
console.log(`${good ? 'ok' : 'FAIL'}: 1280px narrow diagram left=${m.left} right=${m.right} svg=${m.svgW} figure=${m.figW}`);
process.exit(good ? 0 : 1);
JS
node "$TMP/probe.mjs" "$module" "$TMP/page.html"
