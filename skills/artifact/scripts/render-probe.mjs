// render-probe.mjs — rendered-geometry defects a reader sees and check-artifact cannot
// (check-artifact reads source, not layout). Run through render-probe.sh, which resolves
// Playwright and passes its module directory in AIDEX_PLAYWRIGHT_MODULE.
//
// Each page is loaded headless at 1280 and 390 px (dark scheme) and checked for:
//   text-overlap      two texts drawn over each other
//   svg-text-clipped  svg text outside its svg viewport (clipped axis labels)
//   content-spills    a box whose content spills out of it (visible overflow)
//   content-cut       a box whose content is cut by it (hidden overflow)
//   fixed-over-text   a position:fixed control drawn over page text (any scroll position)
//   page-hscroll      the page scrolls horizontally
//
// Promoted from .context/experiments/2026-09-24-artifact-route-ab/probe.mjs (aidex_ws).
// Output: one JSON line per page and width, then a human-readable defect list.
// Exit 0 = clean, 1 = at least one defect, 2 = usage, 3 = Playwright or its browser missing,
// 4 = the probe crashed (a launch error other than a missing browser, a page that failed
// to load, an exception while measuring). A crash is never reported as a defect or clean.

import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const USAGE = 'usage: render-probe.sh [--shots <dir>] <page.html>...';
const args = process.argv.slice(2);
let shots = null;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--shots') { shots = args[++i]; if (!shots) { console.error(USAGE); process.exit(2); } }
  else if (args[i].startsWith('-')) { console.error(USAGE); process.exit(2); }
  else files.push(args[i]);
}
if (!files.length) { console.error(USAGE); process.exit(2); }
for (const f of files) if (!fs.existsSync(f)) { console.error(`render-probe: no such file: ${f}`); process.exit(2); }

let chromium;
try {
  ({ chromium } = createRequire(path.join(process.env.AIDEX_PLAYWRIGHT_MODULE || '.', 'package.json'))('playwright'));
} catch (e) {
  if (e && e.code === 'MODULE_NOT_FOUND') {
    console.error('render-probe: Playwright not found. Install it with: npm i -g playwright');
    process.exit(3);
  }
  console.error(`render-probe: CRASH loading Playwright: ${String(e && e.message || e).split('\n')[0]}`);
  process.exit(4);
}

const check = () => {
  const vis = el => { const s = getComputedStyle(el); return s.display !== 'none' && s.visibility !== 'hidden' && +s.opacity > 0.05; };
  // the class attribute, not .className: on an svg element that is an object, not a string
  const name = el => { const c = (el.getAttribute('class') || '').trim(); return el.tagName.toLowerCase() + (c ? '.' + c.split(/\s+/)[0] : '') + ' "' + (el.textContent || '').trim().slice(0, 40) + '"'; };
  const fixedAncestor = el => { for (let e = el; e && e !== document.body; e = e.parentElement) if (getComputedStyle(e).position === 'fixed') return e; return null; };
  // The consultation copy bar. Below the kit's 62rem breakpoint the kit turns `.rail`
  // into a bar pinned to the viewport bottom (components.css: `.rail { position: sticky;
  // bottom: 0; background: var(--paper) }`, "a bottom bar carrying the copy button"). Body
  // text scrolls UNDER that opaque bar by design, so its geometry intersects whatever text
  // is at the viewport bottom at the sampled scroll position, while the reader sees the
  // bar, not two texts on top of each other (verified on the C pages' 390 px screenshots).
  // Only the bottom-pinned form is exempt: in the desktop column the rail pins at the
  // top and never sits over body text, so an overlap there is still a defect.
  const inStickyBottomBar = el => { const r = el.closest('.rail'); if (!r) return false; const s = getComputedStyle(r); return s.position === 'sticky' && s.bottom !== 'auto'; };
  const out = [];
  // text boxes: one per element that owns a non-empty text node
  const boxes = [];
  const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n; (n = tw.nextNode());) {
    if (!n.textContent.trim()) continue;
    const el = n.parentElement; if (!el || !vis(el) || el.closest('script,style,noscript,[hidden],details:not([open]) > :not(summary)')) continue;
    const r = document.createRange(); r.selectNodeContents(n);
    for (const b of r.getClientRects()) if (b.width > 1 && b.height > 1) boxes.push({ el, b, fixed: fixedAncestor(el), bar: inStickyBottomBar(el) });
  }
  const sy = scrollY;
  // 1. two texts drawn over each other. A fixed text against a non-fixed one is left to
  // check 4, which names that collision once as fixed-over-text instead of twice; two
  // fixed texts colliding (two labels inside one toolbar, or two fixed controls) stay here.
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
    const a = boxes[i], c = boxes[j]; if (a.el === c.el || a.el.contains(c.el) || c.el.contains(a.el)) continue;
    if (!a.fixed !== !c.fixed || a.bar !== c.bar) continue;
    const w = Math.min(a.b.right, c.b.right) - Math.max(a.b.left, c.b.left), h = Math.min(a.b.bottom, c.b.bottom) - Math.max(a.b.top, c.b.top);
    if (w > 2 && h > 2 && w * h > 0.25 * Math.min(a.b.width * a.b.height, c.b.width * c.b.height))
      out.push({ kind: 'text-overlap', a: name(a.el), b: name(c.el), y: Math.round(a.b.top + sy) });
  }
  // 2. svg text outside its svg viewport (clipped axis labels)
  for (const t of document.querySelectorAll('svg text')) {
    const s = t.ownerSVGElement; if (!s || !vis(t)) continue; const a = t.getBoundingClientRect(), b = s.getBoundingClientRect();
    if (a.width && (a.left < b.left - 1 || a.right > b.right + 1 || a.top < b.top - 1 || a.bottom > b.bottom + 1))
      out.push({ kind: 'svg-text-clipped', a: name(t), y: Math.round(a.top + sy) });
  }
  // 3. a box whose content spills out of it (visible overflow) or is cut by it (hidden
  // overflow). One wide child makes every ancestor up to the page overflow by the same
  // amount; a box is not reported when a descendant carries the SAME kind, because the
  // innermost is the one to fix. A different kind is its own defect: a parent that cuts
  // its text (content-cut) is reported even when a child also spills.
  const spilling = [];
  for (const el of document.body.querySelectorAll('*')) {
    if (!vis(el) || el.closest('svg') || !el.textContent.trim()) continue;
    const s = getComputedStyle(el); if (s.display.startsWith('inline') && s.display !== 'inline-block') continue;
    if (/(auto|scroll)/.test(s.overflowX + s.overflowY)) continue;
    const dx = el.scrollWidth - el.clientWidth, dy = el.scrollHeight - el.clientHeight;
    if (el.clientWidth && (dx > 3 || (s.overflowY !== 'visible' && dy > 3)))
      spilling.push({ el, x: { kind: s.overflowX === 'visible' ? 'content-spills' : 'content-cut', a: name(el), dx, dy, y: Math.round(el.getBoundingClientRect().top + sy) } });
  }
  for (const { el, x } of spilling) if (!spilling.some(o => o.el !== el && el.contains(o.el) && o.x.kind === x.kind)) out.push(x);
  // 4. a fixed control drawn over page text. Both the container's own rect and each fixed
  // text box are tested. The container rect alone misses a label hanging out of a 0-height
  // (or 0x0) fixed strip; the text boxes alone miss the opaque padding of a pill such as
  // the kit theme toggle, which covers a line of body text with no letter of its own over
  // it (6 such collisions on the 2026-09-24 A/B pages). One line per fixed container.
  const areas = [];
  for (const el of document.body.querySelectorAll('*')) {
    if (getComputedStyle(el).position !== 'fixed' || !vis(el)) continue; const r = el.getBoundingClientRect();
    if (r.width > 1 && r.height > 1) areas.push({ owner: el, label: el, r });
  }
  for (const f of boxes) if (f.fixed) areas.push({ owner: f.fixed, label: f.el, r: f.b });
  const hit = new Set();
  for (const { owner, label, r } of areas) {
    if (hit.has(owner)) continue;
    const t = boxes.find(o => !o.fixed && o.b.right > r.left && o.b.left < r.right && o.b.bottom > r.top && o.b.top < r.bottom);
    if (t) { hit.add(owner); out.push({ kind: 'fixed-over-text', a: name(label), b: name(t.el) }); }
  }
  // 5. horizontal page scroll, naming the innermost element that reaches past the viewport
  // (an svg counts as one element: its shapes are not what the author sized). Content
  // inside a box that clips or scrolls on x cannot widen the page, so it is not a suspect.
  if (document.scrollingElement.scrollWidth > innerWidth + 1) {
    const clipped = e => { for (let a = e.parentElement; a && a !== document.body; a = a.parentElement) if (getComputedStyle(a).overflowX !== 'visible') return true; return false; };
    const wide = [...document.body.querySelectorAll('*')].filter(e => !(e.parentElement && e.parentElement.closest('svg')) && vis(e) && e.getBoundingClientRect().right > innerWidth + 1 && !clipped(e));
    const culprit = wide.find(e => !wide.some(o => o !== e && e.contains(o)));
    out.push({ kind: 'page-hscroll', a: culprit ? name(culprit) : undefined, dx: document.scrollingElement.scrollWidth - innerWidth });
  }
  return out;
};

let browser;
try { browser = await chromium.launch(); }
catch (e) {
  const msg = String(e && e.message || e);
  // Playwright's own wording for a browser that was never downloaded
  if (/Executable doesn't exist/.test(msg)) {
    console.error('render-probe: Playwright is installed but its Chromium is not. Install it with: npx playwright install chromium');
    process.exit(3);
  }
  console.error(`render-probe: CRASH launching Chromium: ${msg.split('\n')[0]}`);
  process.exit(4);
}
if (shots) fs.mkdirSync(shots, { recursive: true });
const report = [];
let current = '';
try {
for (const f of files) for (const width of [1280, 390]) {
  current = `${f} @${width}px`;
  const page = await browser.newPage({ viewport: { width, height: 900 }, colorScheme: 'dark' });
  await page.goto('file://' + path.resolve(f)); await page.waitForTimeout(400);
  const d = await page.evaluate(check);
  // the fixed-control check is scroll-dependent: sample the page at four scroll positions
  const seen = new Set(d.filter(x => x.kind === 'fixed-over-text').map(x => x.a + '|' + x.b));
  const H = await page.evaluate(() => document.scrollingElement.scrollHeight);
  for (const y of [H * 0.25, H * 0.5, H * 0.75]) {
    await page.evaluate(y => scrollTo(0, y), y); await page.waitForTimeout(50);
    for (const x of await page.evaluate(check)) if (x.kind === 'fixed-over-text' && !seen.has(x.a + '|' + x.b)) { seen.add(x.a + '|' + x.b); d.push(x); }
  }
  if (shots) {
    await page.evaluate(() => scrollTo(0, 0));
    await page.screenshot({ path: path.join(shots, `${path.basename(f, path.extname(f))}-${width}.png`), fullPage: true });
  }
  const kinds = {}; for (const x of d) kinds[x.kind] = (kinds[x.kind] || 0) + 1;
  console.log(JSON.stringify({ file: path.basename(f), width, kinds, defects: d }));
  report.push({ file: f, width, d });
  await page.close();
}
} catch (e) {
  console.error(`render-probe: CRASH on ${current}: ${String(e && e.message || e).split('\n')[0]}`);
  await browser.close().catch(() => {});
  process.exit(4);
}
await browser.close();

const total = report.reduce((n, r) => n + r.d.length, 0);
console.log('');
for (const { file, width, d } of report) for (const x of d)
  console.log(`DEFECT ${path.basename(file)} @${width}px ${x.kind}: ${[x.a, x.b].filter(Boolean).join(' over ') || ''}${x.dx ? ` (dx=${x.dx}${x.dy ? `, dy=${x.dy}` : ''})` : ''}${x.y !== undefined ? ` at y=${x.y}` : ''}`);
console.log(total ? `render-probe: ${total} defect(s) in ${files.length} page(s)` : `render-probe: clean (${files.length} page(s), 1280 and 390 px)`);
process.exit(total ? 1 : 0);
