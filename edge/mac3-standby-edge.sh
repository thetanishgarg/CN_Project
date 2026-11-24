#!/bin/bash
# edge/mac3-standby-edge.sh
# =============================================================================
# Mac 3: Standby nginx Edge — Ext E setup helper
#
# Run AFTER:
#   1. brew install nginx (once, if not already installed)
#   2. Mac 2 runs edge/mac2-export-certs.sh and AirDrops the .tgz to Mac 3
#   3. This Mac runs:  ./edge/mac2-import-certs.sh ~/Downloads/team1-edge-certs.tgz
#
# USAGE
#   ./edge/mac3-standby-edge.sh start    # write config + start standby nginx
#   ./edge/mac3-standby-edge.sh stop     # stop standby nginx
#   ./edge/mac3-standby-edge.sh status   # is it running? is 443 free?
#   ./edge/mac3-standby-edge.sh precheck # verify cert + port availability before starting
#
# This script is a thin wrapper around edge/nginx-script.sh that:
#   • Checks port 443 is free before starting
#   • Passes 'standby' so edge/nginx-script.sh picks the right role/X-Edge header
#   • Prints clear instructions for the firewall exception needed (Ext C + Ext E coexist)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config.env

NGINX_SCRIPT="./edge/nginx-script.sh"

check_port_443() {
    if lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null | grep -q .; then
        echo "ERROR: Port 443 is already in use on this Mac."
        echo "       Stop whatever is listening first:"
        lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null
        exit 1
    fi
    echo "✓ Port 443 is free"
}

check_certs() {
    local N="${NGINX_PREFIX:-$HOME/cn-phase1/edge/nginx}"
    local CRT="$N/certs/app.$PROJECT_DOMAIN.crt"
    if [ ! -f "$CRT" ]; then
        echo "ERROR: Certificate not found at $CRT"
        echo "       Ask Mac 2 to run: ./edge/mac2-export-certs.sh"
        echo "       Then AirDrop the .tgz here and run: ./edge/mac2-import-certs.sh <file>"
        exit 1
    fi
    echo "✓ Certificate found: $CRT"
}

check_backends() {
    echo "Checking backend reachability (firewall must allow STANDBY_EDGE_IP=$STANDBY_EDGE_IP)..."
    if curl -s --connect-timeout 2 "http://$MAC3_IP:$BACKEND_A_PORT/api/status" > /dev/null 2>&1; then
        echo "✓ Backend A ($MAC3_IP:$BACKEND_A_PORT) reachable"
    else
        echo "⚠ Backend A ($MAC3_IP:$BACKEND_A_PORT) not reachable — is it running?"
    fi
    if curl -s --connect-timeout 2 "http://$MAC4_IP:$BACKEND_B_PORT/api/status" > /dev/null 2>&1; then
        echo "✓ Backend B ($MAC4_IP:$BACKEND_B_PORT) reachable"
    else
        echo "⚠ Backend B ($MAC4_IP:$BACKEND_B_PORT) not reachable — is it running / firewall OK?"
    fi
}

case "${1:-help}" in
    precheck)
        echo "===== Mac 3 Standby Edge Pre-flight Check ====="
        check_port_443
        check_certs
        check_backends
        echo ""
        echo "If Ext C firewall is active on Mac 4, they must run:"
        echo "  sudo ./firewall/backend-firewall.sh apply"
        echo "  (STANDBY_EDGE_IP=$STANDBY_EDGE_IP is already in the allow list)"
        ;;
    start)
        echo "===== Starting Standby nginx Edge (Mac 3) ====="
        check_port_443
        check_certs
        sudo bash "$NGINX_SCRIPT" start standby
        echo ""
        echo "Standby edge is running on :443 (X-Edge: mac3-standby)"
        echo ""
        echo "Test it directly (before DNS cutover):"
        echo "  curl -sI --resolve app.$PROJECT_DOMAIN:443:$STANDBY_EDGE_IP \\"
        echo "       https://app.$PROJECT_DOMAIN/api/status | grep -i x-edge"
        echo ""
        echo "When Mac 1 does the DNS cutover, traffic will shift here automatically."
        ;;
    stop)
        sudo bash "$NGINX_SCRIPT" stop
        ;;
    status)
        bash "$NGINX_SCRIPT" status
        ;;
    *)
        sed -n '3,20p' "$0"
        ;;
esac
