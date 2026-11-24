# DEMO SCRIPT — Computer Networks Phase 1 & 2
## 11 Steps | Exact Commands | Presenter per Step

> **IPs:** Mac 1 (DNS) `10.202.54.224` · Mac 2 (nginx/edge) `10.202.54.225` · Mac 3 (Backend A + Standby Edge) `10.202.54.70` · Mac 4 (Backend B + Backup DNS + Test Client) `10.202.54.68`  
> **Domain:** `app.team1.test` · **CA:** `team1-ca.crt`  
> The addresses above are from the 22 Nov network. Use the values in `config.env`; `./demo.sh` reads them for you and runs this Mac's part of each step.

---

## Phase 1 Steps (1–5, recap)

### Step 1 — LAN: All 4 Macs on the same subnet
**Presenter: Mac 1**

```bash
# Each Mac shows their IP
ipconfig getifaddr en0

# Mac 1 pings all others
ping -c 3 10.202.54.225   # Mac 2
ping -c 3 10.202.54.70    # Mac 3
ping -c 3 10.202.54.68    # Mac 4
```

**Evidence:** `evidence/01-lan/`

---

### Step 2 — DNS: Private name resolution
**Presenter: Mac 1 (runs DNS) + Mac 4 (client)**

```bash
# Mac 1 — show dnsmasq running
ps aux | grep dnsmasq

# Mac 4 — query private DNS
dig app.team1.test         # expect answer: 10.202.54.225
dig +short app.team1.test
```

**Evidence:** `evidence/02-dns/`

---

### Step 3 — HTTPS: TLS termination at nginx
**Presenter: Mac 2 + Mac 4**

```bash
# Mac 4 — proper validation, NOT -k
curl -v https://app.team1.test/api/status
curl -v --tlsv1.2 --tls-max 1.2 https://app.team1.test/api/status 2>&1 | grep -E "subject|issuer|SSL connection"
```

**Evidence:** `evidence/03-https/`

---

### Step 4 — Load Balancing: A ↔ B alternating
**Presenter: Mac 4**

```bash
for i in {1..10}; do
    echo -n "Request $i: "
    curl -s -D - -o /dev/null https://app.team1.test/api/status \
        | grep -i "^X-Backend:" | tr -d '\r'
done
```

**Evidence:** `evidence/04-load-balancing/`

---

### Step 5 — Caching: ETag + 304 Not Modified
**Presenter: Mac 4**

```bash
# 1. First request → 200 + ETag + Cache-Control: max-age=60
curl -sI https://app.team1.test/api/cache | grep -Ei "HTTP|cache-control|etag"

# 2. Capture ETag
ETAG=$(curl -sI https://app.team1.test/api/cache | grep -i "^etag:" | awk '{print $2}' | tr -d '\r')

# 3. Conditional GET → 304
curl -sI -H "If-None-Match: $ETAG" https://app.team1.test/api/cache | grep "HTTP/"

# 4. ETags identical on both backends
curl -sI http://10.202.54.70:3001/api/cache | grep -i etag
curl -sI http://10.202.54.68:3002/api/cache | grep -i etag
```

**Evidence:** `evidence/06-caching/`

---

## Phase 2 Steps (6–11)

### Step 6 — Ext A: Backup DNS Failover
**Presenter: Mac 1 (stops DNS) + Mac 4 (shows backup takes over)**

```bash
# Mac 4 — show both DNS servers configured
networksetup -getdnsservers Wi-Fi
scutil --dns | grep -A 4 "resolver #"

# Normal state: query answered by Mac 1
dig app.team1.test         # ;; SERVER: 10.202.54.224

# Mac 1 — STOPS dnsmasq (simulated failure)
# (Mac 1 runs): sudo pkill dnsmasq

# Mac 4 — flush cache, re-query
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
dig app.team1.test         # ;; SERVER: 10.202.54.68  ← Mac 4 backup!

# App still works despite DNS primary failure
curl https://app.team1.test/api/status
```

**Key talking point:** macOS tries servers in order; backup answers when primary times out. TTL=30s means cache doesn't mask the failover.

**Evidence:** `evidence/08-backup-dns/`

---

### Step 7 — Ext B: Short TTL (30 s)
**Presenter: Mac 1 + Mac 4**

```bash
# Show TTL in DNS answer
dig app.team1.test | grep -A 3 "ANSWER SECTION"
# → 30   IN   A   10.202.54.225  (TTL=30s)

# Wait 30 s, flush, query again — no stale data
sleep 30 && sudo dscacheutil -flushcache && dig +short app.team1.test
```

**Evidence:** `evidence/09-ttl/`

---

### Step 8 — Ext C: Service Isolation / Firewall
**Presenter: Mac 4 (applies firewall on port 3002)**

```bash
# Apply pf rules on Mac 4
sudo ./mac4-ext-c-firewall.sh apply

# From Mac 4 itself — show pf anchor
sudo pfctl -a team1-backend -sr

# From an unauthorised host — connection is DROPPED (timeout)
nc -vz 10.202.54.68 3002        # from non-edge: timeout
# From Mac 2 (authorised edge): succeeds
# curl http://10.202.54.68:3002/api/status  → 200

# App still works through nginx (Mac 2 is allowed)
curl https://app.team1.test/api/status

# Remove after demo
sudo ./mac4-ext-c-firewall.sh remove
```

**Evidence:** `evidence/11-service-isolation/`

---

### Step 9 — Ext E: Standby Edge / Hot Cutover
**Presenter: Mac 3 (standby nginx) + Mac 1 (DNS switch)**

```bash
# Mac 3 — start standby nginx
sudo ./mac3-standby-edge.sh start

# Mac 1 — update APP_TARGET_IP to MAC3_IP, restart DNS
# (Mac 1 edits config.env, then): sudo ./dns/start-dns.sh

# Mac 4 — wait ≤30 s (TTL), flush, re-query
sudo dscacheutil -flushcache
dig app.team1.test         # answer: 10.202.54.70  (Mac 3!)

# App still works through standby edge
curl https://app.team1.test/api/status    # X-Backend: A or B

# Revert: Mac 1 restores APP_TARGET_IP=MAC2_IP, restarts DNS
```

**Evidence:** `evidence/10-ha-failover/` + `evidence/12-edge-cutover/`

---

### Step 10 — Ext F: Fault Diagnosis (Faculty Fault Drill)
**Presenter: Mac 4 (runs diagnose.sh), all Macs**

```bash
# Faculty / teammate secretly breaks ONE thing.
# Mac 4 runs the diagnostic:
./troubleshoot/diagnose.sh

# Script stops at the failing layer, names the cause, prints the fix.
# After fix is applied:
./troubleshoot/diagnose.sh   # all 5 layers green
```

**What to narrate:**
1. Layer 1 DNS checked first — most faults start here.
2. If DNS resolves to wrong IP, TLS fails at Layer 4 (SNI mismatch) even if TCP connects.
3. 502 at Layer 5 → script immediately tests both backends directly.

**Evidence:** `evidence/13-troubleshooting/`

---

### Step 11 — Wireshark / Packet Evidence
**Presenter: Mac 4**

```bash
# Already captured — open in Wireshark:
open evidence/05-wireshark/full-flow.pcap

# Demonstrate these filters one by one:
# dns                              → query to :53, answer=MAC2_IP, answered by which server
# tcp.flags.syn==1                 → 3-way handshake SYN/SYN-ACK to :443
# tls.handshake                    → ClientHello(SNI), ServerHello, Certificate, ChangeCipherSpec
# tls.record.content_type==23      → Encrypted Application Data
```

**Evidence:** `evidence/05-wireshark/` (screenshots + pcap)

---

## Quick Evidence Index

| Folder | Demo Step | Contents |
|--------|-----------|---------|
| `evidence/01-lan/` | Step 1 | ifconfig, ping matrix |
| `evidence/02-dns/` | Step 2 | dig output, failure demos |
| `evidence/03-https/` | Step 3 | curl -v, cert details |
| `evidence/04-load-balancing/` | Step 4 | X-Backend alternating log |
| `evidence/05-wireshark/` | Step 11 | full-flow.pcap + screenshots |
| `evidence/06-caching/` | Step 5 | ETag + 304 responses |
| `evidence/07-failures/` | Phase 1 | 5 failure demo text files |
| `evidence/08-backup-dns/` | Step 6 | Failover dig SERVER= proof |
| `evidence/09-ttl/` | Step 7 | TTL=30s, cache expiry |
| `evidence/10-ha-failover/` | Step 9 | Edge cutover dig + curl |
| `evidence/11-service-isolation/` | Step 8 | pf rules, block/allow proofs |
| `evidence/12-edge-cutover/` | Step 9 | DNS switch timing |
| `evidence/13-troubleshooting/` | Step 10 | diagnose.sh run, drill output |
