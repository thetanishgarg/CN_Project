#!/usr/bin/env python3
"""Builds evidence/EVIDENCE.html. All terminal panes are read from files; nothing is retyped."""
import base64, hashlib, html, json, pathlib, re, datetime
R = pathlib.Path(__file__).resolve().parents[2]; E = R/'evidence'; T = E/'test-results'
h = html.escape
BLUE, ORANGE, GOOD, CRIT, INK, MUTE, GRID = '#2a78d6', '#eb6834', '#0b7a3b', '#b3261e', '#14202e', '#5b6672', '#e3e7eb'
LAN, ONE, WIRE = ('lan', 'Recorded on the four-Mac LAN'), ('one', 'Recorded on one Mac'), ('wire', 'Packet capture')
figs = []
def badge(k): return f'<span class="badge {k[0]}">{k[1]}</span>'
def pane(path, a=1, b=None, kind=LAN, cap='', hl=(), drop=0):
    """a pane of verbatim lines a..b of a file"""
    ls = (R/path).read_text(errors='replace').replace('\r', '').splitlines()
    b = b or len(ls); sel = ls[a-1:b]
    figs.append(re.sub(r'\W+', '-', pathlib.Path(path).stem)); n = len(figs)
    body = []
    for l in sel:
        s = h(l)
        if re.search(r'\bPASS\b|: OK$|verify ok| HTTP 304|succeeded', l): s = f'<i class=ok>{s}</i>'
        elif re.search(r'\bFAIL\b|^error |verification failed|timed out|Failed to connect|Could not|^\S+\s+- ', l): s = f'<i class=bad>{s}</i>'
        elif l.startswith('$ ') or l.startswith('>>>'): s = f'<b>{s}</b>'
        elif any(x in l for x in hl): s = f'<mark>{s}</mark>'
        body.append(s)
    return (f'<figure class="fig{" long" if len(sel) > 22 else ""}" id="f{n}" data-name="{n:02d}-{figs[-1]}"><div class="bar"><span>{h(path)} &nbsp;lines {a}&ndash;{b}</span>{badge(kind)}</div>'
            f'<pre>{chr(10).join(body)}</pre><figcaption><b>Figure {n}.</b> {cap}</figcaption></figure>')
def find(path, pat, start=1):
    for i, l in enumerate((R/path).read_text(errors='replace').splitlines(), 1):
        if i >= start and re.search(pat, l): return i
    raise SystemExit(f'{pat} not in {path}')
def fig(svg, cap, name, kind=None, src=''):
    figs.append(name); n = len(figs)
    bar = f'<div class="bar light"><span>{h(src)}</span>{badge(kind) if kind else ""}</div>' if (src or kind) else ''
    return f'<figure class="fig chart" id="f{n}" data-name="{n:02d}-{name}">{bar}<div class="svg">{svg}</div><figcaption><b>Figure {n}.</b> {cap}</figcaption></figure>'
def img(path, cap, kind=ONE):
    d = base64.b64encode((R/path).read_bytes()).decode(); figs.append(pathlib.Path(path).stem); n = len(figs)
    return f'<figure class="fig shot" id="f{n}"><div class="bar"><span>{h(path)}</span>{badge(kind)}</div><img src="data:image/png;base64,{d}" alt=""><figcaption><b>Figure {n}.</b> {cap}</figcaption></figure>'
def table(head, rows, cls=''):
    return f'<table class="{cls}"><thead><tr>' + ''.join(f'<th>{x}</th>' for x in head) + '</tr></thead><tbody>' + ''.join('<tr>' + ''.join(f'<td>{c}</td>' for c in r) + '</tr>' for r in rows) + '</tbody></table>'
def ref(p): return f'<code>{h(p)}</code>'

# ------------------------------------------------------------------ diagrams
def topology():
    def box(x, y, w, t, lines, c=INK):
        s = f'<rect x="{x}" y="{y}" width="{w}" height="{34+15*len(lines)}" rx="6" fill="#fff" stroke="{c}" stroke-width="1.5"/><text x="{x+12}" y="{y+20}" font-weight="700" font-size="13" fill="{INK}">{t}</text>'
        return s + ''.join(f'<text x="{x+12}" y="{y+39+15*i}" font-size="11" fill="{MUTE}">{l}</text>' for i, l in enumerate(lines))
    def arr(d, t, x, y, anchor='middle'):
        return f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="1.6" marker-end="url(#a)"/><text x="{x}" y="{y}" font-size="11" fill="{INK}" text-anchor="{anchor}">{t}</text>'
    return (f'<svg viewBox="0 0 760 322"><defs><marker id="a" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0L8 4L0 8z" fill="{INK}"/></marker></defs>'
      '<rect x="4" y="4" width="752" height="314" rx="10" fill="#f6f8fa" stroke="#d5dbe1"/><text x="18" y="26" font-size="11" fill="#5b6672">One Wi-Fi network, 10.128.139.0/24, gateway 10.128.139.6</text>'
      + box(24, 128, 170, 'Client (Mac 4 or Mac 1)', ['curl, dig, Safari, tcpdump', 'trusts Team1 Local CA', 'DNS: Mac 1, then Mac 4'])
      + box(290, 44, 190, 'Mac 1 &#183; 10.128.139.224', ['Primary DNS, dnsmasq :53', 'A record TTL 30 s'])
      + box(290, 136, 190, 'Mac 2 &#183; 10.128.139.225', ['HTTPS edge, nginx :443', 'TLS 1.2/1.3, HTTP/2', 'round robin, retry'])
      + box(290, 244, 190, 'Mac 3 &#183; standby edge', ['nginx :443, same certificate'])
      + box(570, 70, 170, 'Mac 3 &#183; 10.128.139.70', ['Backend A :3001', 'pf: only the edges may enter'])
      + box(570, 186, 170, 'Mac 4 &#183; 10.128.139.68', ['Backend B :3002', 'Backup DNS :53'])
      + arr('M150 128 C170 80 230 74 286 74', '1 DNS query, UDP 53', 196, 66) + arr('M194 176 L286 176', '2 HTTPS :443', 240, 168)
      + arr('M480 164 L566 112', '3 HTTP', 514, 130, 'end') + arr('M480 188 L566 216', '3 HTTP', 534, 190, 'start')
      + f'<path d="M150 207 C180 270 230 272 286 270" fill="none" stroke="{MUTE}" stroke-width="1.4" stroke-dasharray="5 4" marker-end="url(#a)"/><text x="196" y="288" font-size="11" fill="{MUTE}" text-anchor="middle">after DNS cutover (Ext E)</text></svg>')

def ladder():
    """TLS 1.2 ladder drawn from the real frames of 05-wireshark/packet-ladder-tls12.txt"""
    txt = (E/'05-wireshark/packet-ladder-tls12.txt').read_text().splitlines()
    want = [(r'Standard query 0x5690 A ', 'DNS query: A app.team1.test?', 'c', 'DNS'), (r'response 0x5690', 'DNS answer: 10.202.54.225, TTL 30', 's', 'DNS'),
            (r'64537 → 443 \[SYN', 'SYN, Seq=0', 'c', 'TCP'), (r'443 → 64537 \[SYN, ACK', 'SYN-ACK, Seq=0 Ack=1', 's', 'TCP'), (r'64537 → 443 \[ACK\] Seq=1 ', 'ACK, Ack=1', 'c', 'TCP'),
            (r'Client Hello', 'ClientHello, SNI=app.team1.test', 'c', 'TLS'), (r'Server Hello, Certificate', 'ServerHello + Certificate', 's', 'TLS'), (r'Server Key Exchange', 'ServerKeyExchange + HelloDone', 's', 'TLS'),
            (r'Client Key Exchange', 'ClientKeyExchange, CCS, Finished', 'c', 'TLS'), (r'443 → 64537 .*|TLSv1.2 109 Change Cipher', None, 's', 'TLS'),
            (r'TLSv1.2 151 Application Data', 'Application Data: the encrypted GET', 'c', 'HTTP'), (r'TLSv1.2 265 Application Data', 'Application Data: the encrypted reply', 's', 'HTTP'),
            (r'64537 → 443 \[FIN', 'FIN', 'c', 'TCP')]
    want[9] = (r'TLSv1.2 109 Change Cipher', 'CCS, Finished', 's', 'TLS')
    col = {'DNS': '#6250d6', 'TCP': MUTE, 'TLS': BLUE, 'HTTP': ORANGE}; out = []; y = 58; t0 = None
    for pat, lab, side, lay in want:
        l = next(x for x in txt if re.search(pat, x)); fr, t = l.split()[:2]; t = float(t); t0 = t0 if t0 is not None else t
        x1, x2 = (210, 590) if side == 'c' else (590, 210)
        out.append(f'<text x="60" y="{y+4}" font-size="11" fill="{MUTE}" font-family="Menlo">{(t-t0)*1000:7.1f} ms</text><text x="150" y="{y+4}" font-size="10" fill="{MUTE}">#{fr}</text>'
                   f'<line x1="{x1}" y1="{y}" x2="{x2}" y2="{y}" stroke="{col[lay]}" stroke-width="2" marker-end="url(#m{lay})"/><text x="400" y="{y-5}" font-size="11.5" text-anchor="middle" fill="{INK}">{lab}</text>'
                   f'<text x="640" y="{y+4}" font-size="11" fill="{INK}">{lay}</text><rect x="624" y="{y-5}" width="9" height="9" rx="2" fill="{col[lay]}"/>'); y += 27
    mk = ''.join(f'<marker id="m{k}" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto"><path d="M0 0L8 4L0 8z" fill="{v}"/></marker>' for k, v in col.items())
    return (f'<svg viewBox="0 0 720 {y+6}"><defs>{mk}</defs><text x="210" y="20" font-size="12" font-weight="700" text-anchor="middle" fill="{INK}">Mac 4 10.202.54.68</text><text x="590" y="20" font-size="12" font-weight="700" text-anchor="middle" fill="{INK}">DNS .224 / edge .225</text>'
            f'<line x1="210" y1="28" x2="210" y2="{y-8}" stroke="{GRID}" stroke-width="2"/><line x1="590" y1="28" x2="590" y2="{y-8}" stroke="{GRID}" stroke-width="2"/>{"".join(out)}</svg>')

def convs():
    rows = []
    for l in (E/'05-wireshark/tcp-conversations.txt').read_text().splitlines():
        m = re.match(r'(10\.\S+)\s+<->\s+(\S+)\s+.*?(\d+) (\d+) bytes\s+([\d.]+)\s+([\d.]+)\s*$', l)
        if m: rows.append([f'<code>{m[1]}</code>', f'<code>{m[2]}</code>', 'TLS 1.2' if ':64537' in m[1] else 'TLS 1.3', m[3], m[4], f'{float(m[6])*1000:.0f} ms'])
    assert len(rows) == 6
    return '<h3>The six connections</h3>' + table(['Client socket', 'Edge socket', 'Version', 'Frames', 'Bytes', 'Duration'], rows) + '<p class="small">Six ephemeral client ports, always port 443 on the edge. Source: <code>evidence/05-wireshark/tcp-conversations.txt</code>; versions from each ServerHello.</p>'
# ------------------------------------------------------------------ charts from data
def ha():
    txt = (E/'10-ha-failover/ha-failover-120858.txt').read_text().splitlines(); pts, sec = [], 0
    for l in txt:
        if re.match(r'1\) ', l): sec = 1
        if 'Backend A DOWN' in l: sec = 2
        if '3) Waiting' in l: sec = 3
        m = re.match(r'\s+(\d\d:\d\d:\d\d)  (\d+|FAIL)  X-Backend: (\S+)\s+X-Edge: (\S+)\s+([\d.]+)s', l)
        if m: pts.append((sec, m[1], m[2], m[3], float(m[5])))
    assert len(pts) == 20 and all(p[2] == '200' for p in pts)
    W, x0, y0, H = 720, 58, 34, 190; step = (W-x0-20)/20; Y = lambda v: y0+H-v/1.4*H; s = ''
    for v in (0, .5, 1.0): s += f'<line x1="{x0}" x2="{W-10}" y1="{Y(v)}" y2="{Y(v)}" stroke="{GRID}"/><text x="{x0-8}" y="{Y(v)+4}" font-size="11" text-anchor="end" fill="{MUTE}">{v:.1f} s</text>'
    for i, lab in ((0, 'Both up'), (6, 'Backend A stopped'), (14, 'A restarted')):
        x = x0+i*step; s += (f'<line x1="{x}" x2="{x}" y1="{y0-14}" y2="{y0+H}" stroke="#b9c2cb" stroke-dasharray="3 3"/>' if i else '') + f'<text x="{x+6}" y="{y0-4}" font-size="11.5" font-weight="600" fill="{INK}">{lab}</text>'
    for i, (sc, t, st, b, v) in enumerate(pts):
        x = x0+(i+.5)*step; c = BLUE if b == 'A' else ORANGE; top = min(Y(v), y0+H-4)
        s += f'<path d="M{x-9} {y0+H} V{top+4} q0 -4 4 -4 H{x+5} q4 0 4 4 V{y0+H}Z" fill="{c}"><title>{t}  HTTP {st}  Backend {b}  {v:.3f}s</title></path><text x="{x}" y="{y0+H+15}" font-size="11" text-anchor="middle" fill="{INK}">{b}</text>'
    x = x0+6.5*step; s += f'<text x="{x+16}" y="{Y(1.219)+6}" font-size="11.5" fill="{INK}">1.219 s, still HTTP 200</text>'
    s += f'<rect x="{x0}" y="{y0+H+26}" width="10" height="10" rx="2" fill="{BLUE}"/><text x="{x0+15}" y="{y0+H+35}" font-size="11" fill="{INK}">answered by A</text><rect x="{x0+110}" y="{y0+H+26}" width="10" height="10" rx="2" fill="{ORANGE}"/><text x="{x0+125}" y="{y0+H+35}" font-size="11" fill="{INK}">answered by B</text>'
    return f'<svg viewBox="0 0 {W} {y0+H+44}">{s}</svg>'
def cutdata():
    S = []
    for l in (E/'12-edge-cutover/edge-cutover-121149.txt').read_text().splitlines():
        m = re.match(r'(\d\d):(\d\d):(\d\d)  (\S+)(?: \([^)]*\))?\s+(\S+)(?: \([^)]*\))?\s+(\S+)\s+(\S+)$', l)
        if m: S.append((int(m[1])*3600+int(m[2])*60+int(m[3]), m[4].split('.')[-1], m[5].split('.')[-1], m[6], m[7]))
    return S
def hms(t): return f'{t//3600:02d}:{t//60%60:02d}:{t%60:02d}'
def lanes(S, a, b, defs, ticks, height=30, marks=()):
    W, x0 = 720, 150; X = lambda t: x0+(t-a)/(b-a)*(W-x0-12); s = ''; y = 34 if marks else 8
    S = [r for r in S if a <= r[0] <= b]
    for lab, key, cmap in defs:
        s += f'<text x="{x0-10}" y="{y+height/2+4}" font-size="11.5" text-anchor="end" fill="{INK}">{lab}</text>'; i = 0
        while i < len(S):
            j = i
            while j+1 < len(S) and key(S[j+1]) == key(S[i]): j += 1
            e = S[j+1][0] if j+1 < len(S) else S[j][0]+2; c, name = cmap[key(S[i])]; w = X(min(e, b))-X(S[i][0])
            s += f'<rect x="{X(S[i][0]):.1f}" y="{y}" width="{max(w-2,1):.1f}" height="{height}" rx="3" fill="{c}"><title>{name}: {hms(S[i][0])} to {hms(e)}</title></rect>'
            if w > 62: s += f'<text x="{X(S[i][0])+8:.1f}" y="{y+height/2+4}" font-size="11.5" font-weight="600" fill="#fff">{name}</text>'
            i = j+1
        y += height+10
    for t in ticks: s += f'<line x1="{X(t):.1f}" x2="{X(t):.1f}" y1="{y-4}" y2="{y}" stroke="{MUTE}"/><text x="{X(t):.1f}" y="{y+14}" font-size="10.5" text-anchor="middle" fill="{MUTE}">{hms(t)}</text>'
    for t, lab, an in marks: s += f'<line x1="{X(t):.1f}" x2="{X(t):.1f}" y1="26" y2="{y-6}" stroke="{INK}" stroke-dasharray="3 3"/><text x="{X(t):.1f}" y="18" font-size="11" text-anchor="{an}" fill="{INK}">{lab}</text>'
    return f'<svg viewBox="0 0 {W} {y+22}">{s}</svg>'
def tests():
    runs = {}
    for f in sorted(T.glob('mac[24]-*.txt')):
        m = re.search(r'(\d+) passed\s+(\d+) failed\s+(\d+) warn', f.read_text()); p = f.stem.split('-'); runs.setdefault(p[0], []).append((p[2], *map(int, m.groups())))
    W = 720; s = ''; y = 22
    for mac, rs in runs.items():
        s += f'<text x="10" y="{y}" font-size="12.5" font-weight="700" fill="{INK}">{mac.replace("mac","Mac ")} test script</text>'; y += 10
        mx = max(p+f for _, p, f, w in rs); k = 470/mx
        for t, p, f, w in rs:
            wp, wf = p*k, f*k
            s += f'<text x="64" y="{y+12}" font-size="11" text-anchor="end" fill="{MUTE}">{t[:2]}:{t[2:4]}:{t[4:]}</text><rect x="72" y="{y+1}" width="{wp:.1f}" height="14" rx="3" fill="{GOOD}"><title>{p} passed</title></rect>'
            if f: s += f'<rect x="{74+wp:.1f}" y="{y+1}" width="{wf:.1f}" height="14" rx="3" fill="{CRIT}"><title>{f} failed</title></rect>'
            s += f'<text x="{82+wp+wf:.1f}" y="{y+12}" font-size="11" fill="{INK}">{p} passed, {f} failed' + (f', {w} warning' + 's'*(w > 1) if w else '') + '</text>'; y += 19
        y += 22
    s += f'<rect x="72" y="{y-12}" width="10" height="10" rx="2" fill="{GOOD}"/><text x="87" y="{y-3}" font-size="11" fill="{INK}">passed</text><rect x="142" y="{y-12}" width="10" height="10" rx="2" fill="{CRIT}"/><text x="157" y="{y-3}" font-size="11" fill="{INK}">failed</text>'
    return f'<svg viewBox="0 0 {W} {y+4}">{s}</svg>'

S = cutdata(); sec = lambda t: sum(int(x)*k for x, k in zip(t.split(':'), (3600, 60, 1)))
two = {'225': (BLUE, 'Mac 2'), '70': (ORANGE, 'Mac 3'), '55': ('#6b7480', '.55')}
edge = {'mac2-primary': (BLUE, 'Mac 2 edge'), 'mac3-standby': (ORANGE, 'Mac 3 edge'), '-': (CRIT, 'no answer')}
cut_svg = lanes(S, sec('12:12:10'), sec('12:15:02'), [('DNS server says', lambda r: r[1], two), ('Client cache uses', lambda r: r[2], two), ('Edge that answered', lambda r: r[3], edge)],
    [sec('12:12:10')+30*i for i in range(6)], marks=[(sec('12:12:40'), '12:12:40 record changed', 'end'), (sec('12:13:09'), '12:13:09 client moves (29 s)', 'start')])
inc_svg = lanes(S, sec('12:11:49'), sec('12:26:00'), [('DNS server says', lambda r: r[1], two), ('Client cache uses', lambda r: r[2], two), ('Edge that answered', lambda r: r[3], edge)], [sec('12:12:00')+120*i for i in range(7)])
cc10, cc11 = (json.loads((E/f'06-caching/chrome-cache-http{v}.json').read_text()) for v in ('1.0', '1.1'))
def ccell(r): return 'served from Chrome&rsquo;s disk cache, server not contacted' if not r['reachedServer'] else f'HTTP {r["wireStatus"]}, {r["bytesOnWire"]} bytes' + (', sent If-None-Match' if r['ifNoneMatch'] else '')

# ------------------------------------------------------------------ status matrix
P, PT, N = '<span class="st p">Proven</span>', '<span class="st pt">Partly proven</span>', '<span class="st n">Not recorded</span>'
matrix = [
 ('A', 'All Macs on one private LAN', P, 'Mac 2 and Mac 4 ping the other three', '01-lan/', 's-a'),
 ('B', 'Private DNS for team1.test', P, 'Right answer, NXDOMAIN, forwarding; packets captured', '02-dns/', 's-b'),
 ('C', 'Two backend services', P, 'Endpoints, headers, both names seen', '04-load-balancing/', 's-c'),
 ('D', 'Load balancing at the edge', P, 'A/B alternation in ten runs; strict in six', '04-load-balancing/', 's-d'),
 ('E', 'HTTPS with our own CA', P, 'Certificate from the wire verifies; no -k', '03-https/', 's-e'),
 ('F', 'HTTP caching', P, '304 through the edge; Chrome behaviour recorded', '06-caching/', 's-f'),
 ('G', 'Packet capture', P, 'DNS, TCP, TLS 1.2 and 1.3, Application Data', '05-wireshark/', 's-g'),
 ('6.3', 'Failure behaviour', P, 'Five failures with distinct signatures', '07-failures/', 's-63'),
 ('Ext A', 'Backup DNS', PT, 'Backup serves the same record; primary-down switch not recorded raw', '08-backup-dns/', 's-xa'),
 ('Ext B', 'Short TTL', P, 'TTL 30 on both servers; client held old answer 29 s', '09-ttl/, 12-edge-cutover/', 's-xb'),
 ('Ext C', 'Backend isolation', P, 'Client blocked while edge still serves; live pf rules not saved', '11-service-isolation/', 's-xc'),
 ('Ext D', 'Backend failover', P, '20 of 20 requests returned 200', '10-ha-failover/', 's-xd'),
 ('Ext E', 'Edge cutover by DNS', P, '84 of 84 samples returned 200 in the window', '12-edge-cutover/', 's-xe'),
 ('Ext F', 'Fault diagnosis', PT, 'Tool run; one real outage reconstructed; no timed drill saved', '13-troubleshooting/', 's-xf')]
np_, nt_ = sum(P == m[2] for m in matrix), sum(PT == m[2] for m in matrix)
tls12 = 'evidence/05-wireshark/packet-ladder-tls12.txt'; tls13 = 'evidence/05-wireshark/packet-ladder-tls13.txt'; dnsd = 'evidence/05-wireshark/dns-response-decoded.txt'
cv = 'evidence/05-wireshark/tls12-curl-output.txt'; cert = 'evidence/03-https/certificate-verification.txt'
m2f, m4f = 'evidence/test-results/mac2-20261123-232344.txt', 'evidence/test-results/mac4-20261123-232352.txt'
def secn(i, t, kicker=''): return f'<section id="{i}"><p class="kick">{kicker}</p><h2>{t}</h2>'
def claim(c, how): return f'<div class="claim"><p><b>Claim.</b> {c}</p><p><b>How it is proved.</b> {how}</p></div>'
X = []; a = X.append
a(f'''<header class="cover"><p class="kick">Computer Networks Capstone &#183; Team 1 &#183; team1.test</p><h1>Evidence of the Private Network Service Platform</h1>
<p class="lede">Four MacBooks, one Wi-Fi network: private DNS, a trusted HTTPS edge, two load-balanced backends, and a recorded proof of what happens when each part fails.</p>
<div class="tiles"><div><b>{np_} of {len(matrix)}</b><span>requirements fully proven, {nt_} partly</span></div><div><b>20 / 20</b><span>requests succeeded while Backend A was stopped and restarted</span></div><div><b>29 s</b><span>client moved to the standby edge, inside the 30 s TTL</span></div><div><b>24 / 24</b><span>edge checks passed, 23 Nov 23:23</span></div><div><b>44 / 44</b><span>client checks passed, one warning, 23 Nov 23:23</span></div></div>
{fig(topology(), 'The platform on the 23 November demo network. Arrows 1 to 3 are one request.', 'topology')}
<p class="small">Built {datetime.datetime.now():%d %B %Y, %H:%M}. Every terminal pane is loaded from the file named in its title bar, so any line can be checked against the repository.</p></header>''')
a(secn('s-read', 'How to read this file') + f'''<p>Each piece of evidence carries a label saying where it came from.</p>
{table(['Label', 'Meaning'], [[badge(LAN), 'Written by a script or tool while the four Macs shared one network, 22 and 23 November 2026.'], [badge(WIRE), 'Decoded with tshark from the capture taken on Mac 4 on 22 November 2026 at 21:21.'], [badge(ONE), 'Run on Mac 4 alone on 24 November 2026, when the team network was not available. Proves how a part behaves, not how the Macs interact.']])}
<p>The network changed between sessions, so addresses differ by date. All scripts read them from <code>config.env</code>.</p>
{table(['Session', 'Network', 'Used in'], [['22 Nov 2026', '10.202.54.0/24', 'Packet capture, curl -v'], ['23 Nov 2026', '10.128.139.0/24', 'All test runs, failover, cutover, backup DNS log'], ['24 Nov 2026', 'one Mac, loopback', 'Single-Mac recordings']])}
<h3>Requirement to evidence</h3>{table(['Task', 'Requirement', 'Status', 'What proves it', 'Folder'], [[f'<a href="#{m[5]}">{m[0]}</a>', m[1], m[2], m[3], ref(m[4])] for m in matrix], 'mx')}</section>''')
a(secn('s-flow', 'One request, end to end', 'Workflow') + '<p>This ladder is drawn from the timestamps of real captured packets: the client asks our DNS, opens TCP, completes TLS and only then sends HTTP. The number after each time is the frame in <code>team-traffic-only.pcap</code>.</p>'
  + fig(ladder(), 'One complete TLS 1.2 request from Mac 4, 22 November 21:21:28. Pure TCP acknowledgements are left out.', 'request-ladder', WIRE, tls12)
  + table(['Step', 'Layer', 'What happens', 'Where it is shown'], [['1', 'Application over UDP', 'Client asks Mac 1 for app.team1.test; gets the edge address, TTL 30', '<a href="#s-b">Task B</a>'], ['2', 'Transport', 'Three-way handshake to port 443 on Mac 2', '<a href="#s-g">Task G</a>'], ['3', 'TLS', 'Edge proves its identity with a certificate signed by Team1 Local CA', '<a href="#s-e">Task E</a>'], ['4', 'HTTP', 'nginx picks a backend by round robin and adds X-Edge and X-Upstream', '<a href="#s-d">Task D</a>'], ['5', 'HTTP', 'Backend answers with X-Backend and its caching rules', '<a href="#s-f">Task F</a>']]) + '</section>')
a(secn('s-a', 'Task A: one private LAN', 'Phase 1') + claim('All four Macs share one subnet and reach each other at layer 3.', 'Each test script pings the other three Macs and prints its own interface facts.')
  + pane('evidence/01-lan/lan-reachability-recorded.txt', 4, None, LAN, 'Mac 2 and Mac 4 share mask 255.255.255.0 and gateway 10.128.139.6, and each reaches the other three.', hl=('interface en0',))
  + pane('evidence/01-lan/mac1-network-info.txt', 12, 22, LAN, 'Mac 1 on the first network, 22 November, a phone hotspot used as the shared LAN.')
  + '<p class="note">Layer 2 cross-check: in the 22 November packet capture the TLS traffic is exchanged with Ethernet address 7e:45:9b:f9:71:19, the address Mac 2 prints for itself above on 23 November. The edge on the wire really is Mac 2.</p></section>')
i0 = find(dnsd, 'Domain Name System')
a(secn('s-b', 'Task B: private DNS', 'Phase 1') + claim('Our own server answers for team1.test, refuses unknown names in the zone, and forwards everything else.', 'A client&rsquo;s checks, the decoded DNS packet, and the server&rsquo;s own query log.')
  + pane('evidence/02-dns/dns-recorded.txt', 4, None, LAN, 'Mac 4 as a client: the answer comes from Mac 1, port 53.')
  + pane(dnsd, i0, find(dnsd, r'\[Time:'), WIRE, 'The DNS answer on the wire: authoritative, A record for the edge, time to live 30 seconds.', hl=('Authoritative: Server is', 'Time to live', 'Address:'))
  + pane('evidence/02-dns/dns-local.txt', find('evidence/02-dns/dns-local.txt', r'app.team1.test$'), None, ONE, 'The same dnsmasq directives on one Mac: full dig output, NXDOMAIN, forwarding, DNS over TCP, and the query log.', hl=('NXDOMAIN', 'IN\tA\t')) + '</section>')
bl = 'evidence/04-load-balancing/backends-local.txt'
a(secn('s-c', 'Task C: the two backends', 'Phase 1') + claim('One program, started twice, gives two distinguishable services.', 'Raw responses from each process, including the 404 path and the listening sockets.')
  + pane(bl, 5, find(bl, r'^\$ curl -si http://127.0.0.1:3002/$')-1, ONE, 'Same endpoint, different X-Backend. <code>no-store</code> keeps load balancing visible to a browser.', hl=('X-Backend',))
  + pane(bl, find(bl, r'/nope$'), None, ONE, 'An unknown path gives a proper 404, and both sockets listen on all interfaces so the edge can reach them.', hl=('404',))
  + img('evidence/screenshots/chrome-api-status-B.png', 'Screenshot of real Google Chrome showing Backend B&rsquo;s live reply.') + '</section>')
a(secn('s-d', 'Task D: load balancing', 'Phase 1') + claim('The edge spreads requests over both backends by round robin.', 'The X-Backend header of consecutive requests through the edge, in every recorded run that reached it.')
  + pane('evidence/04-load-balancing/round-robin-recorded.txt', 4, None, LAN, 'Six of ten runs alternate strictly. The other four still used both backends but not in strict turn.')
  + '<p class="note">Likely reasons for the uneven runs: nginx keeps one rotation for all clients, so another Mac&rsquo;s requests fall between ours (the 11:58:02 runs on Mac 2 and Mac 4 carry the same time stamp), and a backend that just failed is skipped for 10 seconds. The nginx logs that would settle it were not saved. The last three runs of the day alternate strictly.</p></section>')
a(secn('s-e', 'Task E: HTTPS with our own CA', 'Phase 1') + claim('The edge presents a valid certificate from Team1 Local CA and clients accept it without -k.', 'The certificate was taken out of the captured packets and verified again here, including cases that must fail.')
  + pane(cert, find(cert, r'^\$ openssl x509 -in evidence/03'), find(cert, 'Alternative') + 1, WIRE, 'The certificate the edge really sent (frame 57 of full-flow.pcap).', hl=('subject=', 'issuer=', 'DNS:', 'Server Authentication'))
  + pane(cert, find(cert, r'^\$ openssl verify'), find(cert, r'^\$ openssl x509 -in team1') - 1, ONE, 'Verified against our CA: OK for both names, rejected for another name, rejected without our CA. The two failures show that the trust is real.')
  + pane(cv, find(cv, 'ALPN: curl'), find(cv, 'verify ok') , LAN, 'The same handshake as curl on Mac 4 saw it: certificate verify ok, HTTP/2 agreed through ALPN.')
  + pane('evidence/03-https/https-recorded.txt', 4, None, LAN, 'Final test runs: TLS 1.2 and 1.3, HTTP/2 and HTTP/1.1, both names, checked from the edge and from a client.') + '</section>')
cl = 'evidence/06-caching/caching-local.txt'
a(secn('s-f', 'Task F: HTTP caching', 'Phase 1') + claim('A client can reuse a response for 60 seconds, then revalidate it for free, whichever backend answers.', 'Conditional requests through the edge, the same ETag on both backends, and what Chrome itself did.')
  + pane('evidence/06-caching/caching-recorded.txt', 4, None, LAN, 'Through the HTTPS edge: 4 of 4 conditional requests answered 304.')
  + pane(cl, 5, find(cl, 'Wrong ETag') + 1, ONE, 'Both backends produce the same ETag, so a tag from A is valid at B. A wrong ETag correctly gets the full body.', hl=('ETag:',))
  + table(['Step in real Chrome', 'HTTP/1.1 reply (as behind the edge)', 'HTTP/1.0 reply (backend/backend.py directly)'], [[h(x['step']), ccell(x), ccell(y)] for x, y in zip(cc11['rows'], cc10['rows'])])
  + f'<p class="small">{h(cc11["browser"])}, recorded through the DevTools protocol on one Mac over plain HTTP. Files: <code>chrome-cache-http1.1.json</code>, <code>chrome-cache-http1.0.json</code>.</p>'
  + '<p class="note">Finding: Chrome did not revalidate an HTTP/1.0 response, and Python&rsquo;s server speaks HTTP/1.0. Behind nginx the browser receives HTTP/2, so revalidation works. To show 304 in a browser, open the site through the edge, not the backend port.</p>'
  + img('evidence/screenshots/chrome-api-cache.png', 'Screenshot of real Google Chrome on /api/cache.') + '</section>')
a(secn('s-g', 'Task G: the packets', 'Phase 1') + claim('Every layer is visible on the wire, and the HTTP content is not.', 'A capture on Mac 4 filtered to team traffic: 178 packets, six connections, one TLS 1.2 and five TLS 1.3.')
  + pane(tls12, find(tls12, 'tcp.port==64537') , find(tls12, 'tcp.port==64537') + 17, WIRE, 'TLS 1.2 connection from port 64537: handshake, then Certificate in clear, then Application Data only.', hl=('SYN', 'Client Hello', 'Certificate', 'Key Exchange'))
  + pane(tls13, 1, 15, WIRE, 'TLS 1.3 connection from port 64538: nothing readable after ServerHello, the certificate included, and one round trip fewer.', hl=('SYN', 'Client Hello', 'Server Hello'))
  + convs()
  + table(['To check in Wireshark', 'Display filter'], [['The DNS exchange', '<code>dns</code>'], ['The three-way handshakes', '<code>tcp.flags.syn==1</code>'], ['The certificate in clear (TLS 1.2 only)', '<code>tls.handshake.type==11</code>'], ['Encrypted HTTP', '<code>tls.record.content_type==23</code>']]) + '</section>')
fs = 'evidence/07-failures/failure-signatures-local.txt'
a(secn('s-63', 'Section 6.3: how each failure looks', 'Phase 1') + claim('Each broken layer fails differently, so the symptom names the layer.', 'Recorded checks on the LAN plus the raw error messages.')
  + pane('evidence/07-failures/failures-recorded.txt', 4, None, LAN, 'Wrong DNS server, wrong address, wrong port, one backend dead, both dead. The last two ran on a private copy of the edge on port 18443.')
  + pane(fs, 5, None, ONE, 'Raw error text and curl exit codes: 6 is DNS, 7 is TCP, 35 is TLS.')
  + table(['Symptom', 'Layer', 'Meaning'], [['curl exit 6', 'DNS', 'No address, so no connection was even tried'], ['curl exit 7, refused at once', 'TCP', 'Host is up, nothing listens on that port'], ['curl exit 28, timeout', 'IP or firewall', 'Silence: host gone or packets dropped'], ['curl exit 35 or 60', 'TLS', 'Handshake broken, or certificate not trusted'], ['HTTP 502', 'HTTP', 'Edge is healthy, no backend answered']]) + '</section>')
bd = 'evidence/08-backup-dns/backup-dns-log-excerpt.txt'
a(secn('s-xa', 'Extension A: backup DNS', 'Phase 2') + claim('Mac 4 can answer for the zone when Mac 1 cannot.', 'Both servers checked on the LAN, the backup&rsquo;s own log, and a one-Mac run where the primary is killed.')
  + pane('evidence/08-backup-dns/backup-dns-recorded.txt', 4, None, LAN, 'Same record and same TTL from both servers; the client lists both.')
  + pane(bd, 5, find(bd, r'dns.log:29'), LAN, 'The backup&rsquo;s log: it answered 2574 queries for Mac 1 and 1182 for Mac 4. Ordinary browsing names are left out.', hl=('Mac 1', 'Mac 4'))
  + pane('evidence/08-backup-dns/backup-dns-local.txt', 5, None, ONE, 'Primary killed: it times out, the backup still answers with the same record.')
  + f'<p class="gap"><b>Still to record.</b> A raw dig on the LAN with Mac 1 stopped. An earlier hand-made output was removed from the repository because it could not be traced to a recording. Run <code>capture-lan.sh failover</code>.</p></section>')
a(secn('s-xb', 'Extension B: short TTL', 'Phase 2') + claim('A 30-second TTL bounds how long clients keep an old answer.', 'The TTL in the captured packet, the TTL check on both servers, and a client that kept the old address for 29 seconds.')
  + pane('evidence/09-ttl/ttl-local.txt', 5, None, ONE, 'Server side: the record changes and dig sees the new address at once, TTL 30.')
  + '<p>Client side: in the cutover below, the DNS server changed at 12:12:40 and the client&rsquo;s cache changed at 12:13:09. Between the two, dig and the application disagreed, exactly as a cache should behave.</p>'
  + f'<p class="gap"><b>Note.</b> An earlier hand-made TTL output was removed from the repository for the same reason; the cutover recording above replaces it.</p></section>')
a(secn('s-xc', 'Extension C: backend isolation', 'Phase 2') + claim('Only the edges may connect to a backend port.', 'In two runs started 37 seconds apart: the edge reaches both backends, a client is blocked from Backend A, and the same client still gets answers from A through the edge. A dead backend could not produce that combination.')
  + pane('evidence/11-service-isolation/isolation-recorded.txt', 4, None, LAN, 'Firewall on, firewall off, and two runs that are deliberately not counted.')
  + pane('firewall/backend-firewall.sh', find('firewall/backend-firewall.sh', 'team1-backend anchor'), find('firewall/backend-firewall.sh', 'team1-backend anchor') + 16, ('code', 'Source code'), 'The rules the script loads into the pf anchor: pass loopback, pass the two edges, drop everyone else.', hl=('block', 'pass'))
  + '<p class="gap"><b>Still to record.</b> The live rule listing (<code>capture-lan.sh firewall</code>), and the same proof for Backend B on Mac 4.</p></section>')
hf = 'evidence/10-ha-failover/ha-failover-120858.txt'
a(secn('s-xd', 'Extension D: backend failover', 'Phase 2') + claim('A backend can die and return without a client seeing an error.', '20 requests through the edge while Backend A was stopped and restarted, 23 November 12:08:58 to 12:09:53.')
  + fig(ha(), 'Response time of each request, in order. All 20 returned 200. The slow one is the first after A stopped, which fits nginx trying A, then retrying on B; later requests skip A.', 'failover-latency', LAN, hf)
  + pane(hf, 1, 32, LAN, 'The raw recording.') + '</section>')
a(secn('s-xe', 'Extension E: edge cutover by DNS', 'Phase 2') + claim('Traffic moves from the primary to the standby edge by changing one DNS record, with no failed request.', 'A client sampled the DNS answer, its own cache and the edge that replied about every 2.2 seconds.')
  + fig(cut_svg, 'The server changes first, the client&rsquo;s cache 29 s later, and the answering edge follows the cache. 84 of 84 samples from 12:11:49 to 12:15:02 returned 200.', 'edge-cutover', LAN, 'evidence/12-edge-cutover/edge-cutover-121149.txt')
  + pane('evidence/12-edge-cutover/edge-cutover-121149.txt', 23, 40, LAN, 'The raw rows around both changes.', hl=('mac3-standby',))
  + '<p class="note">Switching back exposed a real weakness. The record returned to Mac 2 at 12:14:31, the client followed at 12:15:04, and every request then failed. A test at 12:20 found the primary edge not serving. Lesson: check the target edge before moving traffic to it. The next section covers that outage.</p></section>')
dg = 'evidence/13-troubleshooting/diagnose-no-lan.txt'; inc = 'evidence/13-troubleshooting/incident-20261123.txt'
a(secn('s-xf', 'Extension F: diagnosing a fault', 'Phase 2') + claim('We can find the failing layer from evidence.', 'A real outage during testing, reconstructed from three files written independently, plus a run of the diagnostic tool.')
  + fig(inc_svg, 'The same watcher file over 14 minutes. Red is no answer: 12:15:04 to 12:23:42. Grey is an address that belongs to none of the four Macs.', 'outage-timeline', LAN, 'evidence/12-edge-cutover/edge-cutover-121149.txt')
  + table(['Layer', 'Evidence during the outage', 'Verdict'], [['IP', 'Mac 2 and Mac 4 both ping the other Macs', 'Healthy'], ['DNS', 'Primary answers 10.128.139.55; backup answers 10.128.139.225', '<b>Fault 1:</b> wrong record on the primary'], ['TCP 443', 'Mac 2 reports nginx is not serving; curl exit 7', '<b>Fault 2:</b> primary edge down'], ['Backend', 'Mac 2 cannot reach Backend A, reaches Backend B', '<b>Fault 3:</b> Backend A unreachable from the edge'], ['Standby', 'Mac 3 edge answers with a valid certificate', 'Healthy, and was the way out']])
  + pane(inc, 4, None, LAN, 'The three sources side by side, then the recovery.')
  + pane(dg, 5, None, ONE, 'The tool run without the team network: it stops at the first failing layer, names it and gives the fix.')
  + '<p class="gap"><b>Still to record.</b> A timed drill: one hidden fault, diagnosed and fixed, with before and after output (<code>capture-lan.sh drill</code>), and a healthy five-layer run.</p></section>')
a(secn('s-tests', 'Test history', 'Results') + '<p>Every saved run of the two scripts on 23 November, failures included. Red early runs are stale addresses and services not yet started; 12:20 is the outage above.</p>' + fig(tests(), 'Saved automated runs, in time order.', 'test-history', LAN, 'evidence/test-results/')
  + pane(m2f, 14, 46, LAN, 'Final Mac 2 run, from the certificate section on.') + pane(m4f, find(m4f, 'Ext E - standby'), None, LAN, 'End of the final Mac 4 run. The one warning: the firewall was off at that moment.')
  + '<p class="gap"><b>Not counted.</b> The only file named mac1 was run on Mac 2 by mistake (it says so in its first check) and has 13 failures. No mac3 run is saved. Both need one run on the right machine.</p></section>')
a(secn('s-gaps', 'What is still missing', 'Open items') + '<p>Nothing here is claimed as done. One session with all four Macs closes it; each row is one command.</p>'
  + table(['Missing', 'Who', 'Command'], [['Ping matrix and interface facts from every Mac', 'all', '<code>capture-lan.sh lan</code>'], ['Full dig, curl -v, 20 balanced requests, 304 through the edge', 'Mac 4', '<code>capture-lan.sh client</code>'], ['Backup DNS switch with Mac 1 stopped', 'Mac 4, Mac 1', '<code>capture-lan.sh failover</code>'], ['Live pf rules', 'Mac 3, Mac 4', '<code>sudo capture-lan.sh firewall</code>'], ['Timed fault drill', 'Mac 4 + one', '<code>capture-lan.sh drill</code>'], ['Test runs from Mac 1 and Mac 3', 'Mac 1, Mac 3', '<code>tests/test-mac1.sh</code>, <code>tests/test-mac3.sh</code>'], ['Window screenshots: Wireshark, Safari padlock', 'Mac 4', 'save as PNG in <code>evidence/screenshots/manual/</code>']])
  + '<p>Scripts are in <code>evidence/build/</code>. Run <code>build.sh</code> afterwards to rebuild this file.</p></section>')
man = sorted((E/'screenshots/manual').glob('*.png')) if (E/'screenshots/manual').exists() else []
if man: a(secn('s-man', 'Window screenshots', 'Screenshots') + ''.join(img(str(p.relative_to(R)), h(p.stem.replace('-', ' ')), ('code', 'Screenshot by the team')) for p in man) + '</section>')
skip = {'EVIDENCE.html', 'EVIDENCE.pdf', 'MANIFEST.sha256'}
fl = [p for p in sorted(E.rglob('*')) if p.is_file() and p.name not in skip and 'screenshots' not in p.parts and p.name != '.DS_Store' and '__pycache__' not in p.parts]
(E/'MANIFEST.sha256').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(E)}\n' for p in fl))
key = [p for p in fl if p.suffix in ('.pcap', '.txt', '.pem', '.json')]
a(secn('s-man2', 'File fingerprints', 'Appendix') + f'<p>First 16 hex digits of each evidence file&rsquo;s SHA-256. The full list is in <code>MANIFEST.sha256</code>; check it with <code>cd evidence &amp;&amp; shasum -a 256 -c MANIFEST.sha256</code>.</p>' + table(['File', 'Bytes', 'SHA-256'], [[ref(str(p.relative_to(E))), f'{p.stat().st_size:,}', f'<code>{hashlib.sha256(p.read_bytes()).hexdigest()[:16]}</code>'] for p in key], 'man') + '</section>')
toc = ''.join(f'<li><a href="#{i}">{t}</a></li>' for i, t in re.findall(r'<section id="([^"]+)"><p class="kick">[^<]*</p><h2>([^<]*)</h2>', ''.join(X)))
CSS = '''@page{size:A4;margin:15mm 14mm 16mm;@bottom-left{content:"Team 1  Evidence";font:8pt "Helvetica Neue";color:#5b6672}@bottom-right{content:counter(page) " / " counter(pages);font:8pt "Helvetica Neue";color:#5b6672}}
*{box-sizing:border-box}body{font:10.2pt/1.5 "Helvetica Neue",Arial,sans-serif;color:#14202e;background:#fff;margin:0 auto;max-width:860px;padding:28px 22px}
h1{font-size:28pt;line-height:1.1;letter-spacing:-.02em;margin:.2em 0 .35em;text-wrap:balance;max-width:16em}h2{font-size:19pt;letter-spacing:-.01em;line-height:1.2;margin:.1em 0 .5em}h3{font-size:12.5pt;margin:1.4em 0 .4em}
p{margin:.5em 0 .8em;max-width:76ch}.lede{font-size:13pt;line-height:1.45;color:#3b4754}.kick{color:#0f6b64;font-weight:600;margin:0 0 .2em;font-size:9.5pt}.small{font-size:8.8pt;color:#5b6672}
section{padding-top:4px;margin-top:30px}h2,h3,.kick,.claim{break-after:avoid}.claim{break-inside:avoid}#s-flow,#s-a,#s-63,#s-xa,#s-xd,#s-xf,#s-tests,#s-gaps,#s-man2{break-before:page}.toc{margin-top:10px;font-size:9.4pt}.toc h2{font-size:14pt;margin-bottom:.2em}.toc ol{columns:2;column-gap:34px;padding-left:1.3em;margin:.4em 0}.toc li{margin:.2em 0;break-inside:avoid}a{color:#0f4fa8;text-decoration:none}
.tiles{display:grid;grid-template-columns:repeat(5,1fr);gap:0;border-block:1.5px solid #14202e;margin:18px 0}.tiles div{padding:11px 12px 12px 0}.tiles div+div{border-left:1px solid #d5dbe1;padding-left:12px}.tiles b{display:block;font-size:18pt;letter-spacing:-.02em;white-space:nowrap}.tiles span{font-size:8.4pt;line-height:1.35;display:block;color:#3b4754}
td:nth-child(2){min-width:5.5em}table{border-collapse:collapse;width:100%;margin:.7em 0 1.1em;font-size:9pt}th{text-align:left;border-bottom:1.5px solid #14202e;padding:5px 10px 5px 0;font-weight:600}td{border-bottom:1px solid #e3e7eb;padding:5px 10px 5px 0;vertical-align:top}tr{break-inside:avoid}table.mx{font-size:8.5pt}table.mx td{padding:3.5px 8px 3.5px 0}table.mx code{font-size:7pt}table.mx td:nth-child(1),table.mx td:nth-child(3){white-space:nowrap}table.man{font-size:6.6pt;line-height:1.2}table.man td{padding:.7px 8px 1.3px 0}code{font:.88em Menlo,monospace;overflow-wrap:anywhere}
.st{font-weight:600}.st:before{content:"";display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px}.st.p:before{background:#0b7a3b}.st.pt:before{background:#eda100}.st.n:before{background:#b3261e}
.fig{margin:14px 0 16px;border:1px solid #c9d1d9;border-radius:7px;overflow:hidden;background:#fff;break-inside:avoid}.bar{display:flex;justify-content:space-between;align-items:center;gap:12px;background:#1d2833;color:#dfe6ec;padding:6px 11px;font:7.8pt Menlo,monospace}.bar.light{background:#f1f4f7;color:#3b4754;border-bottom:1px solid #d5dbe1}.bar span:first-child{overflow-wrap:anywhere}
.badge{font:600 7.6pt "Helvetica Neue",Arial,sans-serif;padding:2px 8px;border-radius:9px;white-space:nowrap;background:#dfe6ec;color:#14202e}.badge.lan{background:#cdeedd;color:#064d25}.badge.wire{background:#d6e6fb;color:#0b3a78}.badge.one{background:#fbe6c4;color:#5c3a00}
pre{margin:0;padding:10px 12px;background:#0f1720;color:#d7dee5;font:7.5pt/1.48 Menlo,monospace;white-space:pre-wrap;overflow-wrap:anywhere}pre i{font-style:normal}pre .ok{color:#7ee2a8}pre .bad{color:#ff9d94}pre b{color:#8fc4ff;font-weight:600}pre mark{background:#2b3a18;color:#e6f5b0}
figcaption{padding:7px 11px;font-size:8.8pt;color:#3b4754;border-top:1px solid #e3e7eb;background:#fafbfc}.svg{padding:12px}.svg svg{display:block;width:100%;height:auto;font-family:"Helvetica Neue",Arial,sans-serif}.shot img{display:block;width:100%;border-bottom:1px solid #e3e7eb}
.claim{border-top:1.5px solid #14202e;border-bottom:1px solid #d5dbe1;padding:7px 0;margin:.4em 0 1em}.claim p{margin:.25em 0}.note,.gap{background:#f1f4f7;border-radius:6px;padding:9px 12px;font-size:9.2pt;max-width:none;break-inside:avoid}.gap{background:#fdf3df}
@media print{body{max-width:none;padding:0;-webkit-print-color-adjust:exact;print-color-adjust:exact}.fig.long{break-inside:auto}.fig.long pre{box-decoration-break:clone;-webkit-box-decoration-break:clone}.bar{break-after:avoid}figcaption{break-before:avoid}}
@media(max-width:640px){.tiles{grid-template-columns:1fr 1fr}.toc ol{columns:1}table{display:block;overflow-x:auto}}'''
cover = X[0]; doc = f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Team 1 Evidence</title><style>{CSS}</style></head><body>{cover}<nav class="toc"><h2>Contents</h2><ol>{toc}</ol></nav>{"".join(X[1:]).replace("<section id=\"s-read\">", "<section id=\"s-read\" style=\"break-before:page\">", 1)}</body></html>'
(E/'EVIDENCE.html').write_text(doc); print(len(figs), 'figures,', len(fl), 'files hashed')
