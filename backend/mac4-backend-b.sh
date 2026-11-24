#!/bin/bash
# ============================================================
#  Mac 4 – Tab 1: Run Backend B
#  SHARED RULE: Do NOT edit backend/backend.py – Mac 3 owns it.
#  Just run it with the right env vars.
# ============================================================

cd "$(dirname "$0")/.."
source ./config.env

echo ""
echo "=========================================="
echo "  Mac 4 – Backend B  (port $BACKEND_B_PORT)"
echo "=========================================="
echo "  My IP : $MAC4_IP"
echo "  Listening on 0.0.0.0:$BACKEND_B_PORT"
echo "  Press Ctrl+C to stop."
echo ""

BACKEND_NAME=B BACKEND_PORT=$BACKEND_B_PORT python3 backend/backend.py
