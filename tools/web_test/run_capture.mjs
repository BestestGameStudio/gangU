#!/usr/bin/env node
// gangU web_test runner: loads a served build, focuses the tab, injects
// capture.js, runs a choreography, saves a webm + burst screenshots.
//
// Usage:
//   node run_capture.mjs --url http://127.0.0.1:8899/ --out takes/take1 [--seconds 25] [--shots]
//   node run_capture.mjs --serve /path/to/exported-build --port 8899 --out takes/take1
//
// Dependencies (declared, versions tested):
//   node >= 18, npm i puppeteer-core@22, a Chrome/Chromium binary (tested: google-chrome stable 131,
//   headless 'new', swiftshader GL flags below). Other browsers/automation drivers are UNTESTED.
// Env: CHROME_PATH overrides the Chrome binary location.
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, s) => {
  if (v.startsWith('--')) a.push([v.slice(2), s[i + 1] && !s[i + 1].startsWith('--') ? s[i + 1] : true]);
  return a;
}, []));
const OUT = args.out || 'takes/take1';
const SECONDS = Number(args.seconds || 25);
mkdirSync(path.dirname(OUT), { recursive: true });

let server = null, url = args.url;
if (args.serve) {
  const port = args.port || '8899';
  server = spawn('python3', ['-m', 'http.server', port, '--bind', '127.0.0.1'], { cwd: args.serve, stdio: 'ignore' });
  url = `http://127.0.0.1:${port}/`;
  await new Promise(r => setTimeout(r, 1000));
}

const puppeteer = await import('puppeteer-core');
const exe = process.env.CHROME_PATH || '/usr/bin/google-chrome';
const browser = await puppeteer.default.launch({
  executablePath: exe, headless: 'new',
  args: ['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--window-size=1280,720'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 720 });
await page.goto(url, { waitUntil: 'load', timeout: 60000 });
// Focus matters: backgrounded/headless-throttled tabs slow rAF (observed ~3-4fps vs ~24fps
// on our rig; exact rates are environment-dependent, not guarantees).
await page.mouse.click(640, 360);
await new Promise(r => setTimeout(r, 12000)); // engine boot
await page.evaluate(readFileSync(new URL('./capture.js', import.meta.url), 'utf8'));
// Sacrificial first tap: the first synthetic input burst after a load was observed swallowed.
await page.evaluate(() => window.__ganguTest.tap('a', 'KeyA', 30));
const mime = await page.evaluate(() => window.__ganguTest.startRec());
console.log('recorder mime:', mime);

// Choreography: hub gate entry (proven pattern on the 2026-11-07 build), then survive-and-cast.
// Enemies kill a stationary player in ~3s, so movement/casting starts immediately after entry.
await page.evaluate(async (secs) => {
  const T = window.__ganguTest;
  const entered = () => T.logs.some(l => l.includes('gate entered'));
  for (let a = 0; a < 10 && !entered(); a++) {
    T.kd('a', 'KeyA'); T.kd('w', 'KeyW');
    await T.sleep(320); T.ku('w', 'KeyW');
    const t0 = Date.now();
    while (Date.now() - t0 < 560 && !entered()) await T.sleep(60);
    if (entered()) break;
    T.ku('a', 'KeyA');
    T.kd('d', 'KeyD'); T.kd('s', 'KeyS'); await T.sleep(380); T.ku('d', 'KeyD'); T.ku('s', 'KeyS');
  }
  T.ku('a', 'KeyA'); T.ku('w', 'KeyW');
  const dead = () => T.logs.filter(l => l.includes('gangU booted OK')).length;
  const bootsAtStart = dead();
  const end = Date.now() + secs * 1000;
  while (Date.now() < end) {
    T.cast(640, 260);
    await T.sleep(500);
    T.kd('a', 'KeyA'); await T.sleep(300); T.ku('a', 'KeyA');
    await T.sleep(300);
    if (dead() > bootsAtStart) break; // died: death-restart returns to hub; stop the take
  }
}, SECONDS);

const rec = await page.evaluate(() => window.__ganguTest.stopRec());
if (!rec.bytes || rec.bytes < 10000) throw new Error(`recording suspiciously small: ${rec.bytes} bytes`);
const buf = Buffer.from(rec.b64, 'base64');
writeFileSync(OUT + '.webm', buf);
console.log('webm bytes:', buf.length, 'sha256:', createHash('sha256').update(buf).digest('hex'));

if (args.shots) {
  for (let i = 0; i < 6; i++) {
    await page.screenshot({ path: `${OUT}-shot${i}.png` });
    await new Promise(r => setTimeout(r, 70));
  }
}
const finalLogs = await page.evaluate(() => window.__ganguTest.logs.filter(l =>
  l.includes('gate entered') || l.includes('booted OK')));
console.log('log markers:', JSON.stringify(finalLogs));
await browser.close();
if (server) server.kill();
console.log('OK');
