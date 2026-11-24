# Audit of the evidence and the claims made about it (24 Nov 2026)

Team working note.

## Fix before the demo

1. **`config.env` looks wrong.** `MAC2_IP="10.102.29.224"` mixes two networks (the others are `10.128.29.x`) and ends in `.224`, which is Mac 1's number. On 24 Nov at 16:02 Mac 4 was `10.102.29.68`, and the address table showed Mac 2's hardware address (`7e:45:9b:f9:71:19`) at `10.102.29.225`. So that network was probably 10.102.29.224 / .225 / .70 / .68. Check with `ipconfig getifaddr en0` on each Mac.
2. **Mac 4's running DNS is stale.** Its `dnsmasq` (started 24 Nov 15:36) still answers `10.128.139.225`. Restart it after fixing `config.env`.

## Files removed or not relied on

| File | Why | Replaced by |
|---|---|---|
| `08-backup-dns/backup-dns-failover.txt` (**removed**) | Mixes 10.202.54.x and 10.81.95.x and calls both "directly reachable" from one /24; no machine-written log contains 10.81.95.x. Its dig output also has no OPT section although it reports one additional record. Reads as an illustration | LAN checks and a one-Mac run now; `capture-lan.sh failover` for the real thing |
| `09-ttl/ttl-caching-demo.txt` (**removed**) | Same mixed networks, commentary inside the output | `12-edge-cutover/edge-cutover-121149.txt`, which shows real caching |
| `01-lan/mac1-network-info.txt` (kept) | Hand-assembled ("likely /24"); its private MAC `6e:a4:d1:e3:8c:a0` differs from the DNS server's on the wire, `5e:a4:d1:e3:8a:a0`. Only its address lines are shown in the PDF | `capture-lan.sh lan` on Mac 1 |
| `test-results/mac1-20261123-115654.txt` (kept) | Run on Mac 2 (the first check says so); 13 failed | Run `tests/test-mac1.sh` on Mac 1 |

Removed files are still in git history (`git show <commit>^:<path>`).

## Claims in the report that the files do not support

| Claim | Where | What the files show |
|---|---|---|
| test-mac1 and test-mac3 "passed" | `report.tex`, results table | No valid Mac 1 run and no Mac 3 run is saved |
| test-mac4 final run 45/45 | `report.tex` | 45/45 was at 12:03; the final run is 44 passed, 0 failed, 1 warning |
| Full ping matrix in `01-lan/` | `report.tex` | Not there; pings from Mac 2 and Mac 4 only |
| `/` serves an HTML page | `report.tex`, Task C | `backend.py` returns JSON |
| `Cache-Control: public, max-age=60` | `report.tex`, Task F | `max-age=60`, no `public` |
| Upstream keepalive was removed | `report.tex`, Task D and challenges | No version of `nginx-script.sh` in git contains it |
| Ext D is caching; `10-ha-failover` is Ext E | `PHASE2-REPORT.md` | Ext D is backend failover and `10-ha-failover` is its folder; `12-edge-cutover` is Ext E |
| pf anchor `team1-backend` | `PHASE2-REPORT.md`, `RUNBOOK.md` | It is `com.apple/team1-backend`; the runbook's `pfctl -a team1-backend -sr` shows nothing |
| A blocked edge gets "Connection refused" | `RUNBOOK.md` fault 9 | The rule is `block drop`, so it times out |
| Learning summaries | `PHASE2-REPORT.md` | Still placeholders |
| Every request returned 200 during cutover | `report.tex` | True for the cutover window (84 of 84). The full file also has 197 failures from the later outage; expect the question |

## Technical findings

- **AAAA lookups return NXDOMAIN** for `app.team1.test` (packet capture and Mac 4's DNS log), although the name exists. "No data" would be correct. macOS coped in every recorded run.
- **Chrome did not revalidate HTTP/1.0 responses**, so a browser pointed at a backend port never shows 304. Demonstrate it through the edge.
- **Cutting back to Mac 2 failed on 23 Nov.** The client followed DNS to an edge that was not serving. Check the target first.
- **`team-traffic-only.pcap` is the one to hand in.** `full-flow.pcap` also holds unrelated background traffic from Mac 4.
- **A non-existent address looked open on port 443** on 24 Nov, so `nc -z` alone is not proof of a server on that network. `diagnose.sh` layer 3 relies on it; layer 4 catches the difference.

## Changed on 24 Nov

Added the files marked in `README.md`, `build/`, `screenshots/`, `EVIDENCE.*` and `MANIFEST.sha256`. Removed the two files above. In `06-caching/README.md`, replaced two outdated IP addresses with `config.env` variables. Repo-wide cleanup (generated config, stale dumps, duplicate deck) is described in the pull request.
