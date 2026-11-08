// gangU web_test in-page driver + recorder.
// Injected into the game page by run_capture.mjs (or paste into DevTools console).
// Exposes window.__ganguTest = { kd, ku, cast, startRec, stopRec, sleep, logs }.
// No game-state access: input events and canvas capture only (real physics).
(() => {
  const canvas = document.getElementById('canvas');
  const logs = [];
  const origLog = console.log.bind(console);
  console.log = (...a) => { logs.push(a.join(' ')); origLog(...a); };

  // Map game-space coords (1280x720 design) through the canvas bounding rect so
  // this works at any window size / CSS scale, not only a fixed 1280 viewport.
  function toClient(x, y) {
    const r = canvas.getBoundingClientRect();
    return { clientX: r.left + (x / 1280) * r.width, clientY: r.top + (y / 720) * r.height };
  }
  function kd(key, code) {
    for (const t of [window, canvas]) t.dispatchEvent(new KeyboardEvent('keydown', { key, code, bubbles: true }));
  }
  function ku(key, code) {
    for (const t of [window, canvas]) t.dispatchEvent(new KeyboardEvent('keyup', { key, code, bubbles: true }));
  }
  function tap(key, code, ms = 40) { kd(key, code); return new Promise(r => setTimeout(() => { ku(key, code); r(); }, ms)); }
  function cast(x, y) {
    const o = { ...toClient(x, y), button: 0, bubbles: true };
    canvas.dispatchEvent(new MouseEvent('mousemove', o));
    canvas.dispatchEvent(new MouseEvent('mousedown', o));
    canvas.dispatchEvent(new MouseEvent('mouseup', o));
  }
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  let recState = null;
  function startRec(bitsPerSec = 6000000) {
    const mime = ['video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm']
      .find(m => window.MediaRecorder && MediaRecorder.isTypeSupported(m));
    if (!mime) throw new Error('MediaRecorder: no supported webm mimeType in this browser');
    const stream = canvas.captureStream(30);
    const rec = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: bitsPerSec });
    const chunks = [];
    rec.ondataavailable = e => { if (e.data && e.data.size) chunks.push(e.data); };
    rec.start(250);
    recState = { rec, chunks, stream };
    return mime;
  }
  async function stopRec() {
    if (!recState) throw new Error('startRec first');
    const { rec, chunks, stream } = recState;
    await new Promise(r => { rec.onstop = r; rec.stop(); });
    stream.getTracks().forEach(t => t.stop());
    const blob = new Blob(chunks, { type: rec.mimeType });
    const buf = new Uint8Array(await blob.arrayBuffer());
    let bin = '';
    for (let i = 0; i < buf.length; i += 0x8000)
      bin += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000));
    recState = null;
    return { bytes: buf.length, b64: btoa(bin) };
  }
  window.__ganguTest = { kd, ku, tap, cast, sleep, startRec, stopRec, logs };
})();
