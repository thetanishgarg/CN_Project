# Evidence

**Start here: [EVIDENCE.pdf](EVIDENCE.pdf)** (or `EVIDENCE.html` in a browser). It covers every task and extension, and each figure names the file and lines it came from.

| Folder | Requirement | Recorded on the four-Mac LAN | Recorded on one Mac, 24 Nov |
|---|---|---|---|
| `01-lan/` | Task A | `lan-reachability-recorded.txt`, `mac1-network-info.txt` | |
| `02-dns/` | Task B | `dns-recorded.txt` | `dns-local.txt` |
| `03-https/` | Task E | `https-recorded.txt`, `server-cert-from-capture.pem` | `certificate-verification.txt` (verifies the captured certificate) |
| `04-load-balancing/` | Tasks C, D | `round-robin-recorded.txt` | `backends-local.txt` |
| `05-wireshark/` | Task G | `full-flow.pcap`, `team-traffic-only.pcap`, `packet-ladder-*.txt`, `dns-response-decoded.txt`, `clienthello-decoded.txt` | |
| `06-caching/` | Task F | `caching-recorded.txt`, `../05-wireshark/cache-headers.txt` | `caching-local.txt`, `chrome-cache-http1.0.json`, `chrome-cache-http1.1.json` |
| `07-failures/` | Section 6.3 | `failures-recorded.txt` | `failure-signatures-local.txt` |
| `08-backup-dns/` | Ext A | `backup-dns-recorded.txt`, `backup-dns-log-excerpt.txt` | `backup-dns-local.txt` |
| `09-ttl/` | Ext B | see `12-edge-cutover/` | `ttl-local.txt` |
| `10-ha-failover/` | Ext D | `ha-failover-120858.txt` | |
| `11-service-isolation/` | Ext C | `isolation-recorded.txt` | |
| `12-edge-cutover/` | Ext E | `edge-cutover-*.txt`, `cutover-transitions.txt` | |
| `13-troubleshooting/` | Ext F | `incident-20261123.txt` | `diagnose-no-lan.txt` |
| `test-results/` | all | every saved run, failures included | |
| `screenshots/` | | one PNG per figure, plus two real Chrome screenshots (`chrome-*.png`) | |

`*-recorded.txt`, `*-excerpt.txt`, `cutover-transitions.txt` and `incident-20261123.txt` are verbatim extracts with source file and line number. The numbered PNGs are images of the figures in the PDF, not photographs of a terminal window.

## Rebuild and extend

```bash
./evidence/build/build.sh
```

- `build/capture-lan.sh`: records what still needs all four Macs (open it for the one-line commands).
- `build/capture-local.sh`, `build/chrome-cache.mjs`: the single-Mac recordings.
- `build/decode-pcap.sh`: regenerates the filtered capture, the decoded packet ladders and the extracted certificate from `05-wireshark/full-flow.pcap`.
- `build/derive.py`: regenerates the `*-recorded.txt` extracts from the saved test and watcher logs.
- Put window screenshots (Wireshark, Safari padlock) in `screenshots/manual/*.png`; the next build adds them.

Check integrity with `cd evidence && shasum -a 256 -c MANIFEST.sha256`.
