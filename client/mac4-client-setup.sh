#!/bin/bash
# ============================================================
#  Mac 4 – Tab 2: Client Setup
#  Run this ONCE after Mac 2 sends you ca.crt
#
#  Steps:
#   1. Trust ca.crt in macOS Keychain (for Safari / Chrome)
#   2. Build ~/cn-ca-bundle.pem  (for curl – LibreSSL ignores Keychain)
#   3. Write ~/.curlrc so every curl uses the bundle automatically
#   4. Set DNS to MAC1_IP via networksetup
# ============================================================

set -e
cd "$(dirname "$0")/.."
source ./config.env

CA_CRT="${1:-ca.crt}"   # pass a path as $1 or put ca.crt in this directory

if [ ! -f "$CA_CRT" ]; then
    echo "ERROR: $CA_CRT not found."
    echo "Usage: ./client/mac4-client-setup.sh [path/to/ca.crt]"
    echo "       (Wait for Mac 2 to send you ca.crt first)"
    exit 1
fi

echo ""
echo "=========================================="
echo "  Mac 4 – Client Setup"
echo "=========================================="

# ── 1. Trust in macOS Keychain (browsers / native TLS) ─────
echo ""
echo "[1/4] Trusting $CA_CRT in macOS Keychain..."
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain "$CA_CRT"
echo "      ✓ Keychain trust set"

# ── 2. Build curl CA bundle ─────────────────────────────────
echo ""
echo "[2/4] Building ~/cn-ca-bundle.pem ..."
cat /etc/ssl/cert.pem "$CA_CRT" > "$HOME/cn-ca-bundle.pem"
echo "      ✓ Bundle written: $HOME/cn-ca-bundle.pem"

# ── 3. ~/.curlrc – proper validation, NOT -k ────────────────
echo ""
echo "[3/4] Writing ~/.curlrc ..."
# Back up existing file if present
if [ -f "$HOME/.curlrc" ]; then
    cp "$HOME/.curlrc" "$HOME/.curlrc.bak-cn"
    echo "      (backed up existing ~/.curlrc to ~/.curlrc.bak-cn)"
fi

# Remove any old cn-ca-bundle line, then append
grep -v 'cn-ca-bundle' "$HOME/.curlrc" 2>/dev/null > /tmp/curlrc.tmp || true
echo "cacert = \"$HOME/cn-ca-bundle.pem\"" >> /tmp/curlrc.tmp
cp /tmp/curlrc.tmp "$HOME/.curlrc"
echo "      ✓ ~/.curlrc updated: cacert = $HOME/cn-ca-bundle.pem"

# ── 4. Point DNS to Mac 1 (and Backup DNS if configured) ───
echo ""
SERVICE=$(networksetup -listallnetworkservices 2>/dev/null | grep -Ei "^(Wi-Fi|AirPort)$" | head -1 || echo "Wi-Fi")
echo "[4/4] Setting DNS on '$SERVICE' to Mac 1 ($MAC1_IP)${BACKUP_DNS_IP:+ and Mac 4 ($BACKUP_DNS_IP)}..."
if [ -n "${BACKUP_DNS_IP:-}" ]; then
    sudo networksetup -setdnsservers "$SERVICE" "$MAC1_IP" "$BACKUP_DNS_IP"
else
    sudo networksetup -setdnsservers "$SERVICE" "$MAC1_IP"
fi
echo "      ✓ DNS set on $SERVICE"

# Flush DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "      ✓ DNS cache flushed"

echo ""
echo "=========================================="
echo "  Setup complete! Verify with:"
echo "    dig app.$PROJECT_DOMAIN          # should return $MAC2_IP"
echo "    curl https://app.$PROJECT_DOMAIN/api/status"
echo "=========================================="
