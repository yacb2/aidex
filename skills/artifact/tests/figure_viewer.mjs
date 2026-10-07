// figure_viewer.mjs <page.html> — what a reader gets from the item-figure viewer
// (BL-597 gallery walk, BL-626 lone/mixed/svg figures), in a real browser with
// TRUSTED key presses, at 1280 and at 390 px. Prints one JSON object;
// test-figure-viewer.sh asserts on it.
import { createRequire } from 'node:module';
import path from 'node:path';

const { chromium } = createRequire(path.join(process.env.AIDEX_PLAYWRIGHT_MODULE, 'package.json'))('playwright');
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await page.goto('file://' + process.argv[2]);
// A step that cannot happen (no such button on a kit without the feature) is
// recorded by the state that follows, not by a 30 s timeout.
page.setDefaultTimeout(1500);
const click = (sel) => page.click(sel).catch(() => {});

const dlgState = () => page.evaluate(() => {
  const dlg = document.querySelector('dialog.kit-zoom');
  if (!dlg || !dlg.querySelector('.kit-zoom-cap')) return { open: !!dlg && dlg.open, tile: '', cap: '', capShown: false,
    prevShown: false, nextShown: false, prevOff: false, nextOff: false, svgShown: false, imgShown: false,
    svgText: 0, btnsInside: false, focusInDialog: false };
  const vis = (el) => !!el && el.getClientRects().length > 0 && !el.hidden;
  const svg = dlg.querySelector('.kit-zoom-svg svg');
  const t = svg && svg.querySelector('text');
  const img = dlg.querySelector('.kit-compare > img');
  const r = (el) => el.getBoundingClientRect();
  return {
    open: dlg.open, tile: dlg.querySelector('.kit-zoom-tile').textContent,
    cap: dlg.querySelector('.kit-zoom-cap').textContent, capShown: vis(dlg.querySelector('.kit-zoom-cap')),
    prevShown: vis(dlg.querySelector('.kit-zoom-prev')), nextShown: vis(dlg.querySelector('.kit-zoom-next')),
    prevOff: dlg.querySelector('.kit-zoom-prev').disabled, nextOff: dlg.querySelector('.kit-zoom-next').disabled,
    svgShown: vis(svg), imgShown: vis(img),
    // the smallest svg text, in screen px: its font-size times the drawing's scale
    svgText: t ? Math.min(...[...svg.querySelectorAll('text')].map((x) =>
      parseFloat(x.getAttribute('font-size')) * r(svg).width / svg.viewBox.baseVal.width)) : null,
    imgW: vis(img) ? r(img).width : null, imgNatW: vis(img) ? img.naturalWidth : null,
    svgW: vis(svg) ? r(svg).width : null, vbW: svg ? svg.viewBox.baseVal.width : null,
    btnsInside: [...dlg.querySelectorAll('.kit-zoom-head button')].filter((b) => vis(b))
      .every((b) => r(b).left >= 0 && r(b).right <= document.documentElement.clientWidth + 1),
    focusInDialog: dlg.contains(document.activeElement) || document.activeElement === dlg,
    native: dlg.classList.contains('native'),
    tileShown: vis(dlg.querySelector('.kit-zoom-tile')), keysShown: vis(dlg.querySelector('.kit-zoom-keys')),
    accColor: svg && svg.querySelector('.acc') ? getComputedStyle(svg.querySelector('.acc')).color : null,
    inkColor: svg ? getComputedStyle(svg.querySelector('text')).color : null,
    body: (() => { const b = dlg.querySelector('.kit-compare'); const sv = dlg.querySelector('.kit-zoom-svg svg');
      const c = dlg.querySelector('.kit-zoom-cap'), bb = dlg.querySelector('.kit-zoom-body').getBoundingClientRect();
      return { ox: getComputedStyle(b).overflowX, sw: b.scrollWidth, cw: b.clientWidth, sl: b.scrollLeft,
               svgLeft: sv && vis(sv) ? Math.round(sv.getBoundingClientRect().left - b.getBoundingClientRect().left) : null,
               rightGap: sv && vis(sv) ? Math.round(b.getBoundingClientRect().right - sv.getBoundingClientRect().right) : null,
               capInside: vis(c) ? c.getBoundingClientRect().left >= bb.left - 1 && c.getBoundingClientRect().right <= bb.right + 1 : null }; })(),
    nextRect: (() => { const r = dlg.querySelector('.kit-zoom-next').getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top)]; })(),
    keysText: dlg.querySelector('.kit-zoom-keys').textContent,
    nav: (() => { const p = getComputedStyle(dlg.querySelector('.kit-zoom-prev')), n = getComputedStyle(dlg.querySelector('.kit-zoom-next'));
      return { prevColor: p.color, nextColor: n.color, prevOpacity: p.opacity, nextOpacity: n.opacity }; })(),
    btn: (() => { const cs = (el) => getComputedStyle(el).backgroundColor;
      return { prev: cs(dlg.querySelector('.kit-zoom-prev')), close: cs(dlg.querySelector('.kit-zoom-close')) }; })(),  };
});
const closeDlg = async () => { await page.keyboard.press('Escape'); await page.waitForTimeout(100); };

async function run(width) {
  await page.setViewportSize({ width, height: 900 });
  const o = {};
  o.markers = await page.evaluate(() => ({
    lonePng: document.querySelector('[data-id="Q2"] figure').getAttribute('role'),
    loneSvg: document.querySelector('[data-id="Q3"] figure').getAttribute('role'),
    label: getComputedStyle(document.querySelector('[data-id="Q3"] figure'), '::after').content,
    pair: [...document.querySelectorAll('[data-id="Q4"] figure')].map((f) => f.getAttribute('role')),
    // what the reader sees in the page itself at this width
    title: document.querySelector('[data-id="Q2"] figure').getAttribute('title'),
    rowSvgTile: (() => { const f = document.querySelector('[data-id="svgrow-sample"] figure[data-tile="before"]');
      return { role: f.getAttribute('role'), zoom: f.getAttribute('data-zoom') }; })(),
    rowImgTile: document.querySelector('[data-id="svgrow-sample"] figure[data-tile="after"]').getAttribute('role'),
    capAlign: getComputedStyle(document.querySelector('[data-id="Q2"] figcaption')).textAlign,
    pageAcc: getComputedStyle(document.querySelector('[data-id="Q3"] figure svg .acc')).color,
    pageSvgText: (() => { const s = document.querySelector('[data-id="Q3"] figure svg');
      return 12 * s.getBoundingClientRect().width / s.viewBox.baseVal.width; })(),
  }));
  // a lone png
  await click('[data-id="Q2"] figure');
  o.lonePng = await dlgState();
  await closeDlg();
  // a lone svg, opened with the keyboard (Enter on the focused figure)
  await page.focus('[data-id="Q3"] figure').catch(() => {});
  await page.keyboard.press('Enter');
  o.loneSvg = await dlgState();
  // scroll fully right, then Esc and reopen: nothing stale, symmetric edges, caption stays put
  await page.evaluate(() => { document.querySelector('.kit-compare').scrollLeft = 9999; });
  o.scrolled = await dlgState();
  await closeDlg();
  await page.focus('[data-id="Q3"] figure').catch(() => {});
  await page.keyboard.press('Enter');
  o.reopen = await dlgState();
  if (o.reopen.native) await click('.kit-zoom-size');   // to Fit, whichever size it opened at
  o.loneSvgFit = await page.evaluate(() => getComputedStyle(document.querySelector('.kit-zoom-svg svg')).maxHeight);   // Fit must fit the height too
  o.loneFit = await dlgState();
  await closeDlg();
  // the size button does not move when a lone drawing changes size (Fit -> 1:1)
  await click('[data-id="Q3"] figure');
  const sizeTop = () => page.evaluate(() => document.querySelector('.kit-zoom-size').getBoundingClientRect().top);
  o.loneToggle = { fit: await sizeTop() };
  await click('.kit-zoom-size');
  o.loneToggle.native = await sizeTop();
  await closeDlg();
  // a portrait drawing: Fit is capped by the height, so it must be centred, not just full width
  await click('[data-id="Q8"] figure');
  o.portrait = await dlgState();
  await closeDlg();
  // a drawing that fits, then a tall one: the tall one gets its own size
  await click('[data-id="Q9"] figure');
  await click('.kit-zoom-next');
  o.stepTall = await dlgState();
  await closeDlg();
  // a tall svg in Fit stays inside the window
  await click('[data-id="Q5"] figure');
  await click('.kit-zoom-size');
  o.tall = await page.evaluate(() => { const r = document.querySelector('.kit-zoom-svg svg').getBoundingClientRect();
    return { bottom: r.bottom, h: window.innerHeight, native: document.querySelector('dialog.kit-zoom').classList.contains('native') }; });
  await closeDlg();
  // a fresh open starts at the image's own default size
  await click('[data-id="Q2"] figure');
  await click('.kit-zoom-size');
  o.q2toggled = await dlgState();
  await closeDlg();
  await click('[data-id="Q2"] figure');
  o.q2reopen = await dlgState();
  await closeDlg();
  // same-kind walks keep the reader's size
  await click('[data-id="Q1"] figure');
  await click('.kit-zoom-size');
  await click('.kit-zoom-next');
  o.keepSize = await dlgState();
  await closeDlg();
  // the mixed png + svg pair: keys, then the buttons
  await click('[data-id="Q4"] figure');
  o.pair1 = await dlgState();
  await page.keyboard.press('ArrowRight');
  o.pair2 = await dlgState();
  await page.keyboard.press('ArrowRight');
  o.pairEnd = await dlgState();               // no wrapping
  await page.evaluate(() => { document.querySelector('.kit-compare').scrollLeft = 50; });
  await click('.kit-zoom-prev');
  o.pairPrev = await dlgState();
  await click('.kit-zoom-next');
  o.pairNext = await dlgState();              // the button just disabled gave up the focus
  o.pairNextScroll = o.pairNext.body.sl;       // came back to the svg after a scroll: starts at 0
  await page.keyboard.press('ArrowLeft');
  o.pairBack = await dlgState();              // keys still work after a button press
  await closeDlg();
  // Ampliar straight on the run's drawing (BL-712), then Fit -> 1:1 -> Fit (BL-713)
  await page.locator('[data-id="Q4"] figure').nth(1).click().catch(() => {});
  o.svgOpen = await dlgState();
  await click('.kit-zoom-size');
  o.svgNative = await dlgState();
  await click('.kit-zoom-size');
  o.svgFit = await dlgState();
  await closeDlg();
  // Chrome makes an overflowing scroller Tab-focusable: the arrows must survive the walk it triggers
  await click('[data-id="Q4"] figure');
  await page.keyboard.press('ArrowRight');
  let found = false;
  for (let i = 0; i < 8 && !found; i++) {
    await page.keyboard.press('Tab');
    found = await page.evaluate(() => document.activeElement.classList.contains('kit-compare'));
  }
  await page.keyboard.press('ArrowLeft');
  await page.waitForTimeout(150);                 // Chrome drops a no-longer-focusable focus at the next frame
  o.tabGuard = { found, left: await dlgState() };
  await page.keyboard.press('ArrowRight');
  o.tabGuard.right = await dlgState();
  await closeDlg();
  await click('[data-id="Q4"] figure');
  await page.keyboard.press('ArrowRight');
  // the keys always walk: click the drawing, Left goes back, focus stays in the dialog, Right walks on
  await page.keyboard.press('ArrowRight');
  await click('.kit-zoom-svg svg');
  await page.keyboard.press('ArrowLeft');
  o.clickLeft = await dlgState();
  await page.keyboard.press('ArrowRight');
  o.clickRight = await dlgState();
  await closeDlg();
  // a tall raster at 1:1: stepping keeps the reader's vertical position (BL-597)
  await click('[data-id="Q7"] figure');
  await click('.kit-zoom-size');
  o.tallRaster = await page.evaluate(() => { const d = document.querySelector('dialog.kit-zoom'); d.scrollTop = 400;
    return { st: d.scrollTop, native: d.classList.contains('native') }; });
  await page.keyboard.press('ArrowRight');
  o.tallStep = await page.evaluate(() => ({ st: document.querySelector('dialog.kit-zoom').scrollTop,
    tile: document.querySelector('.kit-zoom-tile').textContent }));
  await closeDlg();
  // a lone raster at 1:1 scrolls INSIDE the viewer, header and caption stay put, the dialog never scrolls sideways
  await click('[data-id="Q2"] figure');
  await click('.kit-zoom-size');
  o.rasterNative = await page.evaluate(() => {
    const d = document.querySelector('dialog.kit-zoom'), st = d.querySelector('.kit-compare'), h = d.querySelector('.kit-zoom-head');
    const before = h.getBoundingClientRect().left; st.scrollLeft = 9999; d.scrollLeft = d.scrollLeft;
    const c = d.querySelector('.kit-zoom-cap').getBoundingClientRect(), b = d.querySelector('.kit-zoom-body').getBoundingClientRect();
    const im = d.querySelector('.kit-compare > img').getBoundingClientRect();
    return { dlgScrolls: d.scrollWidth > d.clientWidth + 1, dlgSl: d.scrollLeft, stackScrolls: st.scrollWidth > st.clientWidth + 1,
             headMoved: Math.abs(h.getBoundingClientRect().left - before) > 0.5, capInside: c.left >= b.left - 1 && c.right <= b.right + 1,
             rightGap: Math.round(st.getBoundingClientRect().right - im.right), imgW: im.width }; });
  await closeDlg();
  // a drawing with no viewBox (only width/height): shown sanely, never blown up
  await click('[data-id="Q6"] figure');
  o.noViewBox = await page.evaluate(() => { const d = document.querySelector('dialog.kit-zoom');
    const r = document.querySelector('.kit-zoom-svg svg').getBoundingClientRect(), st = d.querySelector('.kit-compare').getBoundingClientRect();
    return { w: r.width, h: r.height, stackW: st.width, left: r.left - st.left }; });
  await closeDlg();
  // the 8-image gallery: buttons to the end
  await click('[data-id="Q1"] figure');
  o.g1 = await dlgState();
  for (let i = 0; i < 7; i++) await click('.kit-zoom-next');
  o.g8 = await dlgState();
  await closeDlg();
  // Esc after walking to image 2 returns the focus to the figure shown
  await click('[data-id="Q1"] figure');
  await click('.kit-zoom-next');
  await closeDlg();
  o.focusAfterEsc = await page.evaluate(() =>
    [...document.querySelectorAll('[data-id="Q1"] figure')].indexOf(document.activeElement));
  o.layout = await page.evaluate(() => {
    const [a, b] = [...document.querySelectorAll('[data-id="Q4"] figure')].map((f) => f.getBoundingClientRect());
    const caps = [...document.querySelectorAll('[data-id="Q4"] figcaption')].map((c) => Math.round(c.getBoundingClientRect().top));
    return { capsAligned: caps.length === 2 && caps[0] === caps[1], sideBySide: Math.abs(a.top - b.top) < 2 && b.left >= a.right - 1, aW: a.width, bW: b.width,
             overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth };
  });
  return o;
}
// REAL touch: a CDP touch swipe over the Q4 drawing. It walks when the drawing fits the dialog
// and pans when it overflows (a synthetic PointerEvent cannot see the browser cancelling the pointer).
async function touchRun(width) {
  const ctx = await browser.newContext({ hasTouch: true, viewport: { width, height: 900 } });
  const tp = await ctx.newPage();
  await tp.goto('file://' + process.argv[2]);
  tp.setDefaultTimeout(1500);
  const cdp = await ctx.newCDPSession(tp);
  const touch = async (type, x, y) => cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y }] });
  const swipe = async (dx, target = '.kit-zoom-svg svg') => {
    const r = await tp.evaluate((target) => { const b = document.querySelector(target).getBoundingClientRect();
      return { x: b.left + Math.min(b.width, window.innerWidth - b.left) / 2, y: b.top + 60 }; }, target);
    await touch('touchStart', r.x, r.y);
    for (let i = 1; i <= 10; i++) await touch('touchMove', r.x + dx * i / 10, r.y + 20 * i / 10);   // a finger drifts ~20 px
    await touch('touchEnd');
    await tp.waitForTimeout(300);
    return tp.evaluate(() => ({ tile: document.querySelector('.kit-zoom-tile').textContent,
      sl: document.querySelector('.kit-compare').scrollLeft }));
  };
  await tp.tap('[data-id="Q4"] figure');
  const o = {};
  o.rasterSwipe = await swipe(-200, '.kit-compare > img');    // the capture at Fit: finger left = next
  o.toSvg = o.rasterSwipe.tile;
  o.swipeBack = await swipe(200);                             // finger moves right: previous image
  await tp.keyboard.press('ArrowRight');
  o.swipeNext = await swipe(-200);                            // finger moves left: next image (or pan)
  // two fingers spreading over the drawing: the browser must be allowed to pinch-zoom the page
  const sx = await tp.evaluate(() => { const b = document.querySelector('.kit-zoom-svg svg').getBoundingClientRect();
    return { x: Math.min(b.left + b.width / 2, window.innerWidth / 2), y: b.top + 80 }; });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: sx.x - 20, y: sx.y, id: 1 }, { x: sx.x + 20, y: sx.y, id: 2 }] });
  for (let i = 1; i <= 10; i++) await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove',
    touchPoints: [{ x: sx.x - 20 - 8 * i, y: sx.y, id: 1 }, { x: sx.x + 20 + 8 * i, y: sx.y, id: 2 }] });
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await tp.waitForTimeout(300);
  o.pinchScale = await tp.evaluate(() => window.visualViewport.scale);
  await ctx.close();
  return o;
}

const out = { w1280: await run(1280), w390: await run(390) };
out.w1280.touch = await touchRun(1280);
out.w390.touch = await touchRun(390);
console.log(JSON.stringify(out));
await browser.close();
