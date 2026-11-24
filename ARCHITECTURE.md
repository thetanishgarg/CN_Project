# 🏗️ ARCHITECTURE — Computer Networks Phase 1 & Phase 2

> **About the addresses.** The IPs drawn and tabulated here come from two earlier sessions (`10.202.54.x` and `10.81.95.x`). The addresses actually in use are always the ones in `config.env`; the structure and ports are the same.

> **High-Availability Campus Network Simulation**  
> Private Dual DNS (dnsmasq) + Active-Passive HTTPS Edge (nginx) + Dual Backend (Python) + Host Firewall Isolation (pf)

---

## 1. Network Topology (Phase 2)

```
┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                 Shared Wi-Fi LAN / Hotspot                                       │
│                                                                                                  │
│   ┌────────────────────────┐                   ┌────────────────────────┐                        │
│   │         MAC 1          │                   │         MAC 2          │                        │
│   │   Primary DNS Server   │                   │   Primary HTTPS Edge   │                        │
│   │    (dnsmasq :53)       │                   │    & Load Balancer     │                        │
│   │                        │                   │     (nginx :443)       │                        │
│   │     10.202.54.224      │                   │     10.81.95.225       │                        │
│   └───────────┬────────────┘                   └───────────┬────────────┘                        │
│               │                                            │                                     │
│               │             ┌────────────────────────┐     │                                     │
│               │             │  Gateway / Wi-Fi AP    │     │                                     │
│               │             │     10.202.54.86       │     │                                     │
│               │             └───────────┬────────────┘     │                                     │
│               │                         │                  │                                     │
│   ┌───────────┴─────────────────────────┴──────────────────┴────────────┐                        │
│   │                                                                     │                        │
│   │   ┌────────────────────────────────┐    ┌───────────────────────────┴────────────────────┐   │
│   │   │             MAC 3              │    │                     MAC 4                      │   │
│   │   │  • Backend A (Python :3001)    │    │  • Backend B (Python :3002)                    │   │
│   │   │  • Standby Edge (nginx :443)   │    │  • Backup DNS Server (dnsmasq :53) [Ext A]     │   │
│   │   │  • pf Firewall Isolation       │    │  • Active Test Client (curl, dig, Wireshark)   │   │
│   │   │    [Ext C: Block direct :3001] │    │                                                │   │
│   │   │                                │    │                                                │   │
│   │   │         10.81.95.70            │    │                  10.81.95.68                   │   │
│   │   └────────────────────────────────┘    └────────────────────────────────────────────────┘   │
│   │                                                                                              │
└───┴──────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Cloud Architecture Equivalents (Phase 2)

| LAN Project Role | Technology Used | AWS Enterprise Equivalent | Architectural Function & Rationale |
|---|---|---|---|
| **Primary DNS** (Mac 1) | dnsmasq (UDP 53) | **Amazon Route 53** (Primary Hosted Zone Resolver) | Authoritative DNS resolution for `team1.test` zone with TTL caching. |
| **Backup DNS** (Mac 4, Ext A) | dnsmasq (UDP 53) | **Route 53 Secondary Resolver / Cross-AZ Resolver** | High-availability resolver redundancy preventing single point of failure (SPOF) at name resolution tier. |
| **Primary HTTPS Edge** (Mac 2) | nginx (TCP 443, TLS 1.2/1.3) | **Application Load Balancer (ALB) - Active** | TLS termination, HTTP/1.1 keepalive, Layer 7 path routing, round-robin load distribution. |
| **Standby HTTPS Edge** (Mac 3, Ext E) | nginx (TCP 443, TLS 1.2/1.3) | **Standby ALB / Multi-Region DR Edge** | Hot-standby reverse proxy activated via DNS cutover during maintenance or failure. |
| **Backend Tier** (Mac 3 & 4) | Python HTTP microservices (:3001, :3002) | **EC2 Auto Scaling Group / ECS Fargate Tasks** | Stateless application tier returning JSON payloads with Cache-Control and ETag headers. |
| **Firewall Isolation** (Mac 3, Ext C) | macOS Packet Filter (`pfctl`) | **AWS Security Groups & Network ACLs** | Strict Layer 3/4 network microsegmentation: permits traffic to backends ONLY from Edge proxies. |
| **Wi-Fi / Hotspot Router** | 802.11 Access Point + DHCP + NAT | **AWS Virtual Private Cloud (VPC) + Internet Gateway (IGW)** | Layer 2 broadcast domain + Layer 3 subnet routing and external internet transit. |

---

## 3. IP & Service Matrix

| Mac Node | Hostname / Role | Phase 1 Function | Phase 2 Extension Role | IP Address | Listening Ports & Protocols |
|---|---|---|---|---|---|
| **Mac 1** | Primary DNS | Authoritative DNS for `team1.test` | Primary Resolver for dual-DNS setup | `10.202.54.224` | `UDP 53` (dnsmasq), `TCP 53` |
| **Mac 2** | Primary Edge | TLS Termination & Load Balancer | Primary Traffic Target (`$APP_TARGET_IP`) | `10.81.95.225` | `TCP 443` (nginx HTTPS) |
| **Mac 3** | Backend A | HTTP Microservice A | **Ext E:** Standby Edge (`:443`)<br>**Ext C:** `pf` Firewall isolation | `10.81.95.70` | `TCP 3001` (Backend A)<br>`TCP 443` (Standby nginx) |
| **Mac 4** | Backend B / Client | HTTP Microservice B | **Ext A:** Backup DNS Server (`:53`)<br>Primary Test & Evidence Client | `10.81.95.68` | `TCP 3002` (Backend B)<br>`UDP 53` (dnsmasq Backup) |

### Active DNS Zone Configuration (`team1.test`)

| Fully Qualified Domain Name (FQDN) | Record Type | Target IP Address | TTL | Purpose |
|---|---|---|---|---|
| `app.team1.test` | A | `10.81.95.225` (Cutover: `10.81.95.70`) | **30 s** | User web application & dashboard |
| `api.team1.test` | A | `10.81.95.225` (Cutover: `10.81.95.70`) | **30 s** | REST API status endpoint |
| `*.team1.test` (unmapped) | — | NXDOMAIN | — | Non-existent domain boundary |
| Public domains (`google.com`, etc.) | A / AAAA | Forwarded to `8.8.8.8`, `8.8.4.4` | Upstream | Preserves general internet connectivity |

---

## 4. End-to-End Request Flows

### 4.1. Normal Operational Flow (Phase 1 Baseline)

```
[ Client Mac ]            [ Mac 1: DNS ]            [ Mac 2: Edge ]           [ Mac 3/4: Backends ]
      │                          │                         │                           │
      │ 1. DNS Query (UDP 53)    │                         │                           │
      │    "A app.team1.test?"   │                         │                           │
      │─────────────────────────>│                         │                           │
      │ 2. DNS Reply             │                         │                           │
      │    "IP: 10.81.95.225"    │                         │                           │
      │    "TTL: 30s"            │                         │                           │
      │<─────────────────────────│                         │                           │
      │                                                    │                           │
      │ 3. TCP 3-Way Handshake (SYN -> SYN-ACK -> ACK)     │                           │
      │───────────────────────────────────────────────────>│                           │
      │ 4. TLS 1.3 Handshake (ClientHello, Cert, Finished) │                           │
      │<══════════════════════════════════════════════════>│                           │
      │ 5. Encrypted HTTPS GET /api/status                 │                           │
      │───────────────────────────────────────────────────>│                           │
      │                                                    │ 6. HTTP Proxy Pass        │
      │                                                    │    (Round-Robin :3001/:2) │
      │                                                    │──────────────────────────>│
      │                                                    │ 7. HTTP 200 + ETag JSON   │
      │                                                    │<──────────────────────────│
      │ 8. Encrypted HTTPS Response (X-Backend: A or B)    │                           │
      │<───────────────────────────────────────────────────│                           │
```

---

### 4.2. Extension A: Backup DNS Failover Flow

```
[ Client Mac ]            [ Mac 1: Primary DNS ]     [ Mac 4: Backup DNS ]     [ Mac 2: Edge ]
      │                          │ (DOWN / Stopped)         │                         │
      │ 1. DNS Query (UDP 53)    │                          │                         │
      │    to 10.202.54.224      │                          │                         │
      │─── ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─>│ ✗ (No Response / Timeout)│                         │
      │                                                     │                         │
      │ 2. mDNSResponder Automatic Failover                 │                         │
      │    DNS Query to Backup: 10.81.95.68                 │                         │
      │────────────────────────────────────────────────────>│                         │
      │ 3. DNS Reply from Backup                            │                         │
      │    "IP: 10.81.95.225, TTL: 30s"                     │                         │
      │<────────────────────────────────────────────────────│                         │
      │                                                                               │
      │ 4. Seamless TCP & TLS Connection to Edge                                      │
      │──────────────────────────────────────────────────────────────────────────────>│
```

---

### 4.3. Extension B: TTL Caching & Resolver Invalidation Flow

```
[ Application / curl ]       [ macOS mDNSResponder ]      [ Mac 1: dnsmasq ]        [ Network Wire ]
         │                            │                           │                        │
         │ 1. curl app.team1.test     │                           │                        │
         │    getaddrinfo()           │                           │                        │
         │───────────────────────────>│ (Cache Miss)              │                        │
         │                            │ 2. Query UDP 53           │                        │
         │                            │──────────────────────────>│                        │
         │                            │ 3. Reply: IP=225, TTL=30s │                        │
         │                            │<──────────────────────────│                        │
         │                            │ [Saves to Cache: 30s timer]                        │
         │ 4. Returns 10.81.95.225    │                           │                        │
         │<───────────────────────────│                           │                        │
         │                            │                           │                        │
         │ [DNS Server changes record to 10.81.95.70 via start-dns.sh --target 10.81.95.70]│
         │                            │                           │                        │
         │ 5. curl within 30s         │                           │                        │
         │    getaddrinfo()           │                           │                        │
         │───────────────────────────>│ [Cache Hit! Age < 30s]    │                        │
         │ 6. Returns 10.81.95.225    │ (NO query sent to wire!)  │                        │
         │<───────────────────────────│                           │                        │
         │                            │                           │                        │
         │ 7. dig app.team1.test (direct socket to :53)           │                        │
         │───────────────────────────────────────────────────────>│ (Bypasses OS Cache)    │
         │ 8. dig returns 10.81.95.70 IMMEDIATELY                 │                        │
         │<───────────────────────────────────────────────────────│                        │
         │                            │                                                    │
         │ 9. dscacheutil -flushcache │                                                    │
         │    killall -HUP mDNSResp   │ [Cache Purged]                                     │
         │───────────────────────────>│                                                    │
         │ 10. curl app.team1.test    │                                                    │
         │───────────────────────────>│ (Cache Miss -> Re-query)  │                        │
         │                            │──────────────────────────>│                        │
         │                            │<──────────────────────────│                        │
         │ 11. Returns 10.81.95.70    │                                                    │
         │<───────────────────────────│                                                    │
```

---

### 4.4. Extension C: Packet Filter (pf) Backend Isolation

```
[ Client Mac ] ───────────────── TCP SYN :3001 ─────────────────> [ Mac 3: Backend A ]
                                                                       │
                                                                 [ pf Firewall Rule ]
                                                                 block in proto tcp to port 3001
                                                                 pass in proto tcp from MAC2_IP to port 3001
                                                                       │
                                                             ✗ DROP / REJECT (Direct Client Blocked)

[ Mac 2: Edge ] ───────────────── TCP SYN :3001 ─────────────────> [ Mac 3: Backend A ]
                                                                       │
                                                                 [ pf Firewall Rule ]
                                                                 Source IP == MAC2_IP -> PASS
                                                                       │
                                                             ✓ TCP Handshake ESTABLISHED
```

---

### 4.5. Extension E: Active-Passive Edge Cutover

```
[ State ]            [ DNS Record ]        [ Client Cache (<=30s) ]     [ Active Traffic Path ]
──────────────────────────────────────────────────────────────────────────────────────────────────
Normal               app -> Mac 2 (225)    Cached -> Mac 2              100% traffic on Mac 2
Cutover Initiated    app -> Mac 3 (70)     Cached clients -> Mac 2      Traffic split:
                                           Expired clients -> Mac 3     Mac 2 drains, Mac 3 ramps
Cutover Complete     app -> Mac 3 (70)     All cached -> Mac 3          100% traffic on Mac 3
```

---

## 5. OSI & TCP/IP Protocol Stack Mapping

```
┌───────┬─────────────────┬─────────────────┬────────────────────────────┬─────────────────────────────┐
│ OSI # │ OSI Layer       │ TCP/IP Layer    │ Protocol / Standard        │ Project Phase 2 Role        │
├───────┼─────────────────┼─────────────────┼────────────────────────────┼─────────────────────────────┤
│   7   │ Application     │                 │ HTTP/1.1                   │ JSON APIs, ETags, Proxies   │
│       │                 │ Application     │ DNS                        │ dnsmasq queries / records   │
├───────┼─────────────────┤                 ├────────────────────────────┼─────────────────────────────┤
│   6   │ Presentation    │                 │ TLS 1.2 / TLS 1.3          │ nginx certificate/ciphers   │
├───────┼─────────────────┼─────────────────┼────────────────────────────┼─────────────────────────────┤
│   5   │ Session         │ Transport       │ TLS Session / TCP Sockets  │ Keep-Alive, multiplexing    │
├───────┼─────────────────┤                 ├────────────────────────────┼─────────────────────────────┤
│   4   │ Transport       │                 │ TCP (:443, :3001, :3002)   │ 3-way handshake, SYN/ACK    │
│       │                 │                 │ UDP (:53)                  │ Stateless DNS query packets │
├───────┼─────────────────┼─────────────────┼────────────────────────────┼─────────────────────────────┤
│   3   │ Network         │ Internet        │ IPv4 (10.202.54.x)         │ IP routing, ICMP ping,      │
│       │                 │                 │ pf packet filtering        │ Ext C firewall rules        │
├───────┼─────────────────┼─────────────────┼────────────────────────────┼─────────────────────────────┤
│   2   │ Data Link       │ Network Access  │ Ethernet / 802.11 Wi-Fi    │ MAC addresses, ARP frames   │
├───────┼─────────────────┤ (Link)          ├────────────────────────────┼─────────────────────────────┤
│   1   │ Physical        │                 │ 2.4 GHz / 5 GHz RF Media   │ Wi-Fi radio modulation      │
└───────┴─────────────────┴─────────────────┴────────────────────────────┴─────────────────────────────┘
```

---

## 6. Comprehensive Viva Examination Guide

### 6.1. Why UDP for DNS (and when is TCP used)?
- **UDP port 53** is chosen because standard DNS queries and replies are stateless, lightweight transactions (typically under 512 bytes). Establishing a TCP connection requires a 3-way handshake (1.5 RTT) plus connection teardown overhead, which would triple latency and exhaust socket buffers on high-throughput resolvers.
- **TCP port 53** is automatically used in two scenarios:
  1. When response payloads exceed the 512-byte UDP limit (or EDNS0 buffer size), the server responds with the Truncation bit set (`TC=1`), prompting the client to retry over TCP.
  2. DNS Zone Transfers (AXFR/IXFR) between authoritative primary and secondary nameservers, where reliable, ordered delivery of entire zone databases is strictly required.

---

### 6.2. DNS Service Failure vs Application Server Failure
A fundamental network engineering distinction:
1. **DNS Service Failure (Layer 7 Resolution Failure):**
   - The DNS daemon (`dnsmasq`) is stopped or UDP port 53 packets are dropped.
   - The client OS fails during the name translation step before any connection is initiated.
   - Command output: `curl: (6) Could not resolve host: app.team1.test` or `dig: connection timed out`.
   - The underlying network (Layer 3/4) is completely healthy (`ping <MAC2_IP>` succeeds).
   - **Resolution:** Redundant nameservers (Primary on Mac 1 + Backup on Mac 4 via Ext A).
2. **Application Server Failure (Layer 4 / Layer 7 Service Failure):**
   - DNS resolution succeeds completely, returning `10.81.95.225`.
   - The client successfully targets the IP, but:
     - If nginx is stopped: Layer 4 failure (`curl: (7) Failed to connect: Connection refused`).
     - If both backends are stopped: Layer 7 failure (`HTTP/1.1 502 Bad Gateway` returned by nginx).
   - **Resolution:** Reverse proxy upstream health retries (`proxy_next_upstream`) or active-passive cutover to Standby Edge (Ext E).

---

### 6.3. macOS Resolver Architecture: `dig` vs `dscacheutil` / `curl`
- **`dig`:** A specialized diagnostic tool that opens a raw UDP socket directly to the IP address passed via `@<server>` (or the first nameserver in `/etc/resolv.conf`). It **completely bypasses** the macOS operating system cache and queries the wire directly.
- **`curl` / browsers / system tools:** Invoke the standard POSIX libc C function `getaddrinfo()`. On macOS, `getaddrinfo()` forwards requests via XPC IPC to the system caching daemon (`mDNSResponder`). `mDNSResponder` checks its internal memory cache:
  - If cached and the record age is less than the received TTL, it returns the cached IP with **zero network traffic**.
  - Only upon cache miss or expiration does it issue a network query.
- **Inspection Command:** `dscacheutil -q host -a name app.team1.test` inspects the active OS resolver cache.
- **Flushing Command:** `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.

---

### 6.4. Dual DNS Failover Algorithm on macOS (`scutil --dns`)
- macOS does not use standard glibc sequential resolver failover.
- The system configuration daemon (`configd`) publishes the active resolver table to the dynamic store, viewable with `scutil --dns`.
- When multiple nameservers are configured (`networksetup -setdnsservers Wi-Fi $MAC1_IP $BACKUP_DNS_IP`), `mDNSResponder` maintains background state tracking server responsiveness.
- If queries to the primary nameserver fail or time out, `mDNSResponder` switches queries to the backup nameserver with minimal failover latency (~1-2 seconds).

---

### 6.5. DNS TTL Rationale (30s vs 86400s)
- **TTL (Time To Live):** A 32-bit integer in the DNS Resource Record specifying how many seconds recursive resolvers and client stubs are permitted to cache the answer.
- **Trade-off Analysis:**
  - **High TTL (e.g. 86400s / 24 hours):** Maximizes caching efficiency, eliminates resolver query latency for returning clients, and minimizes load on authoritative nameservers. However, disaster recovery and IP migrations are delayed by up to 24 hours.
  - **Low TTL (e.g. 30s as in Phase 2):** Enables rapid disaster recovery and active-passive cutover (Ext E). When an edge node fails or requires maintenance, traffic can be diverted to the standby edge within 30 seconds. The trade-off is slightly higher UDP query traffic on the local network.

---

### 6.6. Why `.test` and not `.local` or `.internal`?
- **RFC 6762 (Multicast DNS):** Specifically reserves the `.local` top-level domain for mDNS / Apple Bonjour link-local name resolution over multicast UDP port 5353. macOS kernel networking traps all `.local` queries and refuses to send standard unicast DNS queries to port 53.
- **RFC 6761 (Special-Use Domain Names):** Formally reserves `.test` for testing and private networking. No public root zone delegation exists for `.test`, preventing private test queries from accidentally leaking to the public Internet or colliding with global domain registries.

---

## 7. Extension Learning Summaries (For Mac 4 / `PHASE2-REPORT.md`)

### Extension A: Backup DNS Failover Learning Summary
> Implementing dual-resolver high availability highlighted the critical distinction between resolver redundancy and client caching dynamics. While having a secondary nameserver on Mac 4 eliminated DNS as a single point of failure (SPOF), testing demonstrated that client failover latency depends directly on the OS resolver implementation: macOS `mDNSResponder` dynamically tracks server health and routes queries across configured servers rather than relying on strict sequential timeouts. Most importantly, the extension proved that a DNS failure manifests as a complete inability to resolve hostnames (Layer 7 resolution failure) before any TCP connection can be attempted, whereas an application or load balancer outage allows successful name resolution but fails during TCP handshaking (`Connection refused`) or HTTP processing (`502 Bad Gateway`).

### Extension B: DNS TTL & Client-Side Caching Learning Summary
> The TTL experiment illustrated the practical friction between DNS propagation speed and resolver caching guarantees. Setting a short 30-second TTL demonstrated the exact mechanics of client-side cache persistence: modifying an A-record on authoritative nameservers is not immediately reflected in applications like `curl` because the OS stub resolver (`mDNSResponder`) serves cached answers from local memory until the TTL counter expires. Crucially, comparing `dscacheutil` against `dig` exposed why administrators often experience debugging discrepancies—`dig` communicates directly with port 53 on the wire, bypassing OS caching entirely, while client applications depend on OS-level cache invalidation via `dscacheutil -flushcache` and `killall -HUP mDNSResponder`.
