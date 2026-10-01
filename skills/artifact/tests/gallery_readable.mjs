// gallery_readable.mjs <page.html> — what the reader SEES of a gallery row,
// measured in a real browser at desktop and at 390 px: the rail and heading
// text, where the zoom label sits, whether the page overflows, where the
// highlight outline lands on the capture, the stacked order, and the outline in
// the zoom dialog. Prints one JSON object; test-gallery-readable.sh asserts.
import { createRequire } from 'node:module';
import path from 'node:path';

const { chromium } = createRequire(path.join(process.env.AIDEX_PLAYWRIGHT_MODULE, 'package.json'))('playwright');
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await page.goto('file://' + process.argv[2]);
const ROW = '[data-id="audit-users-list-menu-light-desktop"]';
const out = {};

out.desktop = await page.evaluate((ROW) => {
  const row = document.querySelector(ROW);
  const r = (el) => { const b = el.getBoundingClientRect(); return { l: b.left, t: b.top, w: b.width, h: b.height }; };
  const [before, after] = row.querySelectorAll('figure[data-tile]');
  const hl = after.querySelector('.gal-hl'), img = after.querySelector('img');
  const hb = r(hl), ib = r(img);
  const hlBefore = r(before.querySelector('.gal-hl')), ibBefore = r(before.querySelector('img'));
  const zoomAfter = getComputedStyle(after, '::after');
  const rail = [...document.querySelectorAll('#raillist .railitem')].map((a) => ({
    text: a.querySelector('.rt').textContent, rid: !!a.querySelector('.rid') }));
  return {
    heading: row.querySelector('h3').textContent,
    rail,
    stackedAbove: r(after).t >= r(before).t + r(before).h - 1 && Math.abs(r(after).w - r(before).w) < 2,
    frac: [(hb.l - ib.l) / ib.w, (hb.t - ib.t) / ib.h, hb.w / ib.w, hb.h / ib.h].map((v) => Math.round(v * 100)),
    fracBefore: [(hlBefore.l - ibBefore.l) / ibBefore.w, (hlBefore.t - ibBefore.t) / ibBefore.h].map((v) => Math.round(v * 100)),
    hlStyle: (() => { const c = getComputedStyle(hl); return { bg: c.backgroundColor, outline: c.outlineStyle,
      offset: parseFloat(c.outlineOffset), border: c.borderTopWidth }; })(),
    zoomLabelPosition: zoomAfter.position, zoomLabel: zoomAfter.content,
    figureBottom: r(after).t + r(after).h, imgBottom: ib.t + ib.h,
  };
}, ROW);

await page.click(ROW + ' figure[data-tile="after"]');
out.zoom = await page.evaluate(() => {
  const dlg = document.querySelector('dialog.kit-zoom');
  const hl = dlg.querySelector('.kit-hl-layer .gal-hl'), img = dlg.querySelector('.kit-compare > img');
  const hb = hl.getBoundingClientRect(), ib = img.getBoundingClientRect();
  return { open: dlg.open, boxes: dlg.querySelectorAll('.kit-hl-layer .gal-hl').length,
           frac: [(hb.left - ib.left) / ib.width, (hb.top - ib.top) / ib.height, hb.width / ib.width, hb.height / ib.height].map((v) => Math.round(v * 100)) };
});
await page.keyboard.press('Escape');

await page.setViewportSize({ width: 390, height: 800 });
out.phone = await page.evaluate(() => {
  const w = document.documentElement.clientWidth;
  const imgs = [...document.querySelectorAll('.consult-gallery .gal img')];
  return { overflow: document.documentElement.scrollWidth - w,
           imgPastEdge: imgs.some((i) => i.getBoundingClientRect().right > w + 1) };
});
console.log(JSON.stringify(out));
await browser.close();
