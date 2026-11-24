#!/bin/bash
# STANDBY EDGE (Mac 3) - Ext E: install the edge certificate + key received from Mac 2.
#
#   ./edge/mac2-import-certs.sh ~/Downloads/team1-edge-certs.tgz
#
# Then start the standby edge:   ./edge/nginx-script.sh start standby
set -e
source "$(dirname "$0")/../config.env"
BUNDLE="${1:-$HOME/Downloads/team1-edge-certs.tgz}"
C="$HOME/cn-phase1/edge/nginx/certs"
LEAF="app.$PROJECT_DOMAIN"

[ -f "$BUNDLE" ] || { echo "Bundle not found: $BUNDLE (AirDrop it from Mac 2: ./edge/mac2-export-certs.sh)"; exit 1; }
command -v nginx >/dev/null || { echo "nginx not installed:  brew install nginx"; exit 1; }

mkdir -p "$C"
tar -xzf "$BUNDLE" -C "$C"
chmod 600 "$C/$LEAF.key"

# Same checks a client will do: signed by our CA, valid for the name, key matches cert
openssl verify -CAfile "$C/team1-ca.crt" "$C/$LEAF.crt"
openssl x509 -in "$C/$LEAF.crt" -noout -subject -enddate -ext subjectAltName
[ "$(openssl x509 -in "$C/$LEAF.crt" -noout -modulus | md5)" = "$(openssl rsa -in "$C/$LEAF.key" -noout -modulus 2>/dev/null | md5)" ] \
  && echo "Private key matches certificate." || { echo "KEY DOES NOT MATCH CERT"; exit 1; }

echo
echo "Installed in $C"
echo "Delete the bundle now:  rm '$BUNDLE'"
echo "Start the standby edge: ./edge/nginx-script.sh start standby"
