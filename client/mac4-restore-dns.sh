#!/bin/bash
# ============================================================
#  Mac 4 – Restore DNS after the demo
#  Run this at the very end of the session.
# ============================================================

SERVICE=$(networksetup -listallnetworkservices 2>/dev/null | grep -Ei "^(Wi-Fi|AirPort)$" | head -1 || echo "Wi-Fi")
echo "Restoring DNS on $SERVICE to automatic (Empty)..."
sudo networksetup -setdnsservers "$SERVICE" Empty
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true
echo "✓ DNS restored to default (DHCP/automatic)"
networksetup -getdnsservers "$SERVICE"
