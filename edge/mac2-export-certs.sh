#!/bin/bash
# MAC 2 - Ext E: bundle the edge certificate + private key for the standby edge (Mac 3).
#
#   ./edge/mac2-export-certs.sh        -> ~/Desktop/team1-edge-certs.tgz
#
# AirDrop that file to Mac 3, then on Mac 3:  ./edge/mac2-import-certs.sh ~/Downloads/team1-edge-certs.tgz
# The bundle contains a PRIVATE KEY: never commit it to git, delete it after importing.
set -e
source "$(dirname "$0")/../config.env"
C="$HOME/cn-phase1/edge/nginx/certs"
LEAF="app.$PROJECT_DOMAIN"
OUT="$HOME/Desktop/team1-edge-certs.tgz"

for f in "$LEAF.crt" "$LEAF.key" team1-ca.crt; do
  [ -f "$C/$f" ] || { echo "Missing $C/$f - run ./edge/mac2-certs.sh first"; exit 1; }
done
# Only what the standby edge needs. The CA private key stays on Mac 2.
tar -czf "$OUT" -C "$C" "$LEAF.crt" "$LEAF.key" team1-ca.crt
chmod 600 "$OUT"
echo "Bundle: $OUT"
tar -tzf "$OUT" | sed 's/^/  /'
echo
echo "1. AirDrop it to Mac 3 (standby edge, $STANDBY_EDGE_IP)"
echo "2. On Mac 3:  git pull && ./edge/mac2-import-certs.sh ~/Downloads/team1-edge-certs.tgz"
echo "3. Delete the .tgz on both Macs afterwards (it contains the private key)"
