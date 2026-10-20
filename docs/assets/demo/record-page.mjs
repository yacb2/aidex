// Records the built consultation page as a video: open, scroll, pick options, show the copy bar.
import { createRequire } from 'module';
const require = createRequire(process.env.PW_ROOT + '/');
const { chromium } = require('playwright');
const [page_html, outdir] = process.argv.slice(2);
import http from 'http'; import fs from 'fs'; import path from 'path';
// Serve the page over 127.0.0.1 so the clipboard permission has an origin (file:// has none).
const srv = http.createServer((q, r) => { r.setHeader('content-type', 'text/html'); r.end(fs.readFileSync(page_html)); });
await new Promise((ok) => srv.listen(0, '127.0.0.1', ok));
const origin = 'http://127.0.0.1:' + srv.address().port;
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1200, height: 750 }, permissions: ['clipboard-read', 'clipboard-write'], recordVideo: { dir: outdir, size: { width: 1200, height: 750 } } });
const p = await ctx.newPage();
const wait = (ms) => p.waitForTimeout(ms);
await p.goto(origin + '/');
await wait(2000);
await p.mouse.wheel(0, 500); await wait(1800);
await p.locator('input[name="Q1"][data-label="Phased cutover"]').check({ force: true }); await wait(1500);
await p.mouse.wheel(0, 450); await wait(1800);
await p.locator('input[name="Q2"][data-label^="Backfill in batches"]').check({ force: true }); await wait(1500);
await p.mouse.wheel(0, 450); await wait(1800);
await p.locator('input[name="Q3"][data-label="Keep read-only for 30 days"]').check({ force: true }); await wait(1500);
await p.locator('#consult-copy').hover(); await p.locator('#consult-copy').click().catch(() => {});
await wait(2500);
await ctx.close(); srv.close(); await b.close();
