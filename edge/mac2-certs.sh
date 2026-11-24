#!/bin/bash
# MAC 2 - TLS certificates (Task E)
# Uses the existing Team1 Local CA (creates one only if missing) and issues the
# server certificate for app/api.<domain>, signed by that CA.
# Output: ~/cn-phase1/edge/nginx/certs/app.<domain>.crt / .key   (used by nginx)
#         ./team1-ca.crt   (copy of the CA cert -> every client must trust this)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config.env"
D="$HOME/cn-phase1/edge/nginx/certs"; mkdir -p "$D"; cd "$D"
LEAF="app.$PROJECT_DOMAIN"

if [ ! -f team1-ca.crt ]; then
  echo "== Creating Team1 Local CA"
  openssl req -x509 -new -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -keyout team1-ca.key -out team1-ca.crt -subj "/C=IN/O=Team1/CN=Team1 Local CA" \
    -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
fi

echo "== Issuing $LEAF certificate (signed by Team1 Local CA)"
cat > "$LEAF.ext" <<EOF
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:app.$PROJECT_DOMAIN,DNS:api.$PROJECT_DOMAIN
EOF
openssl req -new -newkey rsa:2048 -nodes -sha256 -keyout "$LEAF.key" -out "$LEAF.csr" \
  -subj "/C=IN/O=Team1/CN=$LEAF"
# 365 days: macOS rejects server certs valid for more than 825 days
openssl x509 -req -in "$LEAF.csr" -CA team1-ca.crt -CAkey team1-ca.key -CAcreateserial \
  -out "$LEAF.crt" -days 365 -sha256 -extfile "$LEAF.ext"
chmod 600 team1-ca.key "$LEAF.key"

cp team1-ca.crt "$ROOT/team1-ca.crt"
echo
openssl verify -CAfile team1-ca.crt "$LEAF.crt"
openssl x509 -in "$LEAF.crt" -noout -subject -issuer -enddate -ext subjectAltName,extendedKeyUsage
echo
echo "Done. AirDrop team1-ca.crt (in the repository root) to Mac 1, 3, 4 if they don't trust it yet."
