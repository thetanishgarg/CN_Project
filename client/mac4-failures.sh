#!/bin/bash
# ============================================================
#  Mac 4 – Task: Failure Demos (Integration Owner)
#
#  Run this AFTER everyone's setup is confirmed working.
#  Coordinates with teammates over chat – see comments per step.
#
#  Saves all output to evidence/07-failures/
# ============================================================

set -e
cd "$(dirname "$0")/.."
source ./config.env

DOMAIN="app.$PROJECT_DOMAIN"
OUT="evidence/07-failures"
mkdir -p "$OUT"

pause() {
    echo ""
    echo "──────────────────────────────────────────────"
    echo "  $1"
    echo "──────────────────────────────────────────────"
    read -r -p "  Press ENTER when ready... " _
}

echo ""
echo "=========================================="
echo "  Mac 4 – 5 Failure Demos"
echo "  Saves output to: $OUT/"
echo "=========================================="

# ── DEMO 1: Wrong DNS server ─────────────────────────────────
pause "DEMO 1: Wrong DNS server – point DNS at 8.8.8.8 (Google), NOT Mac 1"
SERVICE=$(networksetup -listallnetworkservices 2>/dev/null | grep -Ei "^(Wi-Fi|AirPort)$" | head -1 || echo "Wi-Fi")
echo "Setting DNS to 8.8.8.8 temporarily on $SERVICE..."
sudo networksetup -setdnsservers "$SERVICE" 8.8.8.8
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo "--- DEMO 1: Wrong DNS server (8.8.8.8) ---" | tee "$OUT/01-wrong-dns-server.txt"
echo "dig output:" | tee -a "$OUT/01-wrong-dns-server.txt"
dig +short "$DOMAIN" 2>&1 | tee -a "$OUT/01-wrong-dns-server.txt"
echo "curl output (expect NXDOMAIN or wrong IP):" | tee -a "$OUT/01-wrong-dns-server.txt"
curl -sv "https://$DOMAIN/api/status" 2>&1 | tee -a "$OUT/01-wrong-dns-server.txt" || true
echo "✓ Demo 1 saved to $OUT/01-wrong-dns-server.txt"

# Restore DNS to Mac 1
sudo networksetup -setdnsservers "$SERVICE" "$MAC1_IP"
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "  DNS restored to $MAC1_IP"

# ── DEMO 2: Wrong DNS IP (typo in MAC1_IP) ──────────────────
pause "DEMO 2: Wrong DNS IP – point DNS at a non-existent IP"
echo "Setting DNS to 10.202.54.99 (non-existent) on $SERVICE..."
sudo networksetup -setdnsservers "$SERVICE" 10.202.54.99
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo "--- DEMO 2: Wrong DNS IP (10.202.54.99 – nonexistent) ---" | tee "$OUT/02-wrong-dns-ip.txt"
dig +short "$DOMAIN" 2>&1 | tee -a "$OUT/02-wrong-dns-ip.txt" || true
curl -sv --connect-timeout 5 "https://$DOMAIN/api/status" 2>&1 | tee -a "$OUT/02-wrong-dns-ip.txt" || true
echo "✓ Demo 2 saved to $OUT/02-wrong-dns-ip.txt"

# Restore DNS
sudo networksetup -setdnsservers "$SERVICE" "$MAC1_IP"
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "  DNS restored to $MAC1_IP"

# ── DEMO 3: One backend stopped (B stopped = only A responds) ─
pause "DEMO 3: One backend stopped – ask MAC 4 (you) to stop Backend B on this machine"
echo ""
echo "  >>> Stop backend/mac4-backend-b.sh now (Ctrl+C in Tab 1) <<<"
read -r -p "  Press ENTER once Backend B is stopped... " _

echo "--- DEMO 3: Backend B stopped (only A responds) ---" | tee "$OUT/03-one-backend-stopped.txt"
for i in {1..8}; do
    echo -n "  Request $i: " | tee -a "$OUT/03-one-backend-stopped.txt"
    curl -s -D - -o /dev/null "https://$DOMAIN/api/status" \
        | grep -Ei "^HTTP|^X-Backend" | tr -d '\r' \
        | tee -a "$OUT/03-one-backend-stopped.txt"
done
echo "✓ Demo 3 saved to $OUT/03-one-backend-stopped.txt"

echo ""
echo "  >>> Restart Backend B now (run backend/mac4-backend-b.sh in Tab 1) <<<"
read -r -p "  Press ENTER once Backend B is running again... " _

# ── DEMO 4: Both backends stopped → 502 ─────────────────────
pause "DEMO 4: Both backends stopped – ask Mac 3 AND Mac 4 to stop their backends"
echo ""
echo "  >>> Ask Mac 3 to stop Backend A, AND stop Backend B yourself <<<"
read -r -p "  Press ENTER once BOTH backends are stopped... " _

echo "--- DEMO 4: Both backends stopped → 502 Bad Gateway ---" | tee "$OUT/04-both-backends-stopped.txt"
for i in {1..4}; do
    echo -n "  Request $i: " | tee -a "$OUT/04-both-backends-stopped.txt"
    curl -sv "https://$DOMAIN/api/status" 2>&1 \
        | grep -Ei "< HTTP|502|Bad Gateway" \
        | tee -a "$OUT/04-both-backends-stopped.txt" || true
done
echo "✓ Demo 4 saved to $OUT/04-both-backends-stopped.txt"

echo ""
echo "  >>> Ask Mac 3 to restart Backend A AND restart Backend B yourself <<<"
read -r -p "  Press ENTER once BOTH backends are running again... " _

# ── DEMO 5: Wrong port ───────────────────────────────────────
pause "DEMO 5: Wrong port – hit port 3001 directly instead of 443"
echo "--- DEMO 5: Wrong port (curl to :8080 which nothing listens on) ---" | tee "$OUT/05-wrong-port.txt"
curl -sv --connect-timeout 5 "https://$DOMAIN:8080/api/status" 2>&1 \
    | tee -a "$OUT/05-wrong-port.txt" || true
echo "--- Also show direct hit to backend port without TLS ---" | tee -a "$OUT/05-wrong-port.txt"
curl -sv --connect-timeout 5 "https://$MAC2_IP:3001/api/status" 2>&1 \
    | tee -a "$OUT/05-wrong-port.txt" || true
echo "✓ Demo 5 saved to $OUT/05-wrong-port.txt"

echo ""
echo "=========================================="
echo "  All 5 failure demos complete!"
echo "  Evidence saved in: $OUT/"
ls -la "$OUT/"
echo "=========================================="
