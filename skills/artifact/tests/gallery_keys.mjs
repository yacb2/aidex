// gallery_keys.mjs <page.html> — REAL key presses on the zoom dialog's keyboard
// marks, through Playwright (CDP Input.dispatchKeyEvent: trusted events).
// test-composer-functional.sh dispatches synthetic KeyboardEvents, which run the
// page's handlers but never the browser's own default actions: a synthetic Esc
// cannot start the dialog's native close, and a synthetic Enter cannot press a
// focused button. Those two paths are what this file exists to exercise.
// Prints one JSON object; test-gallery-keys.sh asserts on it.
import { createRequire } from 'node:module';
import path from 'node:path';

const { chromium } = createRequire(path.join(process.env.AIDEX_PLAYWRIGHT_MODULE, 'package.json'))('playwright');
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await page.goto('file://' + process.argv[2]);

const state = () => page.evaluate(() => {
  const dlg = document.querySelector('dialog.kit-zoom');
  const note = document.querySelector('dialog.kit-mark-note');
  const ta = document.querySelector('[data-id="audit-with-data-light-desktop"] textarea.kit-marks');
  const d = dlg.querySelector('.kit-marks-layer .kit-mark.drawing');
  return { zoom: dlg.open, note: note.open,
           drafts: dlg.querySelectorAll('.kit-marks-layer .kit-mark.drawing').length,
           left: d ? d.style.left : '', marks: ta ? ta.value : null,
           tile: dlg.querySelector('.kit-zoom-tile').textContent };
});
const out = {};

await page.click('[data-id="audit-with-data-light-desktop"] figure[data-tile="before"]');
await page.click('.kit-zoom-mark');
await page.keyboard.press('ArrowRight');
out.arrow = await state();                 // the draft moved, the tile did not
await page.keyboard.press('Escape');
out.esc = await state();                   // draft dropped, dialog still open
if (out.esc.zoom) {
  await page.click('.kit-zoom-mark');
  await page.keyboard.press('Enter');
  out.enter = await state();               // the note dialog asks for its note
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);          // the note's close event is queued, not inline
  out.noteEsc = await state();             // note cancelled, zoom open, nothing stored
  await page.click('.kit-zoom-mark');
  await page.focus('.kit-zoom-close');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(300);
  out.closeEnter = await state();          // Enter pressed Close: no note, no draft left
}
console.log(JSON.stringify(out));
await browser.close();
