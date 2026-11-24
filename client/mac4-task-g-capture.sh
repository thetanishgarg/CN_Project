#!/bin/bash
# ============================================================
#  Mac 4 – Task G: Wireshark / tcpdump evidence capture
#
#  What this captures:
#   - DNS query/response (port 53/UDP) → shows MAC2_IP as answer
#   - TCP 3-way handshake to port 443 (SYN/SYN-ACK/ACK)
#   - TLS 1.2 handshake (ClientHello, ServerHello, Certificate,
#     ChangeCipherSpec) – visible because --tlsv1.2 --tls-max 1.2
#   - Encrypted Application Data (TLS record type 23)
#   - Additional normal curls for load-balancing evidence
#
#  After capture, open in Wireshark with these display filters:
#   dns
#   tcp.flags.syn==1
#   tls.handshake
#   tls.record.content_type==23
# ============================================================

set -e
cd "$(dirname "$0")/.."
source ./config.env

DOMAIN="app.$PROJECT_DOMAIN"
PCAP="evidence/05-wireshark/full-flow.pcap"
INTERFACE="en0"

echo ""
echo "=========================================="
echo "  Mac 4 – Task G: tcpdump Capture"
echo "=========================================="
echo "  Domain : $DOMAIN"
echo "  PCAP   : $PCAP"
echo "  Filter : port 53 or port 443"
echo ""

# ── Flush DNS cache first ────────────────────────────────────
echo "[1/4] Flushing DNS cache..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "      ✓ DNS cache flushed"

# ── Start tcpdump in background ──────────────────────────────
echo ""
echo "[2/4] Starting tcpdump on $INTERFACE..."
mkdir -p evidence/05-wireshark
sudo tcpdump -i "$INTERFACE" -w "$PCAP" "port 53 or port 443" &
TCPDUMP_PID=$!
echo "      ✓ tcpdump running (PID $TCPDUMP_PID)"
sleep 1

# ── TLS 1.2 curl (Certificate message visible in Wireshark) ──
echo ""
echo "[3/4] Running TLS 1.2 curl (Certificate visible in pcap)..."
curl -v --tlsv1.2 --tls-max 1.2 \
    "https://$DOMAIN/api/status" \
    2>&1 | tee evidence/05-wireshark/tls12-curl-output.txt
echo ""
echo "      ✓ TLS 1.2 request complete"
sleep 1

# ── Normal curls (TLS 1.3, load-balancing, encrypted data) ──
echo ""
echo "[4/4] Running normal curls for encrypted Application Data..."
for i in 1 2 3 4; do
    echo -n "  curl $i → "
    curl -s -D - -o /dev/null "https://$DOMAIN/api/status" \
        | grep -Ei "^HTTP|^X-Backend" | tr -d '\r'
    sleep 0.5
done

# Also hit /api/cache for the caching evidence in pcap
curl -sI "https://$DOMAIN/api/cache" >> evidence/05-wireshark/cache-headers.txt 2>&1 || true

# ── Stop capture ─────────────────────────────────────────────
sleep 1
echo ""
echo "Stopping tcpdump..."
sudo kill -INT "$TCPDUMP_PID" 2>/dev/null || true
sleep 2
echo "✓ Capture saved to: $PCAP"

echo ""
echo "=========================================="
echo "  Open $PCAP in Wireshark, then use:"
echo ""
echo "  Display Filter         What you see"
echo "  ─────────────────────  ──────────────────────────────────"
echo "  dns                    DNS query (ephemeral→53) + answer=$MAC2_IP"
echo "  tcp.flags.syn==1       SYN / SYN-ACK to :443 with seq/ack"
echo "  tls.handshake          ClientHello(SNI), ServerHello, Cert, CCS"
echo "  tls.record.content_type==23   Encrypted Application Data"
echo ""
echo "  Screenshot each filter output for evidence/05-wireshark/"
echo "=========================================="
