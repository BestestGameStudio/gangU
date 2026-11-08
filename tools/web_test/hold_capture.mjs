#!/usr/bin/env node
// #246 hold-cast demo runner: boots the served branch build, then HOLDS Space
// ~9s with OS-style key auto-repeat (CDP trusted keyDown + autoRepeat every
// 100ms - the same event stream a real keyboard produces while held), then
// releases for ~3s. Expected on the #246 build: a fire_ball cast about every
// cooldown (1.2s) with no re-press, and silence after keyUp. On unmodified
// main the same choreography yields exactly ONE cast (echo events do not
// re-trigger is_action_just_pressed) - verified as the negative control.
//
// NOTE: capture.js's plain synthetic kd() does NOT reproduce a real held key
// in the Godot web build (no repeats; the engine drops the hold), so the hold
// uses CDP Input.dispatchKeyEvent directly. Movement/boot still use capture.js.
//
// Usage: node hold_capture.mjs --serve /path/to/build --out takes/hold1
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';

const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, s) => {
  if (v.startsWith('--')) a.push([v.slice(2), s[i + 1] && !s[i + 1].startsWith('--') ? s[i + 1] : true]);
  return a;
}, []));
const OUT = args.out || 'takes/hold1';
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
await page.mouse.click(640, 360);
await new Promise(r => setTimeout(r, 12000)); // engine boot
await page.evaluate(readFileSync(new URL('./capture.js', import.meta.url), 'utf8'));
await page.evaluate(() => window.__ganguTest.tap('a', 'KeyA', 30)); // sacrificial tap
const mime = await page.evaluate(() => window.__ganguTest.startRec());
console.log('recorder mime:', mime);

// Aim up-right, then hold Space with real OS-style auto-repeat.
await page.mouse.move(1000, 250);
const cdp = await page.createCDPSession();
const key = { key: ' ', code: 'Space', windowsVirtualKeyCode: 32, nativeVirtualKeyCode: 32 };
await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', ...key });
for (let i = 0; i < 90; i++) {
  await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', ...key, autoRepeat: true });
  await new Promise(r => setTimeout(r, 100));
}
await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', ...key });
await new Promise(r => setTimeout(r, 3000)); // post-release silence

const rec = await page.evaluate(() => window.__ganguTest.stopRec());
const buf = Buffer.from(rec.b64, 'base64');
writeFileSync(`${OUT}.webm`, buf);
const sha = createHash('sha256').update(buf).digest('hex');
console.log(`saved ${OUT}.webm bytes=${buf.length} sha256=${sha}`);
if (buf.length < 50000) { console.error('suspiciously small recording'); process.exit(1); }
if (server) server.kill();
await browser.close();
