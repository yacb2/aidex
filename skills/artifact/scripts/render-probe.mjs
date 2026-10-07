// render-probe.mjs — rendered-geometry defects a reader sees and check-artifact cannot
// (check-artifact reads source, not layout). Run through render-probe.sh, which resolves
// Playwright and passes its module directory in AIDEX_PLAYWRIGHT_MODULE.
//
// Each page is loaded headless at 1280 and 390 px (dark scheme) and checked for:
//   text-overlap      two texts drawn over each other
//   svg-text-clipped  svg text outside its svg viewport (clipped axis labels)
//   svg-text-small    svg text drawn under 10.5 px on screen at 390 px (the kit's floor is
//                     11 px, references/05-visual-review.md row 5; one line per svg)
//   outline-over-text an unfilled stroked rect whose stroke crosses an svg text of the same svg
//                     (not one sitting on a filled rect drawn after it: the tree badge pill)
//   content-spills    a box whose content spills out of it (visible overflow)
//   content-cut       a box whose content is cut by it (hidden overflow)
//   table-cut         a table of 1-3 columns wider than the box it scrolls in
//   fixed-over-text   a position:fixed control drawn over page text (any scroll position)
//   page-hscroll      the page scrolls horizontally
// and for the three render contract classes of the defect registry (LOOP-006):
//   text-style-drift          a kit class that declares a font-size renders at another
//                             size (a descendant rule such as `.consult-item p` beat it),
//                             or a paragraph inside such an element reached by a rule from
//                             outside it; and (under --contract only) an svg text whose
//                             family is not the kit's --sans, --mono or --serif stack
//   figure-text-contrast      svg text under 4.5:1 against the shapes painted under its
//                             centre, alpha-composited, in the light AND the dark scheme
//   svg-label-outside-its-box an svg text centred in a rect runs past its sides (2 px)
// `--contract <slug>` runs only that class and ends with one line `CONTRACT <slug>
// findings=<n>` (exit 1 when n >= 1, 0 when n = 0); a crash exits 4 without that line.
//
// `--invariants` is a different mode: it loads each page at 1280 px, waits for the composer,
// and evaluates the rendered-DOM invariants of tests/invariants/catalog.md (rail, consultation,
// content, runtime, lang). One line per violation `INV <id> <page> <detail>`, a last line
// `INVARIANTS pages=<n> violations=<m>`, exit 1 when m > 0. It does not run the geometry checks.
//
// Promoted from .context/experiments/2026-09-24-artifact-route-ab/probe.mjs (aidex_ws).
// Output: one JSON line per page and width, then a human-readable defect list.
// Exit 0 = clean, 1 = at least one defect, 2 = usage, 3 = Playwright or its browser missing,
// 4 = the probe crashed (a launch error other than a missing browser, a page that failed
// to load, an exception while measuring). A crash is never reported as a defect or clean.

import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const CONTRACT = ['text-style-drift', 'figure-text-contrast', 'svg-label-outside-its-box'];
const USAGE = `usage: render-probe.sh [--shots <dir>] [--contract <${CONTRACT.join('|')}>] [--invariants] <page.html>...`;
const args = process.argv.slice(2);
const usage = why => { console.error(USAGE + (why ? `  -- ${why}` : '')); process.exit(2); };
if (args.includes('-h') || args.includes('--help')) { console.log(USAGE); process.exit(0); }
let shots = null, only = null, inv = false;
const files = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--shots') {
    shots = args[++i];
    if (!shots) usage('--shots needs a directory');
    if (/\.html?$/i.test(shots)) usage(`--shots takes a directory, got the page ${shots}`);
  }
  else if (args[i] === '--invariants') inv = true;
  else if (args[i] === '--contract') { only = args[++i]; if (!CONTRACT.includes(only)) usage(`--contract takes one of ${CONTRACT.join(', ')}`); }
  else if (args[i].startsWith('-')) usage(`unknown flag ${args[i]}`);
  else files.push(args[i]);
}
if (!files.length) usage('no page given');
if (inv && (shots || only)) usage('--invariants is its own mode and takes no --shots or --contract');
for (const f of files) if (!fs.existsSync(f)) usage(`no such file: ${f}`);
if (process.env.AIDEX_PROBE_ARGS_ONLY) process.exit(0);

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
  // What of a text box is drawn (BL-522.4). An ancestor whose overflow is hidden or clip
  // cuts the box outright. One that scrolls (auto, scroll) is a window: a box past its
  // edge is unseen by anything OUTSIDE that scroller (a rail entry scrolled below the
  // list's edge is not over the copy bar under it), while two boxes inside the same
  // scroller still meet when it is scrolled to them, so between those the window does
  // not apply (`seen`). An absolute box escapes the clips below its containing block
  // (the nearest positioned ancestor); a fixed one escapes them all. Overflow only clips
  // a box that has one and holds block content: not inline, not contents.
  const cut = (b, c, x, y) => ({ left: x ? Math.max(b.left, c.left) : b.left, right: x ? Math.min(b.right, c.right) : b.right,
                                 top: y ? Math.max(b.top, c.top) : b.top, bottom: y ? Math.min(b.bottom, c.bottom) : b.bottom });
  const sized = b => ({ ...b, width: b.right - b.left, height: b.bottom - b.top });
  const clips = (el, raw) => {
    let b = { left: raw.left, top: raw.top, right: raw.right, bottom: raw.bottom }, escaping = false;
    const sc = [];
    for (let e = el; e && e !== document.body; e = e.parentElement) {
      const s = getComputedStyle(e);
      if (escaping && s.position !== 'static') escaping = false;
      if (!escaping && s.display !== 'inline' && s.display !== 'contents') {
        const c = e.getBoundingClientRect(), hard = v => v === 'hidden' || v === 'clip', soft = v => v === 'auto' || v === 'scroll';
        b = cut(b, c, hard(s.overflowX), hard(s.overflowY));
        if (soft(s.overflowX) || soft(s.overflowY)) sc.push({ e, c, x: soft(s.overflowX), y: soft(s.overflowY) });
      }
      if (s.position === 'fixed') break;
      if (s.position === 'absolute') escaping = true;
    }
    return { b: sized(b), sc };
  };
  // box `o` as seen from something inside the scrollers `others` (a list of elements)
  const seen = (o, others) => sized(o.sc.reduce((b, w) => others.includes(w.e) ? b : cut(b, w.c, w.x, w.y), o.b));
  const within = o => o.sc.map(w => w.e);
  const out = [];
  // text boxes: one per element that owns a non-empty text node
  const boxes = [];
  const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let n; (n = tw.nextNode());) {
    if (!n.textContent.trim()) continue;
    const el = n.parentElement; if (!el || !vis(el) || el.closest('script,style,noscript,[hidden],details:not([open]) > :not(summary)')) continue;
    const r = document.createRange(); r.selectNodeContents(n);
    for (const raw of r.getClientRects()) { const { b, sc } = clips(el, raw); if (b.width > 1 && b.height > 1) boxes.push({ el, b, sc, fixed: fixedAncestor(el), bar: inStickyBottomBar(el) }); }
  }
  const sy = scrollY;
  // 1. two texts drawn over each other. A fixed text against a non-fixed one is left to
  // check 4, which names that collision once as fixed-over-text instead of twice; two
  // fixed texts colliding (two labels inside one toolbar, or two fixed controls) stay here.
  for (let i = 0; i < boxes.length; i++) for (let j = i + 1; j < boxes.length; j++) {
    const a = boxes[i], c = boxes[j]; if (a.el === c.el || a.el.contains(c.el) || c.el.contains(a.el)) continue;
    if (!a.fixed !== !c.fixed || a.bar !== c.bar) continue;
    const ra = seen(a, within(c)), rc = seen(c, within(a));
    const w = Math.min(ra.right, rc.right) - Math.max(ra.left, rc.left), h = Math.min(ra.bottom, rc.bottom) - Math.max(ra.top, rc.top);
    if (w > 2 && h > 2 && w * h > 0.25 * Math.min(ra.width * ra.height, rc.width * rc.height))
      out.push({ kind: 'text-overlap', a: name(a.el), b: name(c.el), y: Math.round(ra.top + sy) });
  }
  // 2. svg text outside its svg viewport (clipped axis labels)
  for (const t of document.querySelectorAll('svg text')) {
    const s = t.ownerSVGElement; if (!s || !vis(t)) continue; const a = t.getBoundingClientRect(), b = s.getBoundingClientRect();
    if (a.width && (a.left < b.left - 1 || a.right > b.right + 1 || a.top < b.top - 1 || a.bottom > b.bottom + 1))
      out.push({ kind: 'svg-text-clipped', a: name(t), y: Math.round(a.top + sy) });
  }
  // 2b. svg text drawn smaller than the kit's legible floor, as the reader sees it (font size
  // times the viewBox scale), at phone width only (BL-648). 11 px is the floor
  // references/05-visual-review.md names; a text at exactly 11 may measure 10.99, hence 10.5.
  // One line per root svg, naming its smallest text.
  const rootOf = el => { let s = el.ownerSVGElement; while (s && s.ownerSVGElement) s = s.ownerSVGElement; return s; };
  const inertSvg = 'defs,clipPath,mask,marker,pattern,symbol';
  if (innerWidth <= 390) {
    const small = new Map();
    for (const t of document.querySelectorAll('svg text')) {
      const m = t.getScreenCTM(); if (!m || !t.textContent.trim() || !vis(t) || t.closest(inertSvg) || !t.getBoundingClientRect().width) continue;
      const px = parseFloat(getComputedStyle(t).fontSize) * Math.hypot(m.a, m.b), r = rootOf(t);
      const o = small.get(r); if (!o) small.set(r, { t, px, n: 1 }); else { o.n++; if (px < o.px) { o.t = t; o.px = px; } }
    }
    for (const { t, px, n } of small.values()) if (px < 10.5)
      out.push({ kind: 'svg-text-small', a: name(t), msg: `${px.toFixed(1)}px on screen, under the 11 px floor (smallest of ${n} text${n > 1 ? 's' : ''} in its svg)`, y: Math.round(t.getBoundingClientRect().top + sy) });
  }
  // 2c. a highlight outline (an unfilled rect with a stroke) whose stroke band crosses a text
  // of the same svg (BL-648). A text wholly inside the inner edge or wholly outside the
  // outer edge is clear; one touching the band by more than 1 px is crossed. Rects only,
  // read as screen boxes (no rotation); a filled rect is a card, not an outline.
  for (const r of document.querySelectorAll('svg rect')) {
    if (!vis(r) || r.closest(inertSvg)) continue;
    const cs = getComputedStyle(r), m = r.getScreenCTM(); if (!m || cs.stroke === 'none' || !(parseFloat(cs.strokeWidth) > 0)) continue;
    if (!(cs.fill === 'none' || /^rgba\(.*,\s*0\)$/.test(cs.fill) || parseFloat(cs.fillOpacity) === 0)) continue;
    const q = r.getBoundingClientRect(), hw = parseFloat(cs.strokeWidth) * Math.hypot(m.a, m.b) / 2, root = rootOf(r);
    for (const t of document.querySelectorAll('svg text')) {
      if (rootOf(t) !== root || !t.textContent.trim() || !vis(t) || t.closest(inertSvg)) continue;
      const b = t.getBoundingClientRect(); if (!b.width) continue;
      const touches = b.right > q.left - hw + 1 && b.left < q.right + hw - 1 && b.bottom > q.top - hw + 1 && b.top < q.bottom + hw - 1;
      const inside = b.left >= q.left + hw - 1 && b.right <= q.right - hw + 1 && b.top >= q.top + hw - 1 && b.bottom <= q.bottom - hw + 1;
      // a filled rect drawn after the outline that holds the text is what the text sits on
      // (the diagram engine's badge pill straddles its box's edge over a page-ground fill)
      const padded = [...root.querySelectorAll('rect')].some(p => {
        if (p === r || !(r.compareDocumentPosition(p) & Node.DOCUMENT_POSITION_FOLLOWING) || !vis(p) || p.closest(inertSvg)) return false;
        const ps = getComputedStyle(p); if (ps.fill === 'none' || /^rgba\(.*,\s*0\)$/.test(ps.fill) || parseFloat(ps.fillOpacity) < 0.9) return false;
        const pb = p.getBoundingClientRect();
        return pb.left <= b.left + 1 && pb.right >= b.right - 1 && pb.top <= b.top + 1 && pb.bottom >= b.bottom - 1;
      });
      if (touches && !inside && !padded) { out.push({ kind: 'outline-over-text', a: name(r), b: name(t), y: Math.round(b.top + sy) }); break; }
    }
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
  // 3b. a table of one to three columns wider than the box it scrolls in (BL-592). Check 3
  // skips a scroller, yet the kit makes such a table fit the screen (BL-567): past the edge
  // the reader sees its last column cut, fade or not. Four or more columns scroll on purpose
  // (BL-248, BL-536). Columns counted as composer.js does: the most cells in an outer row,
  // so a table nested in another one's cell is the outer table's to judge.
  for (const t of document.body.querySelectorAll('table')) {
    if (!vis(t) || t.parentElement.closest('table') || [].reduce.call(t.rows, (m, r) => Math.max(m, r.cells.length), 0) > 3) continue;
    let sc = t.parentElement; while (sc && sc !== document.body && !/(auto|scroll)/.test(getComputedStyle(sc).overflowX)) sc = sc.parentElement;
    if (!sc || sc === document.body || !sc.clientWidth) continue;
    const r = t.getBoundingClientRect(), dx = Math.round(r.width - sc.clientWidth);
    if (dx > 1) out.push({ kind: 'table-cut', a: name(t), dx, y: Math.round(r.top + sy) });
  }
  // 4. a fixed control drawn over page text. Both the container's own rect and each fixed
  // text box are tested. The container rect alone misses a label hanging out of a 0-height
  // (or 0x0) fixed strip; the text boxes alone miss the opaque padding of a pill such as
  // the kit theme toggle, which covers a line of body text with no letter of its own over
  // it (6 such collisions on the 2026-09-24 A/B pages). One line per fixed container.
  const areas = [];
  for (const el of document.body.querySelectorAll('*')) {
    if (getComputedStyle(el).position !== 'fixed' || !vis(el)) continue; const r = el.getBoundingClientRect();
    if (r.width > 1 && r.height > 1) areas.push({ owner: el, label: el, r, sc: [] });
  }
  for (const f of boxes) if (f.fixed) areas.push({ owner: f.fixed, label: f.el, r: f.b, sc: within(f) });
  const hit = new Set();
  for (const { owner, label, r, sc } of areas) {
    if (hit.has(owner)) continue;
    const t = boxes.find(o => { if (o.fixed) return false; const q = seen(o, sc); return q.right > r.left && q.left < r.right && q.bottom > r.top && q.top < r.bottom; });
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

// The render contract classes. Runs in the page; `classes` is the subset to run and
// `scheme` the colour scheme the page was loaded in (named in contrast findings only).
const contract = ({ classes, scheme, svgFamily }) => {
  const want = k => classes.includes(k);
  const out = [];
  // A collapsed <details> (a decided item folds into one) is read as the reader sees it
  // once opened; each one opened here is closed again before the geometry checks run.
  const opened = [...document.querySelectorAll('details:not([open])')];
  for (const d of opened) d.open = true;
  let unmeasured = 0;
  const shown = el => el.checkVisibility({ opacityProperty: true, visibilityProperty: true });
  const name = el => { const c = (el.getAttribute('class') || '').trim(); return el.tagName.toLowerCase() + (c ? '.' + c.split(/\s+/)[0] : '') + ' "' + (el.textContent || '').trim().slice(0, 40) + '"'; };
  const px = v => Math.round(v * 100) / 100;
  const texts = [...document.querySelectorAll('svg text')].filter(t => t.textContent.trim() && shown(t) && t.getBoundingClientRect().width > 0);
  const rootSvg = t => { let s = t.ownerSVGElement; while (s && s.ownerSVGElement) s = s.ownerSVGElement; return s; };
  const inert = 'defs,clipPath,mask,marker,pattern,symbol';

  if (want('text-style-drift')) {
    // (a) Every class the kit's components sheet gives a font-size in a single-class rule
    // (`.fieldlabel { font-size: 0.72rem }`), read from the page's own kit, so a page is
    // held to the kit it was written with. Rules inside a matching media query count. A
    // `:where()` filter on it (kit 27's `.chip:where(:not(svg *))`) adds no specificity
    // and keeps the rule single-class.
    const rulesOf = sheet => { const acc = []; const walk = rs => { for (const r of rs) {
      if (r instanceof CSSMediaRule) { if (matchMedia(r.conditionText).matches) walk(r.cssRules); }
      else if (r instanceof CSSStyleRule) acc.push(r); } };
      try { walk(sheet.cssRules); } catch { /* a cross-origin sheet cannot be read */ } return acc; };
    // Selector lists split at top-level commas only (`:is(a, b)` stays whole).
    const parts = sel => { const out = []; let d = 0, cur = '';
      for (const ch of sel) { if (ch === '(') d++; if (ch === ')') d--; if (ch === ',' && !d) { out.push(cur.trim()); cur = ''; } else cur += ch; }
      out.push(cur.trim()); return out.filter(Boolean); };
    const kit = [...document.styleSheets].find(s => /artifact-kit\W+components/.test((s.ownerNode && s.ownerNode.textContent || '').slice(0, 300)));
    const declared = new Map();   // class -> the kit rule that declares its size
    if (kit) for (const r of rulesOf(kit)) {
      if (!r.style.fontSize) continue;
      for (const sel of parts(r.selectorText)) { const m = sel.replace(/:where\((?:[^()]|\([^()]*\))*\)/g, '').match(/^\.(-?[_a-zA-Z][\w-]*)$/); if (m) declared.set(m[1], r); }
    }
    const resolve = (v, el) => {
      const m = String(v).trim().match(/^(-?[\d.]+)(px|rem|em|%)$/); if (!m) return null;
      const n = +m[1];
      if (m[2] === 'px') return n;
      if (m[2] === 'rem') return n * parseFloat(getComputedStyle(document.documentElement).fontSize);
      const parent = parseFloat(getComputedStyle(el.parentElement || document.documentElement).fontSize);
      return m[2] === 'em' ? n * parent : n * parent / 100;
    };
    // Specificity [ids, classes, types] of one complex selector: :where() counts nothing,
    // :is()/:not()/:has() count their most specific argument.
    const spec = sel => {
      const v = [0, 0, 0];
      let s = sel.replace(/:where\((?:[^()]|\([^()]*\))*\)/g, '');
      s = s.replace(/:(is|not|has|matches)\(((?:[^()]|\([^()]*\))*)\)/g, (_, __, arg) => {
        const best = parts(arg).map(spec).sort((a, b) => b[0] - a[0] || b[1] - a[1] || b[2] - a[2])[0] || [0, 0, 0];
        for (let i = 0; i < 3; i++) v[i] += best[i]; return ' ';
      });
      s = s.replace(/\[[^\]]*\]/g, () => { v[1]++; return ' '; });
      s = s.replace(/::[\w-]+/g, () => { v[2]++; return ' '; });
      s = s.replace(/#[\w-]+/g, () => { v[0]++; return ' '; });
      s = s.replace(/\.[\w-]+/g, () => { v[1]++; return ' '; });
      s = s.replace(/:[\w-]+(\([^()]*\))?/g, () => { v[1]++; return ' '; });
      for (const t of s.split(/[\s>+~]+/)) if (/^[a-zA-Z][\w-]*$/.test(t)) v[2]++;
      return v;
    };
    // The classes a selector's subject (its last compound) names; parenthesised arguments
    // (`:not(.x)`) do not target the element, so they are dropped first.
    const subjectClasses = sel => {
      let s = sel; for (let prev; prev !== s;) { prev = s; s = s.replace(/\([^()]*\)/g, ''); }
      const last = s.trim().split(/\s*[\s>+~]\s*/).pop();
      return [...last.matchAll(/\.(-?[_a-zA-Z][\w-]*)/g)].map(m => m[1]);
    };
    const sized = [...document.styleSheets].flatMap(rulesOf).filter(r => r.style.fontSize);
    // The rule that sets this element's font-size in the cascade: { inline } for a style
    // attribute, { rule, sel } for a style rule (its matching selector), null when the
    // size is inherited. Importance, then specificity, then order.
    const later = (a, b) => { for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] > b[i]; return false; };
    const winner = el => {
      if (el.style.fontSize && el.style.getPropertyPriority('font-size') === 'important') return { inline: true };
      let best = null;
      sized.forEach((rule, order) => {
        const imp = rule.style.getPropertyPriority('font-size') === 'important' ? 1 : 0;
        for (const sel of parts(rule.selectorText)) {
          let hit = false; try { hit = el.matches(sel); } catch { continue; }
          if (!hit) continue;
          const k = [imp, ...spec(sel), order];
          if (!best || later(k, best.k)) best = { rule, sel, k };
        }
      });
      if (el.style.fontSize && !(best && best.k[0])) return { inline: true };
      return best;
    };
    // On purpose: an inline size, or a winning rule whose subject names one of the
    // element's own classes (`.note {..}` on the page, `.x .note {..}`).
    const onPurpose = (el, w) => !!w && (w.inline || subjectClasses(w.sel).some(c => el.classList.contains(c)));
    const isDeclared = el => [...el.classList].some(c => declared.has(c));
    for (const [cls, rule] of declared) for (const el of document.querySelectorAll('.' + CSS.escape(cls))) {
      if (el.closest('svg') || !el.textContent.trim() || !shown(el)) continue;
      const decl = resolve(rule.style.fontSize, el); if (decl === null) continue;
      const got = parseFloat(getComputedStyle(el).fontSize), w = winner(el);
      if (Math.abs(got - decl) > 0.5 && !(w && w.rule === rule) && !onPurpose(el, w))
        out.push({ kind: 'text-style-drift', a: name(el), msg: `.${cls} declares ${rule.style.fontSize} (${px(decl)}px), renders at ${px(got)}px` });
      // Text inside it (the paragraphs of a div.note) takes its size unless a rule reaches
      // it through context OUTSIDE the element (`.consult-item p`). A rule that still
      // matches when the element stands alone (`code`, `.note p`) is part of its design.
      const alone = el.cloneNode(true), inside = [...el.querySelectorAll('*')], twins = [...alone.querySelectorAll('*')];
      inside.forEach((d, i) => {
        if (d.closest('svg') || !shown(d) || !d.textContent.trim()) return;
        for (let a = d.parentElement; a !== el; a = a.parentElement) if (isDeclared(a)) return;
        if (isDeclared(d)) return;
        const dw = winner(d); if (!dw || dw.inline || onPurpose(d, dw)) return;
        let alsoAlone = false; try { alsoAlone = twins[i].matches(dw.sel); } catch { /* keep false */ }
        const dg = parseFloat(getComputedStyle(d).fontSize), pg = parseFloat(getComputedStyle(d.parentElement).fontSize);
        if (!alsoAlone && Math.abs(dg - pg) > 0.5)
          out.push({ kind: 'text-style-drift', a: name(d), msg: `inside .${cls} (${px(pg)}px), set to ${px(dg)}px by \`${dw.sel}\`` });
      });
    }
    // (b) svg text family, under --contract text-style-drift only (opts.svgFamily): the
    // computed family is one of the kit's three stacks, compared as lists with quotes and
    // spacing dropped, one line per family with its count. Each stack is put through the
    // browser too, since Chromium serialises BlinkMacSystemFont as "system-ui".
    const norm = f => f.replace(/["']/g, '').split(',').map(x => x.trim().toLowerCase()).filter(Boolean).join(', ');
    const root = getComputedStyle(document.documentElement);
    const probe = document.createElement('span'); document.body.appendChild(probe);
    const stacks = ['--sans', '--mono', '--serif'].map(v => root.getPropertyValue(v).trim()).filter(Boolean)
      .map(v => { probe.style.fontFamily = v; return norm(getComputedStyle(probe).fontFamily); });
    probe.remove();
    if (svgFamily && stacks.length) {
      const off = new Map();
      for (const t of texts) { const f = norm(getComputedStyle(t).fontFamily); if (!stacks.includes(f)) { const o = off.get(f) || { t, n: 0 }; o.n++; off.set(f, o); } }
      for (const [f, { t, n }] of off) out.push({ kind: 'text-style-drift', a: name(t), msg: `svg text in "${f}" (${n} text${n > 1 ? 's' : ''}), not the kit's --sans, --mono or --serif` });
    }
  }

  if (want('figure-text-contrast')) {
    // Colours go through the browser: computed rgb()/rgba() are read as is, anything else
    // (oklch(), color()) is painted on a 1x1 canvas and read back in sRGB.
    const cv = document.createElement('canvas'); cv.width = cv.height = 1;
    const g = cv.getContext('2d', { willReadFrequently: true });
    const rgba = c => {
      if (!c || c === 'none' || /url\(/.test(c)) return null;
      const m = c.match(/^rgba?\(([^)]+)\)$/);
      if (m) { const v = m[1].split(/[\s,\/]+/).filter(Boolean).map(parseFloat); return [v[0], v[1], v[2], v.length > 3 ? v[3] : 1]; }
      g.clearRect(0, 0, 1, 1); g.fillStyle = 'rgba(0,0,0,0)'; g.fillStyle = c; g.fillRect(0, 0, 1, 1);
      const d = g.getImageData(0, 0, 1, 1).data; return [d[0], d[1], d[2], d[3] / 255];
    };
    const over = (fg, a, bg) => [0, 1, 2].map(i => fg[i] * a + bg[i] * (1 - a));
    const lum = c => c.map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); }).reduce((s, v, i) => s + [0.2126, 0.7152, 0.0722][i] * v, 0);
    const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };
    // opacity multiplies down the svg's groups; fill-opacity is inherited, so the
    // element's own computed value already carries it
    const opacity = (el, stop) => { let a = 1; for (let e = el; e; e = e.parentElement) { a *= parseFloat(getComputedStyle(e).opacity); if (e === stop) break; } return a; };
    const alpha = (el, col, stop) => col[3] * parseFloat(getComputedStyle(el).fillOpacity) * opacity(el, stop);
    const pageBg = svg => { const chain = []; for (let e = svg; e; e = e.parentElement) chain.unshift(e);
      let bg = [255, 255, 255]; for (const e of chain) { const c = rgba(getComputedStyle(e).backgroundColor); if (c && c[3] > 0) bg = over(c, c[3], bg); } return bg; };
    // A <use> draws its referenced shape (or the shapes of a referenced g/symbol) in its
    // own coordinates, offset by x/y. The point is taken into each shape's space through
    // the transforms between the reference and the shape. A fill set nowhere on the
    // referenced chain comes from the <use>, which is what the instance inherits.
    const useHits = (u, cx, cy, svg) => {
      const id = (u.getAttribute('href') || u.getAttribute('xlink:href') || '').replace(/^#/, '');
      const ref = id && document.getElementById(id); const m = u.getScreenCTM(); if (!ref || !m) return [];
      let p = new DOMPoint(cx, cy).matrixTransform(m.inverse());
      p = new DOMPoint(p.x - u.x.baseVal.value, p.y - u.y.baseVal.value);
      const shapes = ref.matches('rect,circle,ellipse,path,polygon,polyline') ? [ref] : [...ref.querySelectorAll('rect,circle,ellipse,path,polygon,polyline')];
      const hits = [];
      for (const s of shapes) {
        const chain = []; for (let e = s; e; e = e.parentElement) { chain.unshift(e); if (e === ref) break; }
        let q = p;
        for (const e of chain) { const tl = e.transform && e.transform.baseVal.consolidate(); if (tl) q = q.matrixTransform(tl.matrix.inverse()); }
        if (!s.isPointInFill(q)) continue;
        const own = chain.some(e => e.hasAttribute('fill') || e.style.fill);
        const fill = getComputedStyle(own ? s : u).fill; if (fill === 'none') continue;
        const c = rgba(fill);
        hits.push([c, c && c[3] * parseFloat(getComputedStyle(own ? s : u).fillOpacity) * opacity(u, svg)]);
      }
      return hits;
    };
    const seen = new Set();
    for (const t of texts) {
      const svg = rootSvg(t); if (!svg) continue;
      const b = t.getBoundingClientRect(), cx = (b.left + b.right) / 2, cy = (b.top + b.bottom) / 2;
      // every shape painted before the text whose fill covers its centre, in paint order;
      // null = a gradient, a pattern or an <image> is under it: not a colour
      let bg = pageBg(svg);
      const paint = (c, a) => { if (!c) { bg = null; return; } if (a <= 0) return; bg = bg ? over(c, a, bg) : (a >= 0.999 ? c.slice(0, 3) : null); };
      for (const s of svg.querySelectorAll('rect,circle,ellipse,path,polygon,polyline,use,image')) {
        if (!(s.compareDocumentPosition(t) & Node.DOCUMENT_POSITION_FOLLOWING) || s.closest(inert) || !shown(s)) continue;
        if (s.tagName === 'image') { const r = s.getBoundingClientRect(); if (cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom) bg = null; continue; }
        if (s.tagName === 'use') { for (const [c, a] of useHits(s, cx, cy, svg)) paint(c, a); continue; }
        const m = s.getScreenCTM(); if (!m) continue;
        if (!s.isPointInFill(new DOMPoint(cx, cy).matrixTransform(m.inverse()))) continue;
        const fill = getComputedStyle(s).fill; if (fill === 'none') continue;
        const c = rgba(fill); paint(c, c && alpha(s, c, svg));
      }
      // a halo: `paint-order: stroke` draws the stroke under the glyphs, so a stroke of 1px
      // or more is what the letters sit on
      const ts = getComputedStyle(t);
      if (/^stroke/.test(ts.paintOrder.trim()) && ts.stroke !== 'none' && parseFloat(ts.strokeWidth) >= 1) {
        const c = rgba(ts.stroke); paint(c, c && c[3] * parseFloat(ts.strokeOpacity) * opacity(t, svg));
      }
      const tc = rgba(getComputedStyle(t).fill);
      if (!bg || !tc) { unmeasured++; continue; }
      const fg = over(tc, alpha(t, tc, svg), bg), q = ratio(fg, bg);
      const key = t.textContent.trim() + '|' + q.toFixed(2);
      if (q < 4.5 && !seen.has(key)) {
        seen.add(key);
        out.push({ kind: 'figure-text-contrast', a: name(t), msg: `${q.toFixed(2)}:1 in the ${scheme} scheme, rgb(${fg.map(Math.round)}) on rgb(${bg.map(Math.round)})` });
      }
    }
  }

  if (want('svg-label-outside-its-box')) {
    // The label's box is the smallest painted rect holding its anchor point: the start,
    // the middle or the end of the label as text-anchor places it, at mid-height. Its
    // centre would miss the box of a label more than twice as wide as the box.
    for (const t of texts) {
      const svg = rootSvg(t); if (!svg) continue;
      const b = t.getBoundingClientRect(), anchor = getComputedStyle(t).textAnchor, cy = (b.top + b.bottom) / 2;
      const cx = anchor === 'middle' ? (b.left + b.right) / 2 : anchor === 'end' ? b.right - 0.5 : b.left + 0.5;
      let box = null, area = Infinity;
      for (const r of svg.querySelectorAll('rect')) {
        if (r.closest(inert) || !shown(r)) continue;
        const s = getComputedStyle(r); if (s.fill === 'none' && s.stroke === 'none') continue;
        const rb = r.getBoundingClientRect();
        if (cx < rb.left || cx > rb.right || cy < rb.top || cy > rb.bottom || rb.width * rb.height >= area) continue;
        box = rb; area = rb.width * rb.height;
      }
      if (box && (b.left < box.left - 2 || b.right > box.right + 2))
        out.push({ kind: 'svg-label-outside-its-box', a: name(t), msg: `x ${Math.round(b.left)}..${Math.round(b.right)} past its rect ${Math.round(box.left)}..${Math.round(box.right)}`, y: Math.round(b.top + scrollY) });
    }
  }
  for (const d of opened) d.open = false;
  return { out, unmeasured };
};

// Anything that escapes the try blocks below is a crash too: exit 4, never a verdict line.
const crash = e => { console.error(`render-probe: CRASH: ${String(e && e.message || e).split('\n')[0]}`); process.exit(4); };
process.on('uncaughtException', crash);
process.on('unhandledRejection', crash);

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
// A page whose script never yields blocks page.evaluate forever, and no caller is sure
// to kill us: the run ends at AIDEX_PROBE_DEADLINE seconds per page (default 60).
// Chromium needs no kill of its own: it exits when this process's pipe to it closes.
const deadline = (Number(process.env.AIDEX_PROBE_DEADLINE) || 60) * files.length;
setTimeout(() => {
  console.error(`render-probe: CRASH on ${current}: no verdict before the ${deadline} s deadline`);
  process.exit(4);
}, deadline * 1000).unref();
if (shots) fs.mkdirSync(shots, { recursive: true });
const report = [];
// --shots bookkeeping: one run stamp for every file written this run, and one manifest
// per page (tiles per width, item ids in page order) so the grader reads tiles by id.
const runStamp = new Date().toISOString();
const VIEW_H = 900;
const manifests = new Map();
const written = [];
let current = '';
const brief = (x, n = 60) => String(x).replace(/\s+/g, ' ').trim().slice(0, n);

// --- --invariants: the rendered-DOM invariants (tests/invariants/catalog.md) ---------------
// Each predicate is keyed by its catalog id and returns detail strings, one per violation.
const invariants = () => {
  // composer.js questionHash(): the chrome the composer injects into an item (keep in step, test-invariants.sh checks)
  const CHROME = '.kit-tag, .consult-proposal, .consult-clear, .kit-other, .kit-notnow, .kit-ask, .kit-defect, .kit-feedback, .kit-more, .kit-provisional, .kit-marks-tile, .kit-marks-list, .consult-kicker, details.opts-more > summary';
  const t = s => (s || '').replace(/\s+/g, ' ').trim();
  const lc = s => t(s).toLowerCase();
  const brief = (s, n = 60) => t(s).slice(0, n);
  const out = [];
  const add = (id, detail) => out.push({ id, detail });
  const shown = el => el.checkVisibility({ contentVisibilityAuto: true, opacityProperty: true, visibilityProperty: true });
  const inClosedDetails = el => { for (let d = el.closest('details:not([open])'); d; d = d.parentElement && d.parentElement.closest('details:not([open])')) { if (!(d === el)) return true; } return false; };
  const links = [...document.querySelectorAll('#raillist a.railitem[href^="#"], #raillist a[href^="#"]')]
    .filter((a, i, all) => all.indexOf(a) === i);
  const idOf = a => { try { return decodeURIComponent(a.getAttribute('href').slice(1)); } catch { return a.getAttribute('href').slice(1); } };
  const target = a => document.getElementById(idOf(a));
  const label = a => t((a.querySelector('.rt') || a).textContent);
  const hasRail = !!document.getElementById('raillist');
  const items = [...document.querySelectorAll('.consult-item')];
  const consultation = items.length > 0;

  if (hasRail) {
    // NAV-1
    for (const a of links) if (!target(a)) add('NAV-1', `rail entry "${brief(label(a))}" links to #${idOf(a)}, which no element carries`);
    // NAV-8 first: a decided target is NAV-8's, not also NAV-2's
    const decidedTarget = x => x.matches('[data-decided]:not([data-proposal])') || !!x.closest('details.decided-unit');
    // NAV-2: the composer never opens a details on rail navigation, so a closed one hides its target too
    for (const a of links) { const x = target(a); if (x && !shown(x) && !decidedTarget(x)) add('NAV-2', `rail entry "${brief(label(a))}" targets #${x.id}, which is not rendered`); }
    for (const a of links) { const x = target(a); if (x && decidedTarget(x)) add('NAV-8', `rail entry "${brief(label(a))}" targets #${x.id}, a decided item folded out of the index`); }
    // NAV-9: every shown, unsettled item is a rail target. Composer exemption (itemLink): a proposal
    // (data-decided + data-proposal) inside a consult-group gets no entry; an item in a group reached
    // only through an id-less group gets none either, which is the defect this row catches.
    const targetSet = new Set(links.map(target).filter(Boolean));
    for (const el of items) {
      if (!shown(el) || inClosedDetails(el) || (el.hasAttribute('data-decided') && !el.hasAttribute('data-proposal'))) continue;
      if (el.hasAttribute('data-proposal') && el.closest('.consult-group')) continue;
      if (!targetSet.has(el)) add('NAV-9', `item ${el.dataset.id || '?'} is not the target of any rail entry`);
    }
    // NAV-3: adjacent pairs, the first one that precedes its predecessor names the break
    const resolved = links.map(a => ({ a, x: target(a) })).filter(p => p.x);
    const ordered = resolved.filter(p => !decidedTarget(p.x));   // a folded decided target has no place to be in order (NAV-8's)
    for (let i = 1; i < ordered.length; i++) {
      const p = ordered[i - 1], q = ordered[i];
      if (p.x !== q.x && (p.x.compareDocumentPosition(q.x) & Node.DOCUMENT_POSITION_PRECEDING))
        add('NAV-3', `rail lists "${brief(label(p.a), 40)}" before "${brief(label(q.a), 40)}" but the page has them the other way round`);
    }
    // NAV-4
    // the target's OWN heading (not one of a nested item); equal when folded, a prefix only for an explicit truncation marker
    const ownHeading = x => {
      const h = x.querySelector(':scope > .sec-head h2, :scope > h2, :scope > h3');
      if (!h) return null;
      const c = h.cloneNode(true); c.querySelectorAll('.consult-id').forEach(n => n.remove());
      return lc(c.textContent);
    };
    // an item's kicker (its title, shown above a question h3) is part of its own heading block
    const ownKicker = x => { const k = x.querySelector(':scope > .consult-kicker'); return k && shown(k) ? lc(k.textContent) : null; };
    for (const { a, x } of resolved) {
      const l = lc(label(a));
      if (!l) { add('NAV-4', `rail entry for #${x.id} has an empty label`); continue; }
      const h = ownHeading(x);
      const cut = l.replace(/(\u2026|\.\.\.)$/, '').trim();
      const ok = h === null ? lc(x.textContent).includes(l) : (h === l || ownKicker(x) === l || (cut !== l && cut && h.startsWith(cut)));
      if (!ok) add('NAV-4', `rail label "${brief(label(a))}" is not the heading of #${x.id}${h === null ? '' : ` ("${brief(h)}")`}`);
    }
    // NAV-5
    const targets = resolved.map(p => p.x);
    for (const h of document.querySelectorAll('.main h2')) {
      if (!shown(h) || inClosedDetails(h)) continue;
      if (!targets.some(x => x === h || x.querySelector('h2') === h)) add('NAV-5', `h2 "${brief(h.textContent)}" is in no rail entry's target`);
    }
    // NAV-6
    const seen = new Map();
    for (const a of links) { const k = idOf(a); if (seen.has(k)) add('NAV-6', `two rail entries target #${k}: "${brief(label(seen.get(k)), 30)}" and "${brief(label(a), 30)}"`); else seen.set(k, a); }
  }
  // NAV-7: any id carried twice (the second copy is where a link may land instead of the first)
  const ids = new Map();
  for (const el of document.querySelectorAll('[id]')) ids.set(el.id, (ids.get(el.id) || 0) + 1);
  for (const [id, n] of ids) if (n > 1) add('NAV-7', `id "${id}" is carried by ${n} elements`);

  if (consultation) {
    // CON-1: mirrors contract_defects.check_decision_item_without_options on the rendered DOM: every
    // item that asks (not the notes box, not a gallery sample with no .opts, not data-free other than
    // "no"/"false", not data-decided) offers >= 2 AUTHORED options: radio or checkbox inputs inside `.opts` (the composer adds
    // chip inputs elsewhere in the item), or the largest select's options, counted in the item's own subtree (a nested item's are its own).
    for (const el of items) {
      if (el.classList.contains('consult-notes') || el.classList.contains('consult-group') || !el.hasAttribute('data-id')) continue;
      const gallery = el.classList.contains('consult-gallery') || !!el.querySelector('.gal:not(.shots), figure[data-tile]');
      if (gallery && !el.querySelector('.opts')) continue;
      const free = el.getAttribute('data-free');
      if (el.hasAttribute('data-decided') || (free !== null && !['no', 'false'].includes(free.trim().toLowerCase()))) continue;
      const own = n => n.closest('.consult-item') === el;
      const inputs = [...el.querySelectorAll('.opts input[type="radio"], .opts input[type="checkbox"]')].filter(i => own(i) && !i.closest('.kit-other, .kit-notnow') && !i.hasAttribute('data-other')).length;
      const sel = Math.max(0, ...[...el.querySelectorAll('select')].filter(own).map(x => x.querySelectorAll('option').length));
      const n = Math.max(inputs, sel);
      if (n < 2) add('CON-1', `item ${el.dataset.id} offers ${n} option${n === 1 ? '' : 's'}`);
    }
    // CON-2
    const top = document.querySelectorAll('aside.rail #consult-copy').length, end = document.querySelectorAll('main #consult-copy-end').length;
    if (top !== 1 || end !== 1) add('CON-2', `copy controls: ${top} #consult-copy in aside.rail and ${end} #consult-copy-end in main, expected 1 and 1`);
    // CON-3
    for (const el of items) {
      const c = el.cloneNode(true);
      c.querySelectorAll('.consult-id, .fieldlabel, textarea, script, style, ' + CHROME).forEach(n => n.remove());
      const media = c.querySelector('input, img, svg, table, figure, canvas, video, pre, select');
      if (!t(c.textContent) && !media) add('CON-3', `item ${el.dataset.id || '?'} has no text beyond its id badge`);
    }
  }

  // CNT-1, CNT-2: visible prose only (code, pre, kbd, samp, textarea, script, style, template are exempt)
  const skip = 'script,style,noscript,textarea,template,code,pre,kbd,samp';
  const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const spec = new Set(), md = new Set();
  for (let n; (n = tw.nextNode());) {
    // all prose, folded details included (the composer folds every decided item into one); only an
    // authored [hidden] / display:none outside a details is exempt
    // ([hidden] alone is not a hiding: the kit's `.main > section { display:flex }` overrides it)
    const el = n.parentElement;
    const hid = el && el.closest('[hidden]');
    if (!el || el.closest(skip) || (hid && getComputedStyle(hid).display === 'none') || (!shown(el) && !el.closest('details:not([open])'))) continue;
    const x = n.textContent;
    for (const m of x.matchAll(/:::|\{#/g)) spec.add(m[0] + ' in "' + brief(x.slice(Math.max(0, m.index - 15), m.index + 25), 40) + '"');
    for (const m of x.matchAll(/\*\*|`/g)) md.add(m[0] + ' in "' + brief(x.slice(Math.max(0, m.index - 15), m.index + 25), 40) + '"');
  }
  for (const d of spec) add('CNT-1', `literal spec syntax ${d}`);
  for (const d of md) add('CNT-2', `unrendered markdown ${d}`);
  // CNT-3
  const solid = 'svg, img, table, figure, canvas, video, iframe, input, textarea, select, pre';
  for (const el of document.querySelectorAll('.main section, .callout, .note')) {
    if (el.matches('.consult-item') || !shown(el)) continue;
    const c = el.cloneNode(true); c.querySelectorAll('.sec-head, h2, h3, .eyebrow').forEach(n => n.remove());
    if (!t(c.textContent) && !c.querySelector(solid)) add('CNT-3', `empty ${el.tagName.toLowerCase()}${el.id ? '#' + el.id : ''}${el.classList.length ? '.' + el.classList[0] : ''}`);
  }

  // LANG-1: the kit chrome (rail head, copy button) speaks the language of the first STRINGS
  // entry it matches; <html lang> must be that language. Read from the page's own inlined composer.
  const src = [...document.scripts].map(s => s.textContent).find(x => /var STRINGS = \{/.test(x));
  const m = src && src.match(/var STRINGS = (\{[\s\S]*?\n  \});\s*\n\s*var L =/);
  if (m) {
    let S = null; try { S = new Function('return ' + m[1])(); } catch { /* an unreadable table is not a verdict */ }
    const chrome = [document.querySelector('.railhead'), document.getElementById('consult-copy')].filter(Boolean);
    if (S && chrome.length) {
      const lang = (document.documentElement.getAttribute('lang') || '').slice(0, 2).toLowerCase();
      const spoken = new Set();
      chrome.forEach(el => { const k = el.id === 'consult-copy' ? 'copy' : 'contents'; for (const l of Object.keys(S)) if (t(el.textContent) === S[l][k]) spoken.add(l); });
      if (spoken.size && !spoken.has(lang)) add('LANG-1', `<html lang="${document.documentElement.getAttribute('lang') || ''}"> but the kit chrome is in ${[...spoken].join('/')}`);
    }
  }
  return out;
};

if (inv) {
  let n = 0, bad = 0;
  for (const f of files) {
    current = f;
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    const runtime = [];
    page.on('console', m => { if (m.type() === 'error' && !/^Failed to load resource/.test(m.text())) runtime.push({ id: 'RUN-1', detail: brief(m.text()) }); });
    page.on('pageerror', e => runtime.push({ id: 'RUN-2', detail: brief(String(e && e.message || e)) }));
    page.on('requestfailed', r => runtime.push({ id: 'RUN-3', detail: `${r.url().slice(0, 80)} (${r.failure() && r.failure().errorText})` }));
    page.on('response', r => { if (r.status() >= 400) runtime.push({ id: 'RUN-3', detail: `${r.url().slice(0, 80)} (HTTP ${r.status()})` }); });
    try { await page.goto('file://' + path.resolve(f), { waitUntil: 'load' }); }
    catch (e) { crash(new Error(`could not load ${f}: ${String(e && e.message || e).split('\n')[0]}`)); }
    await page.waitForTimeout(300);
    const found = [...await page.evaluate(invariants), ...runtime];
    n++;
    for (const v of found) { bad++; console.log(`INV ${v.id} ${path.basename(f)} ${v.detail.replace(/\s+/g, ' ')}`); }
    await page.close();
  }
  await browser.close();
  console.log(`INVARIANTS pages=${n} violations=${bad}`);
  process.exit(bad ? 1 : 0);
}
try {
for (const f of files) for (const width of [1280, 390]) {
  current = `${f} @${width}px`;
  const d = [];
  let unmeasured = 0;
  // the geometry checks and every contract class run in the dark scheme; contrast runs
  // again in the light one, since a label can pass in one scheme and fail in the other
  for (const scheme of ['dark', 'light']) {
    const geometry = !only && scheme === 'dark';
    const classes = CONTRACT.filter(k => (!only || k === only) && (scheme === 'dark' || k === 'figure-text-contrast'));
    if (!geometry && !classes.length) continue;
    const page = await browser.newPage({ viewport: { width, height: VIEW_H }, colorScheme: scheme });
    await page.goto('file://' + path.resolve(f)); await page.waitForTimeout(400);
    if (classes.length) { const c = await page.evaluate(contract, { classes, scheme, svgFamily: only === 'text-style-drift' }); d.push(...c.out); unmeasured += c.unmeasured; }
    if (geometry) {
      const g = await page.evaluate(check); d.push(...g);
      // the fixed-control check is scroll-dependent: sample the page at four scroll positions
      const seen = new Set(g.filter(x => x.kind === 'fixed-over-text').map(x => x.a + '|' + x.b));
      const H = await page.evaluate(() => document.scrollingElement.scrollHeight);
      for (const y of [H * 0.25, H * 0.5, H * 0.75]) {
        await page.evaluate(y => scrollTo(0, y), y); await page.waitForTimeout(50);
        for (const x of await page.evaluate(check)) if (x.kind === 'fixed-over-text' && !seen.has(x.a + '|' + x.b)) { seen.add(x.a + '|' + x.b); d.push(x); }
      }
      if (shots) {
        // instant scrolling and no snapping: a smooth-scroll or snap page would move mid-capture
        await page.addStyleTag({ content: 'html,body{scroll-behavior:auto !important;scroll-snap-type:none !important}' });
        await page.evaluate(() => scrollTo(0, 0));
        const base = path.basename(f, path.extname(f));
        const full = path.join(shots, `${base}-${width}.png`);
        await page.screenshot({ path: full, fullPage: true });
        written.push(full);
        // Viewport-height tiles (a tall page's full-page shot is downscaled past legibility),
        // each tagged with the item ids (data-id) whose box meets it. A stale tile from an
        // earlier, taller build of the same page is removed first.
        const tilePat = new RegExp(`^${base.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}-${width}-t\\d+\\.png$`);
        for (const old of fs.readdirSync(shots)) if (tilePat.test(old)) fs.rmSync(path.join(shots, old));
        const geo = await page.evaluate(() => {
          const seen = new Map();
          for (const el of document.querySelectorAll('[data-id]')) {
            const id = el.getAttribute('data-id');
            if (seen.has(id)) continue;
            // a closed details shows only its summary row: measure the outermost closed one,
            // so a folded id sits on the tile showing its fold row and on none below it
            let box = el;
            for (let d = el.closest('details:not([open])'); d; d = d.parentElement && d.parentElement.closest('details:not([open])')) box = d;
            if (!box.checkVisibility({ contentVisibilityAuto: true, opacityProperty: true, visibilityProperty: true })) continue;
            const r = box.getBoundingClientRect();
            if (!r.width || !r.height) continue;
            seen.set(id, { id, top: Math.floor(r.top + scrollY), bottom: Math.ceil(r.bottom + scrollY) });
          }
          return { H: document.documentElement.scrollHeight, items: [...seen.values()] };
        });
        if (!manifests.has(f)) manifests.set(f, { page: base, run: runStamp, viewport_height: VIEW_H, ids: geo.items.map(it => it.id), widths: {}, written: [] });
        const man = manifests.get(f);
        man.written.push(path.basename(full));
        // Tiles overlap (stride VIEW_H - 100) so a line cut at one tile's edge is whole in the
        // next; the last tile is pinned to H - VIEW_H so none is a thin sliver. A page no
        // taller than the viewport is one tile of its own height.
        const ys = [0];
        while (ys[ys.length - 1] + VIEW_H < geo.H) ys.push(Math.min(ys[ys.length - 1] + VIEW_H - 100, geo.H - VIEW_H));
        const tiles = [];
        for (const [k, y] of ys.entries()) {
          const h = Math.min(VIEW_H, geo.H - y);
          const file = path.join(shots, `${base}-${width}-t${String(k + 1).padStart(2, '0')}.png`);
          // Each tile is the viewport scrolled to y, not a clip of the scroll-0 full-page capture:
          // that capture draws a fixed bar once, over the first screen, and a sticky rail on t01
          // only, and the grader scored both as defects (BL-528). y never exceeds the page's
          // maximum scroll (H - VIEW_H), so scrollTo lands exactly; a page shorter than the
          // viewport has y = 0 and is clipped to its own height.
          await page.evaluate(y => scrollTo(0, y), y); await page.waitForTimeout(100);
          await page.screenshot({ path: file, clip: { x: 0, y: 0, width, height: h } });
          written.push(file); man.written.push(path.basename(file));
          tiles.push({ file: path.basename(file), y, height: h,
            ids: geo.items.filter(it => it.top < y + h && it.bottom > y).map(it => it.id) });
        }
        man.widths[width] = { fullpage: path.basename(full), page_height: geo.H, tiles };
      }
    }
    await page.close();
  }
  const kinds = {}; for (const x of d) kinds[x.kind] = (kinds[x.kind] || 0) + 1;
  // unmeasured: svg text over a gradient or pattern, whose contrast is not a number
  console.log(JSON.stringify({ file: path.basename(f), width, kinds, ...(unmeasured ? { unmeasured } : {}), defects: d }));
  report.push({ file: f, width, d });
}
await browser.close();
} catch (e) {
  console.error(`render-probe: CRASH on ${current}: ${String(e && e.message || e).split('\n')[0]}`);
  await browser.close().catch(() => {});
  process.exit(4);
}

if (shots) {
  for (const [, m] of manifests) {
    const mf = path.join(shots, `${m.page}-shots.json`);
    written.push(mf);
    m.written.push(path.basename(mf));
    fs.writeFileSync(mf, JSON.stringify(m, null, 2) + '\n');
  }
  console.log(`SHOTS run=${runStamp} files=${written.length}`);
  for (const w of written) console.log(`SHOT ${path.resolve(w)}`);
}

const total = report.reduce((n, r) => n + r.d.length, 0);
console.log('');
for (const { file, width, d } of report) for (const x of d)
  console.log(`DEFECT ${path.basename(file)} @${width}px ${x.kind}: ${[x.a, x.b].filter(Boolean).join(' over ') || ''}${x.dx ? ` (dx=${x.dx}${x.dy ? `, dy=${x.dy}` : ''})` : ''}${x.msg ? ` ${x.msg}` : ''}${x.y !== undefined ? ` at y=${x.y}` : ''}`);
console.log(total ? `render-probe: ${total} defect(s) in ${files.length} page(s)` : `render-probe: clean (${files.length} page(s), 1280 and 390 px)`);
// the gate's line under --contract: exactly one, last, only when the run finished
if (only) console.log(`CONTRACT ${only} findings=${total}`);
process.exit(total ? 1 : 0);
