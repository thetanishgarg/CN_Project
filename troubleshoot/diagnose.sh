#!/bin/bash
# ============================================================
#  troubleshoot/diagnose.sh — Ext F: Layer-by-layer diagnosis
#
#  Run from ANY client Mac. Stops at the first failing layer
#  and prints exactly what's wrong and how to fix it.
#
#  Layers checked (in order):
#    1. DNS  — resolves? correct IP? which server? stale cache?
#    2. IP   — ping to the edge
#    3. TCP  — nc -vz host 443
#    4. TLS  — openssl s_client: cert valid, name match, expiry
#    5. HTTP — status code; 502 = backends down
#
#  Usage:
#    ./troubleshoot/diagnose.sh
#    ./troubleshoot/diagnose.sh app.team1.test   (default)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/config.env"

TARGET="${1:-app.$PROJECT_DOMAIN}"
EDGE_IP="$MAC2_IP"
CA_FILE="$SCRIPT_DIR/team1-ca.crt"
PASS="\033[1;32m✓ PASS\033[0m"
FAIL="\033[1;31m✗ FAIL\033[0m"
INFO="\033[1;33m→\033[0m"

echo ""
echo "============================================================"
echo "  TEAM 1 — Layer-by-Layer Diagnostic"
echo "  Target : $TARGET"
echo "  Time   : $(date)"
echo "============================================================"

# ── LAYER 1: DNS ─────────────────────────────────────────────
echo ""
echo "[ LAYER 1 ] DNS"
echo "  Querying: $TARGET ..."

DNS_ANSWER=$(dig +short +timeout=3 "$TARGET" A 2>/dev/null || true)
DNS_SERVER=$(dig +short +timeout=3 "$TARGET" A 2>/dev/null; dig "$TARGET" A 2>/dev/null | grep ";; SERVER:" | awk '{print $3}' || true)
DNS_SERVER_LINE=$(dig "$TARGET" A 2>/dev/null | grep ";; SERVER:" | awk '{print $3}' || echo "unknown")

if [ -z "$DNS_ANSWER" ]; then
    echo -e "  $FAIL — No DNS answer for $TARGET"
    echo ""
    echo "  DIAGNOSIS: DNS resolution failure."
    echo "  Likely causes:"
    echo "    a) Your DNS is not set to Mac 1 ($MAC1_IP) or Mac 4 ($BACKUP_DNS_IP)"
    echo "       Fix: sudo ./dns/set-client-dns.sh set"
    echo "    b) Both primary AND backup dnsmasq are down"
    echo "       Fix: Mac 1: sudo ./dns/start-dns.sh"
    echo "            Mac 4: sudo ./dns/mac4-backup-dns.sh start"
    echo "    c) Stale /etc/resolv.conf pointing to wrong server"
    echo "       Fix: sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
    echo ""
    echo "  Current client DNS servers:"
    networksetup -getdnsservers "$(networksetup -listallnetworkservices | grep -Ei 'Wi-Fi|AirPort' | head -1)" 2>/dev/null || true
    echo ""
    echo "  Stale cache check (direct query to Mac 1):"
    dig +short +timeout=3 @"$MAC1_IP" "$TARGET" 2>/dev/null || echo "  Mac 1 DNS unreachable"
    echo ""
    echo "  Stopping diagnosis at Layer 1."
    exit 1
fi

echo -e "  $PASS — Resolved: $DNS_ANSWER"
echo "  $INFO  Answered by: $DNS_SERVER_LINE"

# Check if the IP is correct
if [ "$DNS_ANSWER" != "$APP_TARGET_IP" ] && [ "$DNS_ANSWER" != "$MAC2_IP" ] && [ "$DNS_ANSWER" != "$MAC3_IP" ]; then
    echo -e "  $FAIL — Resolved to $DNS_ANSWER but expected $APP_TARGET_IP or $MAC2_IP"
    echo ""
    echo "  DIAGNOSIS: DNS returns a WRONG IP."
    echo "  Likely causes:"
    echo "    a) APP_TARGET_IP in config.env was changed but dnsmasq not restarted"
    echo "       Fix: Mac 1: sudo ./dns/start-dns.sh (regenerates config from config.env)"
    echo "    b) Faculty changed DNS record on Mac 1 directly"
    echo "       Fix: Check /etc/dnsmasq.conf on Mac 1 for the address= line"
    echo "    c) Client is querying a wrong DNS server (8.8.8.8 returns NXDOMAIN for .test)"
    echo "       Fix: sudo ./dns/set-client-dns.sh set"
    echo ""
    echo "  Stopping diagnosis at Layer 1 (wrong IP)."
    exit 1
fi

# Check which DNS server answered — backup vs primary
if echo "$DNS_SERVER_LINE" | grep -q "$BACKUP_DNS_IP"; then
    echo -e "  $INFO  NOTE: Answered by BACKUP DNS ($BACKUP_DNS_IP / Mac 4). Primary may be down."
elif echo "$DNS_SERVER_LINE" | grep -q "$MAC1_IP"; then
    echo -e "  $INFO  Answered by PRIMARY DNS ($MAC1_IP / Mac 1) — normal."
fi

# Cache staleness check
echo -e "  $INFO  Cache flush check: direct query to Mac 1..."
DIRECT_ANSWER=$(dig +short +timeout=3 @"$MAC1_IP" "$TARGET" 2>/dev/null || echo "TIMEOUT")
if [ "$DIRECT_ANSWER" = "TIMEOUT" ] || [ -z "$DIRECT_ANSWER" ]; then
    echo -e "  $INFO  Mac 1 DNS not reachable directly (may be relying on backup)"
else
    echo -e "  $INFO  Mac 1 direct answer: $DIRECT_ANSWER"
fi

# ── LAYER 2: IP (Ping) ───────────────────────────────────────
echo ""
echo "[ LAYER 2 ] IP — Ping to edge ($DNS_ANSWER)"

if ping -c 2 -W 2 "$DNS_ANSWER" &>/dev/null 2>&1; then
    RTT=$(ping -c 2 -W 2 "$DNS_ANSWER" 2>/dev/null | tail -1 | awk -F '/' '{print $5}' || echo "?")
    echo -e "  $PASS — $DNS_ANSWER is reachable (avg RTT: ${RTT}ms)"
else
    echo -e "  $FAIL — Cannot ping $DNS_ANSWER"
    echo ""
    echo "  DIAGNOSIS: IP-level connectivity failure."
    echo "  Likely causes:"
    echo "    a) Mac 2 (nginx/edge) is off or crashed"
    echo "       Fix: Mac 2: ./edge/nginx-script.sh start"
    echo "    b) Mac 2's IP has changed (hotspot reassigned it)"
    echo "       Fix: Mac 2 runs 'ipconfig getifaddr en0', updates config.env, Mac 1 restarts DNS"
    echo "    c) Not on the same Wi-Fi subnet"
    echo "       Fix: All Macs must be on the same hotspot. Check: ipconfig getifaddr en0"
    echo ""
    echo "  Stopping diagnosis at Layer 2."
    exit 1
fi

# ── LAYER 3: TCP ─────────────────────────────────────────────
echo ""
echo "[ LAYER 3 ] TCP — nc -vz $DNS_ANSWER 443"

if nc -vz -G 3 "$DNS_ANSWER" 443 2>&1 | grep -q "succeeded\|open"; then
    echo -e "  $PASS — TCP port 443 is open on $DNS_ANSWER"
else
    NC_OUT=$(nc -vz -G 3 "$DNS_ANSWER" 443 2>&1 || true)
    echo -e "  $FAIL — TCP connection to $DNS_ANSWER:443 failed"
    echo "  nc output: $NC_OUT"
    echo ""
    echo "  DIAGNOSIS: nginx is not listening on port 443."
    echo "  Likely causes:"
    echo "    a) nginx stopped or crashed on Mac 2"
    echo "       Fix: Mac 2: sudo ./edge/nginx-script.sh start"
    echo "    b) nginx started on wrong port (check PORT= in edge/nginx-script.sh)"
    echo "       Fix: Mac 2: ./edge/nginx-script.sh status"
    echo "    c) macOS firewall on Mac 2 blocking port 443"
    echo "       Fix: Mac 2: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add \$(which nginx)"
    echo ""
    echo "  Stopping diagnosis at Layer 3."
    exit 1
fi

# ── LAYER 4: TLS ─────────────────────────────────────────────
echo ""
echo "[ LAYER 4 ] TLS — openssl s_client (SNI: $TARGET, CA: team1-ca.crt)"

TLS_OUT=$(echo "" | openssl s_client \
    -connect "$DNS_ANSWER:443" \
    -servername "$TARGET" \
    -CAfile "$CA_FILE" \
    -verify_return_error 2>&1 || true)

# Cert validity
if echo "$TLS_OUT" | grep -q "Verify return code: 0 (ok)"; then
    echo -e "  $PASS — Certificate valid and trusted by team1-ca.crt"
elif echo "$TLS_OUT" | grep -q "certificate has expired"; then
    echo -e "  $FAIL — Certificate is EXPIRED"
    echo ""
    echo "  DIAGNOSIS: TLS certificate has expired."
    echo "  Fix: Mac 2 regenerates cert with ./edge/mac2-certs.sh, then ./edge/nginx-script.sh reload"
    echo ""
    echo "  Stopping diagnosis at Layer 4 (expired cert)."
    exit 1
elif echo "$TLS_OUT" | grep -q "self.signed\|unable to get local issuer"; then
    echo -e "  $FAIL — Certificate NOT trusted (CA not in bundle)"
    echo ""
    echo "  DIAGNOSIS: ca.crt not trusted on this client."
    echo "  Fix: ./client/mac4-client-setup.sh ca.crt  (re-run Keychain + curlrc setup)"
    echo ""
    echo "  Stopping diagnosis at Layer 4 (untrusted CA)."
    exit 1
else
    TLS_ERR=$(echo "$TLS_OUT" | grep "Verify return code" || echo "unknown TLS error")
    echo -e "  $FAIL — TLS error: $TLS_ERR"
    echo ""
    echo "  DIAGNOSIS: TLS negotiation failed."
    echo "  Likely causes:"
    echo "    a) Wrong certificate served (CN doesn't match $TARGET)"
    echo "       Check: echo \"\$TLS_OUT\" | grep 'subject'"
    echo "    b) Faculty replaced cert with expired/wrong one"
    echo "    c) nginx ssl_certificate path wrong in nginx.conf"
    echo "       Fix: Mac 2: ./edge/nginx-script.sh reload"
    echo ""
    echo "  Stopping diagnosis at Layer 4."
    exit 1
fi

# SNI / CN name match
CERT_CN=$(echo "$TLS_OUT" | grep "subject" | head -1 || true)
echo "  $INFO  Certificate: $CERT_CN"

# Expiry
EXPIRY=$(echo "$TLS_OUT" | grep "notAfter" | head -1 || true)
echo "  $INFO  Expiry: $EXPIRY"

# ── LAYER 5: HTTP ────────────────────────────────────────────
echo ""
echo "[ LAYER 5 ] HTTP — GET https://$TARGET/api/status"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --cacert "$CA_FILE" \
    --max-time 5 \
    "https://$TARGET/api/status" 2>/dev/null || echo "000")

HTTP_BODY=$(curl -s \
    --cacert "$CA_FILE" \
    --max-time 5 \
    "https://$TARGET/api/status" 2>/dev/null || true)

case "$HTTP_CODE" in
  200)
    BACKEND=$(curl -s -D - -o /dev/null --cacert "$CA_FILE" --max-time 5 "https://$TARGET/api/status" 2>/dev/null | grep -i "^X-Backend:" | tr -d '\r' || echo "unknown")
    echo -e "  $PASS — HTTP 200 OK  |  $BACKEND"
    ;;
  502)
    echo -e "  $FAIL — HTTP 502 Bad Gateway"
    echo ""
    echo "  DIAGNOSIS: nginx is running but BOTH backends are down or unreachable."
    echo "  Likely causes:"
    echo "    a) Backend A (Mac 3:3001) crashed"
    echo "       Fix: Mac 3: BACKEND_NAME=A BACKEND_PORT=3001 python3 backend/backend.py"
    echo "    b) Backend B (Mac 4:3002) crashed"
    echo "       Fix: Mac 4: ./backend/mac4-backend-b.sh"
    echo "    c) Firewall on Mac 3 or Mac 4 blocking Mac 2's connection"
    echo "       Fix: Mac 3/4: sudo ./firewall/mac4-ext-c-firewall.sh remove"
    echo "    d) Wrong upstream port in nginx.conf"
    echo "       Fix: Mac 2: check BACKEND_A/B in edge/nginx-script.sh, ./edge/nginx-script.sh reload"
    echo ""
    echo "  Quick backend reachability check:"
    curl -s --max-time 2 "http://$MAC3_IP:$BACKEND_A_PORT/api/status" 2>/dev/null \
        && echo "  Mac 3 Backend A: reachable" \
        || echo "  Mac 3 Backend A: UNREACHABLE"
    curl -s --max-time 2 "http://$MAC4_IP:$BACKEND_B_PORT/api/status" 2>/dev/null \
        && echo "  Mac 4 Backend B: reachable" \
        || echo "  Mac 4 Backend B: UNREACHABLE"
    exit 1
    ;;
  000)
    echo -e "  $FAIL — No response from HTTPS (curl timed out)"
    echo ""
    echo "  DIAGNOSIS: Likely a TLS or TCP issue that slipped through earlier checks."
    echo "  Run: curl -v --cacert team1-ca.crt https://$TARGET/api/status"
    exit 1
    ;;
  *)
    echo -e "  $FAIL — Unexpected HTTP $HTTP_CODE"
    echo "  Body: $HTTP_BODY"
    exit 1
    ;;
esac

echo ""
echo "============================================================"
echo -e "  \033[1;32mALL 5 LAYERS PASS\033[0m — System is healthy."
echo "  DNS → IP → TCP → TLS → HTTP: everything works end-to-end."
echo "============================================================"
echo ""
