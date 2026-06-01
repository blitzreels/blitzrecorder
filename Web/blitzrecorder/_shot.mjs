import { chromium } from 'playwright';
const url = process.argv[2] || 'http://localhost:3210/';
const out = process.argv[3] || '/tmp/landing.png';
const w = parseInt(process.argv[4] || '1440', 10);
const reduced = process.argv[5] !== 'motion'; // default reduced so reveals show
const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: w, height: 900 },
  deviceScaleFactor: 2,
  reducedMotion: reduced ? 'reduce' : 'no-preference',
});
const page = await ctx.newPage();
await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
await page.waitForTimeout(900);
await page.screenshot({ path: out, fullPage: true });
console.log('OK', await page.title(), out, reduced ? '(reduced)' : '(motion)');
await browser.close();
