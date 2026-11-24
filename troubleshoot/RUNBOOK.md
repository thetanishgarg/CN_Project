# RUNBOOK — Computer Networks Phase 1 & 2 Troubleshooting
## Team 1 | Mac 4 (Integration Owner)

> Run `./troubleshoot/diagnose.sh` first — it auto-detects the failing layer.  
> Use this table when you need a targeted fix or to explain a specific fault.

---

## Fault Table

| # | Injected Fault | Symptom | Proving Command | Fix |
|---|----------------|---------|----------------|-----|
| 1 | **Wrong DNS record** (address= changed in dnsmasq.conf) | `dig app.team1.test` returns wrong IP; curl goes to wrong host; TLS SNI mismatch | `dig app.team1.test` → check answer vs `$MAC2_IP` | Mac 1: edit config.env, `sudo ./dns/start-dns.sh` |
| 2 | **dnsmasq stopped on Mac 1** (primary DNS down) | `dig @$MAC1_IP app.team1.test` times out; without backup: "Could not resolve host" | `dig +timeout=2 @$MAC1_IP app.team1.test` | Mac 1: `sudo ./dns/start-dns.sh` · Mac 4 backup should auto-cover it |
| 3 | **Client DNS changed** (pointing to 8.8.8.8) | `dig app.team1.test` → NXDOMAIN (8.8.8.8 has no `.test` zone) | `networksetup -getdnsservers Wi-Fi` → not MAC1_IP | `sudo ./dns/set-client-dns.sh set` |
| 4 | **nginx stopped on Mac 2** | Ping to MAC2_IP works; `nc -vz MAC2_IP 443` → "Connection refused" | `nc -vz $MAC2_IP 443` | Mac 2: `sudo ./nginx-script.sh start` |
| 5 | **Wrong upstream port in nginx.conf** (e.g. 3099 instead of 3002) | nginx running, 443 open, but `GET /api/status` → 502; backend direct curl works | `curl http://$MAC4_IP:$BACKEND_B_PORT/api/status` succeeds; nginx 502 | Mac 2: fix `nginx-script.sh` upstream port, `./nginx-script.sh reload` |
| 6 | **Expired / wrong TLS cert** | TLS handshake fails; curl shows "certificate has expired" or "hostname mismatch" | `openssl s_client -connect $MAC2_IP:443 -servername app.team1.test -CAfile team1-ca.crt` | Mac 2: `./mac2-certs.sh` → `./nginx-script.sh reload` |
| 7 | **Backend A stopped** (Mac 3:3001 down) | Load balancing: only `X-Backend: B` in responses; no 502 (nginx retries to B) | `curl http://$MAC3_IP:3001/api/status` → "Connection refused" | Mac 3: `BACKEND_NAME=A BACKEND_PORT=3001 python3 backend.py` |
| 8 | **Both backends stopped** | HTTP 502 from nginx; `X-Backend` header absent | `curl -I https://app.team1.test/api/status` → `HTTP/2 502` | Mac 3 + Mac 4: restart both backends |
| 9 | **Firewall blocking edge** (pf rules on backend Mac) | nginx's connect to the backend times out after 2 s (the rule is `block drop`, so nothing is refused); the other backend answers, or 502 if both are blocked; a direct test from Mac 2 to the backend port times out | `nc -vz $MAC4_IP $BACKEND_B_PORT` from Mac 2 → timeout | `sudo ./mac4-ext-c-firewall.sh remove` (and Mac 3: `sudo ./firewall/backend-firewall.sh remove`) |
| 10 | **Wrong port** (client connects to :8080 or :80) | "Connection refused" or "ECONNREFUSED" immediately | `nc -vz $MAC2_IP 8080` → refused | Use correct port 443: `curl https://app.team1.test/api/status` |
| 11 | **Backup DNS down (Ext A)** when primary also fails | Full DNS outage; both servers unreachable | `dig @$MAC1_IP app.team1.test` and `dig @$MAC4_IP app.team1.test` both timeout | Mac 4: `sudo ./mac4-backup-dns.sh start` |
| 12 | **Stale DNS cache** | Correct DNS servers but old IP cached; curl goes to previous edge | `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder` then re-dig | Flush cache (see command) · Set TTL=30s prevents long stale windows |

---

## Layer Cheat-Sheet

```
Client            Mac 1 (DNS)         Mac 2 (nginx)      Mac 3 / Mac 4
  |                                                       (Backend A/B)
  |─── dig app.team1.test A ──────>|
  |<── answer: $MAC2_IP ───────|
  |                                                       
  |─── TCP SYN ────────────────────────────────────>:443 |
  |<── SYN-ACK ───────────────────────────────────────── |
  |─── TLS ClientHello (SNI: app.team1.test) ──────────> |
  |<── ServerHello + Certificate ──────────────────────── |
  |─── TLS App Data (HTTP GET) ────────────────────────> |
  |                     |──HTTP proxy──>:3001 or :3002──> |
  |                     |<─────JSON─────────────────────  |
  |<── TLS App Data (HTTP 200 + X-Backend: A/B) ───────── |
```

**Layer mapping to fault table rows:**

| Layer | Protocol | Faults |
|-------|----------|--------|
| 1 – Name resolution | DNS/UDP:53 | #1, #2, #3, #11, #12 |
| 2 – IP reachability | ICMP ping | MAC2_IP changed / off-subnet |
| 3 – Port reachable | TCP:443 | #4, #10 |
| 4 – TLS handshake | TLS 1.2/1.3 | #6 |
| 5 – HTTP response | HTTP/1.1 proxy | #5, #7, #8, #9 |

---

## Mock Drill Procedure

> One teammate secretly breaks something; the rest diagnose out loud using `diagnose.sh`.

**Setup:**
1. Agree on a "break window" (90 seconds to introduce the fault).
2. Announce "fault injected" — others run `./troubleshoot/diagnose.sh`.
3. The script stops at the failing layer and prints the diagnosis.
4. Teams must name: **the layer, the specific cause, the fix**.
5. Apply the fix, re-run `diagnose.sh` → all 5 layers green.

**Good faults to drill:**

```bash
# Fault A — stop dnsmasq on Mac 1 (requires Mac 4 backup to catch it)
sudo pkill dnsmasq

# Fault B — point client to wrong DNS
sudo networksetup -setdnsservers Wi-Fi 8.8.8.8

# Fault C — stop Backend B on Mac 4
kill $(lsof -ti :3002) 2>/dev/null

# Fault D — stop nginx on Mac 2
sudo ./nginx-script.sh stop

# Fault E — apply firewall on Mac 4 (diagnose from Mac 2's perspective)
sudo ./mac4-ext-c-firewall.sh apply
```

---

## Quick Reference — Key Diagnostic Commands

Run `source config.env` first: the commands below use its variables instead of fixed addresses.

```bash
# DNS layer
dig app.team1.test                             # resolution + server used
dig +short @$MAC1_IP app.team1.test       # direct query to Mac 1
dig +short @$MAC4_IP  app.team1.test        # direct query to Mac 4 (backup)
scutil --dns | head -20                         # macOS resolver config
networksetup -getdnsservers Wi-Fi               # which DNS servers are set

# IP layer
ping -c 3 $MAC2_IP                         # reach nginx edge?

# TCP layer
nc -vz $MAC2_IP 443                        # port 443 open?
nc -vz $MAC4_IP  3002                       # backend B direct?

# TLS layer
openssl s_client -connect $MAC2_IP:443 \
    -servername app.team1.test \
    -CAfile team1-ca.crt                       # cert valid? CN? expiry?

# HTTP layer
curl -sI --cacert team1-ca.crt https://app.team1.test/api/status
curl -s  --cacert team1-ca.crt https://app.team1.test/api/status

# Firewall
sudo pfctl -a com.apple/team1-backend -sr               # show our pf anchor
sudo pfctl -si                                # overall pf status

# Cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```
