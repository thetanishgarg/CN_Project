#!/bin/bash
# evidence/11-service-isolation/collect-evidence.sh
# =============================================================================
# Run on Mac 3 (and optionally from Mac 4) to capture Ext C demo evidence.
#
# Outputs are saved in the same directory as this script.
#
# SEQUENCE
#   1. Mac 3: Backend A running (BACKEND_NAME=A BACKEND_PORT=3001 python3 backend/backend.py)
#   2. Run this script step by step, following the prompts
#   3. The script saves timestamped .txt files for docs/phase2-report.md
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/../.."
source ./config.env

OUT="evidence/11-service-isolation"
mkdir -p "$OUT"

TS=$(date '+%Y%m%d-%H%M%S')

banner() { echo ""; echo "===== $* ====="; echo ""; }

# --------------------------------------------------------------------------- #
# STEP 1: Baseline — before firewall
# --------------------------------------------------------------------------- #
banner "STEP 1: Baseline (firewall NOT applied)"
echo "Direct access to Backend A from this Mac (should succeed):"
curl -s --connect-timeout 3 "http://$MAC3_IP:$BACKEND_A_PORT/api/status" \
    | tee "$OUT/${TS}-01-baseline-direct.txt"
echo ""
echo "(Ask Mac 4 to run:  curl -v http://$MAC3_IP:$BACKEND_A_PORT/api/status)"
echo "They should see a 200 response — save that output as step 1 baseline."
echo ""
read -rp "Press Enter when you have the Mac 4 baseline screenshot/output... "

# --------------------------------------------------------------------------- #
# STEP 2: Apply firewall
# --------------------------------------------------------------------------- #
banner "STEP 2: Apply firewall"
sudo ./firewall/backend-firewall.sh apply | tee "$OUT/${TS}-02-apply.txt"
echo ""
echo "Firewall is now active."

# --------------------------------------------------------------------------- #
# STEP 3: Show anchor rules
# --------------------------------------------------------------------------- #
banner "STEP 3: Anchor rules (status)"
sudo ./firewall/backend-firewall.sh status | tee "$OUT/${TS}-03-status.txt"

# --------------------------------------------------------------------------- #
# STEP 4: Mac 2 edge still works (via nginx → MAC2_IP → backend)
# --------------------------------------------------------------------------- #
banner "STEP 4: Edge (Mac 2) can still reach Backend A"
echo "Testing through nginx edge (should succeed — Mac 2 is in the allow list):"
curl -sk --connect-timeout 5 "https://app.$PROJECT_DOMAIN/api/status" \
    | tee "$OUT/${TS}-04-edge-ok.txt"
echo ""

# --------------------------------------------------------------------------- #
# STEP 5: Direct access from Mac 4 is BLOCKED
# --------------------------------------------------------------------------- #
banner "STEP 5: Direct access from Mac 4 is BLOCKED (you observe from here)"
echo "On Mac 4, run:"
echo "  curl -v --connect-timeout 5 http://$MAC3_IP:$BACKEND_A_PORT/api/status"
echo ""
echo "Expected: connection times out (pf drops the packet silently)."
echo "This proves the firewall is working."
echo ""
read -rp "Press Enter when Mac 4 has confirmed the timeout / paste result here: "

# --------------------------------------------------------------------------- #
# STEP 6: Remove firewall + verify restored access
# --------------------------------------------------------------------------- #
banner "STEP 6: Remove firewall (restore original pf state)"
sudo ./firewall/backend-firewall.sh remove | tee "$OUT/${TS}-06-remove.txt"
echo ""
echo "Verifying direct access is restored from this Mac:"
curl -s --connect-timeout 3 "http://$MAC3_IP:$BACKEND_A_PORT/api/status" \
    | tee "$OUT/${TS}-06-restored.txt"
echo ""
echo "(Ask Mac 4 to curl again — they should now get 200.)"

banner "Evidence saved to $OUT/"
ls -lh "$OUT/"
