# PHASE 2 REPORT — Computer Networks Project
## Team 1 | Mac 4 (Integration Owner / Test Client / Backup DNS)

> **Status:** Extensions A to F are implemented. Learning summaries are kept next to the work they describe and linked from §5; the Ext F summary and a timed fault drill are still to be written and recorded.  
> **Evidence:** start with `evidence/EVIDENCE.pdf`; `evidence/README.md` maps each numbered folder to its requirement.

---

## 1. What Changed from Phase 1

| Aspect | Phase 1 | Phase 2 |
|--------|---------|---------|
| DNS | Single server on Mac 1 (Python fallback) | Dual DNS: Mac 1 primary + **Mac 4 backup** (Ext A) |
| DNS TTL | Unspecified (long) | **30 s** (Ext B) — fast failover, reduced stale cache |
| Edge / nginx | Single instance on Mac 2 | Mac 2 primary + **Mac 3 standby** (Ext E) |
| Backend security | No firewall; any host can hit :3001/:3002 | **pf anchor** restricts backend ports to edge IPs only (Ext C) |
| Observability | Basic curl tests | Layer-by-layer `diagnose.sh` + mock fault drill (Ext F) |
| Evidence | 01-07 folders | Extended to **08-13** (see index below) |
| DNS records target | Always `MAC2_IP` | `APP_TARGET_IP` variable — toggled during Ext E cutover |

---

## 2. Resilience Test Results (by Extension)

### Ext A — Backup DNS (Mac 4)

**What was done:**
- Installed `dnsmasq` on Mac 4.
- Ran Mac 1's `dns/start-dns.sh` unchanged — same script, same records, generated from `config.env`.
- Configured client DNS with **both servers** (Mac 1 first, Mac 4 second) using `dns/set-client-dns.sh set`.

**What the saved files show:**
- Both servers return the same record and TTL (`evidence/08-backup-dns/backup-dns-recorded.txt`).
- Mac 4's dnsmasq log shows it answering real queries (`backup-dns-log-excerpt.txt`).
- With the primary process killed, the backup still answers (`backup-dns-local.txt`, a one-Mac run).
- Not yet recorded: a raw `dig` on the LAN with Mac 1 stopped, showing `;; SERVER:` as Mac 4. Run `evidence/build/capture-lan.sh failover`.

**Evidence:** `evidence/08-backup-dns/`

**macOS DNS note:**  
`scutil --dns` shows macOS lists multiple resolvers and **rotates / parallelises** queries. When Mac 1 stops responding, the OS retries on Mac 4 within the timeout window. This is not true round-robin — Mac 1 is still tried first if reachable.

**Learning summary:** see [ARCHITECTURE.md](ARCHITECTURE.md), section 7, Extension A.

---

### Ext B — Short TTL (30 s)

**What was done:**
- `DNS_TTL=30` in `config.env`; `start-dns.sh` injects this into dnsmasq `local-ttl`.
- Demonstrated cache expiry: queried `app.team1.test`, waited 30 s, then showed stale entry gone.

**Evidence:** `evidence/09-ttl/ttl-local.txt` (server side) and `evidence/12-edge-cutover/` (the client's cache holding the old answer for 29 s).

**Learning summary:** see [ARCHITECTURE.md](ARCHITECTURE.md), section 7, Extension B.

---

### Ext C — Service Isolation / Firewall (Mac 4 Backend B :3002)

**What was done:**
- Applied `firewall/backend-firewall.sh` (Mac 3's script) on Mac 4 for port 3002.
- Used `mac4-ext-c-firewall.sh apply` → delegates without editing the shared script.
- Verified: the edge (Mac 2) can reach `:3002`; any other host gets a silent drop, so its connection times out (`evidence/11-service-isolation/isolation-recorded.txt`).
- Removed firewall after demo: `sudo ./mac4-ext-c-firewall.sh remove`.

**pf anchor used:** `com.apple/team1-backend` (macOS only evaluates anchors under `com.apple/`)  
**Rules:** allow from MAC2_IP, allow from STANDBY_EDGE_IP, block drop all others.

**Evidence:** `evidence/11-service-isolation/`

**Learning summary:** see [evidence/11-service-isolation/ext-c-learning-summary.md](evidence/11-service-isolation/ext-c-learning-summary.md).

---

### Ext D — Backend high-availability failover (Mac 2)

**What was done:** nginx passive health check (`max_fails=1 fail_timeout=10s`) plus `proxy_next_upstream`, so a request that reaches a stopped backend is retried on the other one.

**Result:** 20 of 20 requests returned 200 while Backend A was stopped and restarted (`evidence/10-ha-failover/ha-failover-120858.txt`).

**Learning summary:** see [MAC2-PHASE2.md](MAC2-PHASE2.md).

### Task F — Caching (carried over from Phase 1)

**Evidence:** `evidence/06-caching/`  
**Result:** the ETag is identical on A and B and conditional requests get `304 Not Modified`, both through the edge and directly.

---

### Ext E — Standby Edge / Hot Cutover (Mac 3)

**What was done:**
- Mac 3 ran `mac3-standby-edge.sh` to bring up a second nginx instance.
- Mac 1 updated `APP_TARGET_IP` → `MAC3_IP` and restarted DNS (TTL=30s, so switch propagated in ≤30 s).
- Clients now reach Mac 3's nginx (same certs, same backends).
- Cutover verified on 23 Nov: the DNS server changed at 12:12:40, the client's cache followed at 12:13:09 (29 s), and 84 of 84 samples in that window returned 200.

**Evidence:** `evidence/12-edge-cutover/` (summary in `cutover-transitions.txt`)

**Learning summary:** see [MAC2-PHASE2.md](MAC2-PHASE2.md).

---

### Ext F — Faculty-Injected Fault Drill (Mac 4)

**What was done:**
- Built `troubleshoot/diagnose.sh` — 5-layer check (DNS → IP → TCP → TLS → HTTP).
- Built `troubleshoot/RUNBOOK.md` — fault table with 12 injected faults, symptoms, proof commands, fixes.
- Ran mock drill: teammate secretly broke one thing → ran `diagnose.sh` → stopped at correct layer → named cause + fix.

**Drill result:** no timed drill is saved yet (`evidence/build/capture-lan.sh drill` records one). `evidence/13-troubleshooting/incident-20261123.txt` reconstructs a real outage on 23 Nov from three independent logs, and `diagnose-no-lan.txt` shows the tool stopping at layer 1.

**Evidence:** `evidence/13-troubleshooting/`

**Learning summary:**
> _[To be added]_

---

## 3. Troubleshooting Findings

**Key insight from the drill:**  
The 5-layer model maps perfectly to real failures:
- Layer 1 (DNS): 4 out of 12 fault types are DNS-layer. The most confusing one — wrong IP from DNS — passes Layer 1 "resolved" check but fails Layer 4 TLS (SNI mismatch). `diagnose.sh` catches this by comparing resolved IP to `$APP_TARGET_IP`.
- Layer 3 (TCP): The fastest to diagnose — `nc -vz` either connects in <1 s or fails. Distinguishes "nginx down" from "IP reachable but nothing listening".
- Layer 5 (HTTP 502): The most ambiguous at first glance — could be one or both backends. `diagnose.sh` does a direct HTTP check on both backend IPs to pinpoint which one is down.

**macOS-specific nuance:**  
`/usr/bin/curl` uses LibreSSL which ignores the macOS Keychain. The `~/.curlrc` with `cacert = ~/cn-ca-bundle.pem` is the correct fix — not `-k`. This was validated in Phase 1 and carried forward.

---

## 4. Evidence Index (find any item in < 30 s)

| Folder | Extension | Contents |
|--------|-----------|---------|
| `evidence/01-lan/` | LAN setup | interface facts and pings from Mac 2 and Mac 4 |
| `evidence/02-dns/` | Phase 1 DNS | dig proofs, failure demos |
| `evidence/03-https/` | Phase 1 HTTPS | certificate taken from the capture and verified |
| `evidence/04-load-balancing/` | Load balancing | X-Backend alternating log |
| `evidence/05-wireshark/` | Packet capture | full-flow.pcap, filtered capture, decoded packets |
| `evidence/06-caching/` | Caching (Ext D) | ETag + 304 responses |
| `evidence/07-failures/` | Phase 1 failures | recorded failure checks and raw error signatures |
| `evidence/08-backup-dns/` | **Ext A** | both servers' answers, backup DNS log excerpt |
| `evidence/09-ttl/` | **Ext B** | server-side TTL change (client side is in 12) |
| `evidence/10-ha-failover/` | **Ext D** | backend failover recording |
| `evidence/11-service-isolation/` | **Ext C** | blocked and allowed connection proofs |
| `evidence/12-edge-cutover/` | **Ext E** | DNS switch timing from the client watcher |
| `evidence/13-troubleshooting/` | **Ext F** | diagnose.sh output, 23 Nov outage reconstruction |

---

## 5. Learning Summaries

> Each summary lives next to the work it describes; this table links to it.

| Extension | Owner | Summary |
|-----------|-------|---------|
| Ext A – Backup DNS | Mac 1 + Mac 4 | [ARCHITECTURE.md §7](ARCHITECTURE.md) |
| Ext B – Short TTL | Mac 1 | [ARCHITECTURE.md §7](ARCHITECTURE.md) |
| Ext C – Firewall | Mac 3 + Mac 4 | [ext-c-learning-summary.md](evidence/11-service-isolation/ext-c-learning-summary.md) |
| Ext D – Backend failover | Mac 2 | [MAC2-PHASE2.md](MAC2-PHASE2.md) |
| Ext E – Standby Edge | Mac 2 + Mac 3 | [MAC2-PHASE2.md](MAC2-PHASE2.md) |
| Ext F – Fault Diagnosis | Mac 4 | _[pending]_ |
