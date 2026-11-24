#!/bin/bash
# ============================================================
#  firewall/mac4-ext-c-firewall.sh — Ext C: Apply / Remove / Verify
#  firewall on Mac 4's Backend B port 3002
#
#  DELEGATES to firewall/backend-firewall.sh (Mac 3 owns it).
#  Mac 4 must NOT edit that script per team contract.
#
#  Usage:
#    sudo ./firewall/mac4-ext-c-firewall.sh apply    # lock port 3002
#    sudo ./firewall/mac4-ext-c-firewall.sh verify   # test access rules
#    sudo ./firewall/mac4-ext-c-firewall.sh remove   # restore after demo
# ============================================================
set -e
cd "$(dirname "$0")/.."
source ./config.env

ACTION="${1:-apply}"
EVDIR="evidence/11-service-isolation"
mkdir -p "$EVDIR"

case "$ACTION" in
  apply)
    echo "========================================================"
    echo "  Ext C: Applying firewall on Mac 4 — port $BACKEND_B_PORT"
    echo "  Allowed: $MAC2_IP (primary edge)"
    echo "           $STANDBY_EDGE_IP (standby edge / Mac 3)"
    echo "  Blocked: everything else"
    echo "========================================================"
    sudo ./firewall/backend-firewall.sh apply "$BACKEND_B_PORT"
    echo ""
    echo "✓ Firewall applied. Run: sudo ./firewall/mac4-ext-c-firewall.sh verify"
    ;;

  verify)
    echo "========================================================"
    echo "  Ext C: Verifying firewall rules on port $BACKEND_B_PORT"
    echo "========================================================"
    sudo ./firewall/backend-firewall.sh status "$BACKEND_B_PORT"

    echo ""
    echo "--- Self-test: local loopback (should succeed) ---"
    nc -vz 127.0.0.1 "$BACKEND_B_PORT" 2>&1 || true

    echo ""
    echo "--- Direct test from THIS Mac's LAN IP (should be BLOCKED if not an edge) ---"
    MY_IP=$(ipconfig getifaddr en0 2>/dev/null || true)
    nc -vz "$MY_IP" "$BACKEND_B_PORT" 2>&1 || echo "(blocked as expected)"

    echo ""
    echo "--- To complete verification ---"
    echo "    Ask Mac 2 (primary edge $MAC2_IP):"
    echo "      curl http://$MAC4_IP:$BACKEND_B_PORT/api/status  → should SUCCEED (200)"
    echo ""
    echo "    Ask a client (e.g. a laptop NOT in the allowed list):"
    echo "      nc -vz $MAC4_IP $BACKEND_B_PORT  → should TIMEOUT/DROP"
    echo ""
    # Save status to evidence
    sudo ./firewall/backend-firewall.sh status "$BACKEND_B_PORT" \
        > "$EVDIR/pf-rules-mac4.txt" 2>&1 || true
    echo "✓ Status saved to $EVDIR/pf-rules-mac4.txt"
    ;;

  remove)
    echo "========================================================"
    echo "  Ext C: Removing firewall from Mac 4 (post-demo restore)"
    echo "========================================================"
    sudo ./firewall/backend-firewall.sh remove "$BACKEND_B_PORT"
    echo ""
    echo "✓ Firewall removed. Backend B is now accessible from any host."
    echo "  Verify: nc -vz $MAC4_IP $BACKEND_B_PORT"
    ;;

  *)
    echo "Usage: sudo $0 {apply|verify|remove}"
    exit 1
    ;;
esac
