// Drives real Google Chrome (headless) against a real backend.py and records what Chrome's
// own network stack reports: 200 from network, then served from cache, then 304 on reload.
import { spawn } from 'node:child_process'; import fs from 'node:fs'; import os from 'node:os'; import path from 'node:path';
const root = path.resolve(import.meta.dirname, '../..'), shots = path.join(root, 'evidence/screenshots');
const ver = process.argv[2] || '1.0';   // 1.0 = backend.py as it is; 1.1 = same handler, HTTP/1.1 status line (what a browser sees behind the edge)
const py = ver === '1.1' ? ['-u', '-c', "import http.server; http.server.BaseHTTPRequestHandler.protocol_version='HTTP/1.1'; exec(open('backend.py').read())"] : ['-u', 'backend.py'];
const be = spawn('python3', py, { cwd: root, env: { ...process.env, BACKEND_NAME: 'B', BACKEND_PORT: '3002' } });
const beLog = []; be.stdout.on('data', d => beLog.push(d.toString()));
const prof = fs.mkdtempSync(path.join(os.tmpdir(), 'cn-chrome-'));
const ch = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ['--headless=new', '--remote-debugging-port=9333', `--user-data-dir=${prof}`, '--no-first-run', '--window-size=1000,420', 'about:blank']);
const sleep = ms => new Promise(r => setTimeout(r, ms)); let tabs;
for (let i = 0; i < 40; i++) { try { tabs = await (await fetch('http://127.0.0.1:9333/json')).json(); if (tabs.length) break; } catch {} await sleep(250); }
const ws = new WebSocket(tabs.find(t => t.type === 'page').webSocketDebuggerUrl); await new Promise(r => ws.onopen = r);
let id = 0; const wait = new Map(), ev = [];
ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id) { wait.get(d.id)(d.result); wait.delete(d.id); } else ev.push(d); };
const cmd = (method, params = {}) => new Promise(r => { const i = ++id; wait.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
await cmd('Network.enable'); await cmd('Page.enable'); await cmd('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-color-scheme', value: 'light' }] });
await cmd('Emulation.setDeviceMetricsOverride', { width: 900, height: 150, deviceScaleFactor: 2, mobile: false });
const version = (await cmd('Browser.getVersion')).product, url = 'http://127.0.0.1:3002/api/cache', rows = [];
async function step(label, fn, shot) {
  ev.length = 0; await fn(); await sleep(900);
  const req = ev.filter(e => e.method === 'Network.requestWillBeSent' && e.params.request.url === url).at(-1)?.params.requestId;
  const res = ev.find(e => e.method === 'Network.responseReceived' && e.params.requestId === req)?.params.response;
  const xr = ev.find(e => e.method === 'Network.responseReceivedExtraInfo' && e.params.requestId === req)?.params;
  const xq = ev.find(e => e.method === 'Network.requestWillBeSentExtraInfo' && e.params.requestId === req)?.params;
  const served = ev.some(e => e.method === 'Network.requestServedFromCache' && e.params.requestId === req);
  const h = Object.fromEntries(Object.entries(xq?.headers ?? {}).map(([k, v]) => [k.toLowerCase(), v]));
  rows.push({ step: label, reachedServer: !!xr, wireStatus: xr?.statusCode ?? null, fromDiskCache: !!res?.fromDiskCache, fromMemoryCache: served, ifNoneMatch: h['if-none-match'] ?? null, bytesOnWire: res?.encodedDataLength ?? null });
  if (shot) fs.writeFileSync(path.join(shots, shot), Buffer.from((await cmd('Page.captureScreenshot')).data, 'base64'));
}
const go = u => cmd('Page.navigate', { url: u });
await step('1. First visit', () => go(url), 'chrome-api-cache.png');
await go('about:blank'); await sleep(400);
await step('2. Visit again within 60 s', () => go(url));
await step('3. Normal reload', () => cmd('Page.reload'));
await step('4. Hard reload (cache bypassed)', () => cmd('Page.reload', { ignoreCache: true }));
await go('http://127.0.0.1:3002/api/status'); await sleep(700);
fs.writeFileSync(path.join(shots, 'chrome-api-status-B.png'), Buffer.from((await cmd('Page.captureScreenshot')).data, 'base64'));
const backendSaw = beLog.join('').split('\n').filter(l => l.includes('/api/cache HTTP'));
const out = { recorded: new Date().toString(), browser: version, url, httpVersion: ver, scope: 'single Mac, direct to backend.py over plain HTTP (not through the HTTPS edge)' + (ver === '1.1' ? '; handler unmodified, protocol_version raised to HTTP/1.1' : ''), rows, backendSaw };
fs.writeFileSync(path.join(root, 'evidence/06-caching/chrome-cache-http' + ver + '.json'), JSON.stringify(out, null, 2)); console.log(JSON.stringify(out, null, 1));
ws.close(); ch.kill(); be.kill(); await sleep(500); fs.rmSync(prof, { recursive: true, force: true }); process.exit(0);
