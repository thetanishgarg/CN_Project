#!/bin/bash
# ============================================================
#  dns/mac4-backup-dns.sh — Ext A: Run Backup DNS on Mac 4
#
#  Uses Mac 1's dns/start-dns.sh unchanged (team contract).
#  Just installs dnsmasq if missing, then delegates to the
#  shared script.
#
#  Usage:
#    sudo ./dns/mac4-backup-dns.sh           # start backup DNS
#    sudo ./dns/mac4-backup-dns.sh stop      # stop it
#    ./dns/mac4-backup-dns.sh status         # check if running
# ============================================================
set -e
cd "$(dirname "$0")/.."
source ./config.env

ACTION="${1:-start}"

case "$ACTION" in
  start)
    # ── 1. Install dnsmasq if not present ───────────────────
    if ! command -v dnsmasq &>/dev/null; then
        echo "[1/3] dnsmasq not found. Installing via Homebrew..."
        if ! command -v brew &>/dev/null && [ ! -x "/opt/homebrew/bin/brew" ] && [ ! -x "/usr/local/bin/brew" ]; then
            echo "ERROR: Homebrew not installed. Install from https://brew.sh first."
            exit 1
        fi
        BREW_BIN=$(command -v brew || echo "/opt/homebrew/bin/brew")
        if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            sudo -u "$SUDO_USER" "$BREW_BIN" install dnsmasq
        else
            "$BREW_BIN" install dnsmasq
        fi
        echo "      ✓ dnsmasq installed"
    else
        echo "[1/3] dnsmasq already installed: $(dnsmasq --version 2>&1 | head -1)"
    fi

    # ── 2. Confirm we are Mac 4 ──────────────────────────────
    MY_IP=$(ipconfig getifaddr en0 2>/dev/null || true)
    echo ""
    echo "[2/3] My IP: $MY_IP  (BACKUP_DNS_IP from config.env: $BACKUP_DNS_IP)"
    if [ "$MY_IP" != "$BACKUP_DNS_IP" ] && [ "$MY_IP" != "$MAC4_IP" ]; then
        echo "WARNING: My IP doesn't match MAC4_IP/BACKUP_DNS_IP."
        echo "         Continuing anyway — mac 1's script will detect the role."
    fi
    echo "       Role: BACKUP DNS (Ext A)"

    # ── 3. Delegate to Mac 1's script (DO NOT FORK) ─────────
    echo ""
    echo "[3/3] Delegating to dns/start-dns.sh (Mac 1's script, unchanged)..."
    echo "      Records:  app.$PROJECT_DOMAIN → $APP_TARGET_IP  TTL=${DNS_TTL}s"
    echo "      Port:     53/UDP on 0.0.0.0"
    echo ""
    exec sudo ./dns/start-dns.sh
    ;;

  stop)
    echo "Stopping dnsmasq (backup DNS)..."
    sudo pkill -f dnsmasq 2>/dev/null || sudo killall dnsmasq 2>/dev/null || true
    echo "✓ dnsmasq stopped"
    ;;

  status)
    echo "=== Backup DNS Status (Mac 4) ==="
    if pgrep -x dnsmasq &>/dev/null; then
        echo "✓ dnsmasq is RUNNING (PID: $(pgrep -x dnsmasq | head -1))"
        echo "  Listening:"
        sudo lsof -nP -iUDP:53 2>/dev/null | grep dnsmasq || echo "  (run as sudo to see port bindings)"
    else
        echo "✗ dnsmasq is NOT running"
    fi
    echo ""
    echo "=== Client DNS config ==="
    networksetup -getdnsservers Wi-Fi 2>/dev/null || networksetup -getdnsservers "$(networksetup -listallnetworkservices | grep -Ei 'Wi-Fi|AirPort' | head -1)"
    ;;

  *)
    echo "Usage: sudo $0 {start|stop|status}"
    exit 1
    ;;
esac
