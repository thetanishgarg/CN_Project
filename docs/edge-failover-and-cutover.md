# Mac 2: Phase 2 (Ext D HA failover, Ext E edge cutover)

Owner: Mac 2 (nginx edge). Files: `edge/nginx-script.sh`, `mac2-*.sh`.

## Files

| File | Runs on | What it does |
|---|---|---|
| `edge/nginx-script.sh start [primary\|standby]` | Mac 2, Mac 3 | Generates the nginx config from `config.env`. Detects the role from this Mac's IP, so the same config runs on both edges. Adds the headers `X-Edge: mac2-primary` / `mac3-standby` and `X-Upstream` |
| `edge/mac2-export-certs.sh` | Mac 2 | Bundles the cert, its private key and the CA cert into `~/Desktop/team1-edge-certs.tgz` for AirDrop. The CA's private key never leaves Mac 2 |
| `edge/mac2-import-certs.sh <tgz>` | Mac 3 | Installs the bundle, then checks that the cert is signed by our CA, valid for the names, and matches the key |
| `edge/mac2-ha-demo.sh demo` / `watch` | client (Mac 1 / Mac 4) | Ext D: guided failover demo, or one request per second on screen |
| `edge/mac2-edge-watch.sh` | client (Mac 1 / Mac 4) | Ext E: every 2 s shows what the DNS server says, what this Mac's cache uses, and which edge answered |

Private keys and `.tgz` bundles are in `.gitignore`. **Never commit them.**

## Ext D: HA failover (demo)

1. Mac 2: `./edge/nginx-script.sh start`, then in a second tab `./edge/nginx-script.sh logs`.
2. Client (Mac 4): `./edge/mac2-ha-demo.sh demo` (it pauses and tells Mac 3 when to act).
   - Both backends up: A, B, A, B.
   - Mac 3 presses Ctrl+C on Backend A: **every request is still 200, all served by B**. The Mac 2 log shows `upstream=<A> , <B>` on the retried request.
   - Mac 3 restarts A, and after the 10 s `fail_timeout` the pattern goes back to A, B, A, B.
3. Results are saved in `evidence/10-ha-failover/`.

**How it works (config in `edge/nginx-script.sh`):**
- `max_fails=1 fail_timeout=10s`: one failed attempt marks a backend DOWN for 10 s. After that nginx tries it again with real traffic, and if it answers it's back in rotation. This is a **passive** health check: nginx learns from failures of real requests.
- `proxy_next_upstream error timeout http_502 http_503` with `proxy_next_upstream_tries 2`: the request that hit the dead backend is **retried on the other one**, so the client never sees the error.
- `proxy_connect_timeout 2s`: a stopped *process* gives "connection refused" (RST) and an instant retry. A *Mac that is off* gives no reply at all, so we give up after 2 s instead of the default 60 s.

**Passive vs active health checks:**
- Open-source nginx only has passive checks.
- nginx Plus (`health_check`) and AWS ALB target groups also send their own probe requests (e.g. `GET /health` every 5 s). They take a backend out *before* a user request fails, and put it back only after N successful probes.

Tested locally on Mac 2 (backends on 3001/3002, edge on 8443, one request per second): 25 of 25 requests returned 200 while Backend A was killed and restarted, and A rejoined about 7 s after restart. With A's address unreachable, 5 of 5 requests returned 200 via B.

## The remaining single point of failure

After Ext D, the backends are redundant, but **the edge (nginx on Mac 2) is still a single point of failure.** DNS points `app.team1.test` at exactly one IP, Mac 2's. If Mac 2 or nginx dies, every client fails at the TCP step (connection refused or timeout), even though both backends are healthy.

Ways to remove it:

| Option | How | Trade-off |
|---|---|---|
| Second edge + DNS failover (our Ext E) | Standby nginx on Mac 3, change the DNS record, short TTL | Cheap, but failover is as slow as the TTL plus client caches, and the switch is manual (or needs health-checked DNS, like Route 53 failover records) |
| Floating / virtual IP | keepalived (VRRP) on Mac 2 and Mac 3 shares one IP. The backup takes over the IP within ~1 s when the master's heartbeats stop (gratuitous ARP updates the LAN) | Fast and DNS doesn't change, but both machines must be on the same L2 network |
| Active-active edges | DNS returns both edge IPs (or anycast), and both serve traffic | No idle standby, but clients must retry the other IP |
| Managed cloud LB | AWS ALB / GCP LB run multiple nodes across availability zones | The provider removes the SPOF for you |

## Ext E: DNS-based edge cutover (demo)

**Setup, once:**
1. Mac 2: `./edge/mac2-export-certs.sh`, then AirDrop `~/Desktop/team1-edge-certs.tgz` to Mac 3.
2. Mac 3 runs `brew install nginx`, `git pull` and `./edge/mac2-import-certs.sh ~/Downloads/team1-edge-certs.tgz`.
3. Delete the `.tgz` on both Macs.
4. Mac 3: `./edge/nginx-script.sh start standby`. It uses the same backends and the same cert. If Mac 3's firewall is on, it must allow `STANDBY_EDGE_IP` to reach 3001/3002.
5. Check from a client:
   ```bash
   curl -sI --resolve app.team1.test:443:<MAC3_IP> https://app.team1.test/api/status | grep -i x-edge
   ```
   It should print `mac3-standby`.

**Demo:**
1. Client (Mac 4): `./edge/mac2-edge-watch.sh`. Every row shows `mac2-primary`.
2. Mac 1: `./dns/cutover-demo.sh cutover`, then `sudo ./dns/start-dns.sh --target <STANDBY_EDGE_IP>` on Mac 1 **and** Mac 4 (both DNS servers).
3. Watch the columns:
   - **DNS SERVER SAYS** switches to Mac 3 immediately.
   - **THIS MAC USES** still shows Mac 2, so **X-EDGE stays `mac2-primary`**. The client cached the old answer, and it is valid for up to 30 s (TTL).
   - When the TTL expires, **X-EDGE becomes `mac3-standby`**. No request fails during the switch, because both edges are serving.
   - A client that flushes (`sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`) switches at once.
4. Restore: `./dns/cutover-demo.sh restore` (target back to Mac 2 on both DNS servers).
5. Results are saved in `evidence/12-edge-cutover/`.

**Why keep the old edge running during the switch:** clients with cached answers keep arriving for one TTL. Only stop the old edge after the TTL has passed (the "drain"). In production you lower the TTL *days before* a migration, because the old long TTL is already cached everywhere.

## Learning summaries (for phase2-report.md)

**Extension D: High-availability failover.** We configured nginx on Mac 2 to detect an unhealthy backend from real traffic and route around it. With `max_fails=1 fail_timeout=10s` a backend that refuses or times out once is taken out of the pool for 10 seconds. With `proxy_next_upstream` the request that failed is retried on the healthy backend, so the client never sees an error. When we stopped Backend A, every request kept returning 200 from Backend B. When A was restarted, nginx put it back automatically after the timeout, and round-robin resumed with no configuration change. We learned the difference between a refused connection (process down, instant RST, instant failover) and a silent host (machine off, must wait for the connect timeout, which we cut to 2 s), and between nginx's passive health checks and the active probes used by AWS ALB target groups. Ext D also made the next weakness obvious: the backends are now redundant, but the edge itself is a single point of failure.

**Extension E: Controlled edge migration (DNS-based cutover).** To address the edge SPOF we ran a standby nginx on Mac 3, using the same generated configuration and the same certificate (moved by AirDrop, never through git), and moved traffic to it by changing the DNS record for `app.team1.test`. The cutover showed that DNS changes are not instant. The DNS server answered with the new IP immediately, but a client that had cached the old answer kept connecting to Mac 2 until its 30-second TTL expired, then moved to Mac 3. Flushing the client cache made it switch at once. Because both edges served traffic during that window, no request failed, which is the reason to keep the old edge running for at least one TTL. This is how production migrations work: lower the TTL well in advance, bring up the new target, switch the record, wait out the old TTL, then retire the old target. Faster failover needs a floating IP (VRRP) or a managed multi-AZ load balancer.
