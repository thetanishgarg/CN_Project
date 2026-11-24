// EVIDENCE.html -> EVIDENCE.pdf, plus one PNG per figure in evidence/screenshots/
import { spawn } from 'node:child_process'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path'; import { pathToFileURL } from 'node:url';
const E = path.resolve(import.meta.dirname, '..'), out = path.join(E, 'screenshots'), prof = fs.mkdtempSync(path.join(os.tmpdir(), 'cn-'));
for (const f of fs.readdirSync(out)) if (/^\d\d-.*\.png$/.test(f)) fs.unlinkSync(path.join(out, f));
const ch = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ['--headless=new', '--remote-debugging-port=9334', `--user-data-dir=${prof}`, '--no-first-run', '--window-size=900,1200', 'about:blank']);
const sleep = ms => new Promise(r => setTimeout(r, ms)); let t;
for (let i = 0; i < 40; i++) { try { t = await (await fetch('http://127.0.0.1:9334/json')).json(); if (t.length) break; } catch {} await sleep(250); }
const ws = new WebSocket(t.find(x => x.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
let id = 0; const w = new Map(); ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id) { w.get(d.id)(d.result ?? d.error); w.delete(d.id); } };
const cmd = (method, params = {}) => new Promise(r => { const i = ++id; w.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await cmd('Page.enable'); await cmd('Emulation.setDeviceMetricsOverride', { width: 900, height: 1200, deviceScaleFactor: 2, mobile: false });
await cmd('Page.navigate', { url: pathToFileURL(path.join(E, 'EVIDENCE.html')).href }); await sleep(1500);
const figs = JSON.parse((await cmd('Runtime.evaluate', { expression: `JSON.stringify([...document.querySelectorAll('.fig[data-name]')].map(f=>{const r=f.getBoundingClientRect();return{n:f.dataset.name,x:r.x+scrollX,y:r.y+scrollY,width:r.width,height:r.height}}))` })).result.value);
for (const f of figs) { const s = await cmd('Page.captureScreenshot', { captureBeyondViewport: true, clip: { x: f.x - 8, y: f.y - 8, width: f.width + 16, height: f.height + 16, scale: 1 } }); fs.writeFileSync(path.join(out, f.n + '.png'), Buffer.from(s.data, 'base64')); }
const pdf = await cmd('Page.printToPDF', { printBackground: true, preferCSSPageSize: true, generateDocumentOutline: true, generateTaggedPDF: true });
fs.writeFileSync(path.join(E, 'EVIDENCE.pdf'), Buffer.from(pdf.data, 'base64')); console.log(figs.length, 'PNGs + EVIDENCE.pdf');
ws.close(); ch.kill(); await sleep(600); fs.rmSync(prof, { recursive: true, force: true, maxRetries: 5 }); process.exit(0);
