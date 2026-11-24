#!/bin/bash
# Ext E - DNS-based edge cutover watcher (run on a CLIENT: Mac 1 or Mac 4)
#
#   ./edge/mac2-edge-watch.sh          every 2 s show: what the DNS server says now,
#                                 what THIS Mac's cache still uses, and which edge answered
#
# Run it, then Mac 1 does:  ./dns/cutover-demo.sh cutover
# You will see the DNS server switch to the standby immediately, while this Mac keeps
# going to the old edge (X-Edge: mac2-primary) until its cached answer's TTL (30 s)
# runs out, then X-Edge: mac3-standby.  ./client flush makes it switch at once.
# Output saved to evidence/12-edge-cutover/
cd "$(dirname "$0")/.."
source ./config.env
APP="app.$PROJECT_DOMAIN"
URL="https://$APP"; [ "$HTTPS_PORT" != "443" ] && URL="$URL:$HTTPS_PORT"
name() { case "$1" in "$MAC2_IP") echo "$1 (Mac2 primary)";; "$STANDBY_EDGE_IP") echo "$1 (Mac3 standby)";; "") echo "-";; *) echo "$1";; esac; }

mkdir -p evidence/12-edge-cutover
LOG="evidence/12-edge-cutover/edge-cutover-$(date +%H%M%S).txt"
exec > >(tee "$LOG") 2>&1
echo "===== Ext E: edge cutover watch ($(date))   TTL=${DNS_TTL}s   Ctrl+C to stop ====="
printf "%-9s %-26s %-26s %-14s %s\n" TIME "DNS SERVER SAYS (dig)" "THIS MAC USES (cache)" "X-EDGE" STATUS
while true; do
  srv=$(dig +short +time=1 +tries=1 "$APP" | tail -1)                      # asks the DNS server directly
  os=$(dscacheutil -q host -a name "$APP" | awk '/ip_address/{print $2; exit}')  # macOS resolver + cache
  res=$(curl -s --max-time 4 --cacert ./team1-ca.crt -o /dev/null -D - "$URL/api/status" | tr -d '\r' | \
        awk '/^HTTP/{s=$2} tolower($1)=="x-edge:"{e=$2} END{print (e?e:"-") " " (s?s:"FAIL")}')
  printf "%-9s %-26s %-26s %-14s %s\n" "$(date +%H:%M:%S)" "$(name "$srv")" "$(name "$os")" ${res}
  sleep 2
done
