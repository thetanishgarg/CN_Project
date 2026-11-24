# Automated tests: one script per Mac

Start all services first (backends, Mac 2 nginx, Mac 1 DNS, Mac 4 backup DNS, client DNS + CA trust). Then each person runs **their own** script:

| Mac | Command | What it checks (PDF) |
|---|---|---|
| Mac 1 | `./tests/test-mac1.sh` | Task A, Task B (DNS server + client), Tasks D/E/F from a client, 6.3 failures, Ext A/B, Ext C (blocked from a client), Ext E (standby reachable) |
| Mac 2 | `./tests/test-mac2.sh` | Task A, Task D (nginx LB), Task E (cert + TLS 1.2/1.3 + HTTP/2), Ext C (edge reaches backends), **Ext D failover and the 502**, proven on a private test copy of nginx (port 18443), so the live edge is untouched |
| Mac 3 | `./tests/test-mac3.sh` | Task A, Task C/F (Backend A), identical ETag with Backend B, Ext C (firewall rules), Ext E (standby edge) |
| Mac 4 | `./tests/test-mac4.sh` | Task A, Task C/F (Backend B), Ext A (backup DNS), the full client side (B/D/E/F, 6.3, Ext A/B/C/E), Task G capture |

- **PASS:** works as the PDF requires.
- **FAIL:** broken. The line below it says how to fix it. Every FAIL must be fixed before the demo.
- **WARN:** an optional part that isn't switched on right now. For example, "firewall not applied" is expected before Ext C, and "standby edge not running" before Ext E. Turn the part on and run the script again: it becomes PASS.

The scripts never stop or change anything on another Mac. Each run is saved to `evidence/test-results/<mac>-<time>.txt` (commit these as evidence).

**Full Phase 2 check:**
1. Mac 3 runs `sudo ./firewall/backend-firewall.sh apply` and Mac 4 runs `sudo ./firewall/mac4-ext-c-firewall.sh apply`.
2. Mac 3 runs `./edge/mac3-standby-edge.sh start`.
3. All 4 scripts run again. Everything should pass with no WARNs (Mac 4 also needs its `.pcap` from `sudo ./client/mac4-task-g-capture.sh`).

The live "watch it happen" demos still use their own scripts:
- Ext A: `dns/backup-dns-demo.sh`
- Ext B: `dns/ttl-demo.sh`
- Ext D: `./edge/mac2-ha-demo.sh demo`
- Ext E: `./edge/mac2-edge-watch.sh` together with `dns/cutover-demo.sh`
- Ext F: `troubleshoot/diagnose.sh`
