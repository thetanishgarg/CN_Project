#!/bin/bash
# Closes the gaps that need all four Macs on one Wi-Fi.
# First: fix config.env, everyone `git pull`, everyone `./demo.sh ready`.
#
#   Any Mac :  ./evidence/build/capture-lan.sh lan        interface facts + ping matrix
#   Mac 4   :  ./evidence/build/capture-lan.sh client     dig, curl -v, load balancing, 304 through the edge, healthy diagnose
#   Mac 4   :  ./evidence/build/capture-lan.sh failover   Ext A, guided: Mac 1 stops its DNS, the backup answers
#   Mac 4   :  ./evidence/build/capture-lan.sh drill      Ext F, guided: a teammate breaks one thing, diagnose, fix, diagnose
#   Mac 3/4 :  sudo ./evidence/build/capture-lan.sh firewall   Ext C: the live pf rules
# Then rebuild the document:  ./evidence/build/build.sh
cd "$(dirname "$0")/../.." || exit 1
source ./config.env
E=evidence; TS=$(date +%Y%m%d-%H%M%S); APP="app.$PROJECT_DOMAIN"; URL="https://$APP"
ME=$(ipconfig getifaddr en0); WHO=unknown
for i in 1 2 3 4; do v="MAC${i}_IP"; [ "${!v}" = "$ME" ] && WHO="mac$i"; done
[ "$WHO" = unknown ] && { echo "This Mac ($ME) is not in config.env - fix that first."; exit 1; }
hdr() { echo "FOUR-MAC LAN RUN   $(date)   recorded on $WHO ($ME)"; echo "$1"; echo "----------------------------------------------------------------"; }
run() { echo; echo "\$ $*"; eval "$*" 2>&1; }
save() { tee "$1"; echo; echo "saved $1"; }
pause() { read -r -p ">> $* [Enter] " _ </dev/tty; }
flush() { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; }
case "${1:-}" in
lan) { hdr "Task A"; run "ipconfig getifaddr en0"; run "ipconfig getoption en0 subnet_mask"; run "route -n get default | grep -E 'gateway|interface'"; run "ifconfig en0 | grep ether"
       for i in 1 2 3 4; do v="MAC${i}_IP"; [ "${!v}" = "$ME" ] || run "ping -c 3 -t 5 ${!v}"; done; run "arp -an | grep -E '$MAC1_IP|$MAC2_IP|$MAC3_IP|$MAC4_IP'"; } | save "$E/01-lan/lan-$WHO-$TS.txt" ;;
client)
  { hdr "Task B"; run "dig $APP"; run "dig +short api.$PROJECT_DOMAIN"; run "dig nosuch.$PROJECT_DOMAIN | grep status"; run "scutil --dns | head -12"; } | save "$E/02-dns/dns-client-$TS.txt"
  { hdr "Task E"; run "curl -sv $URL/api/status"; run "echo | openssl s_client -connect $APP_TARGET_IP:443 -servername $APP -CAfile team1-ca.crt 2>/dev/null | grep -E 'Verify|Protocol|Cipher is|subject|issuer'"; } | save "$E/03-https/curl-v-$TS.txt"
  { hdr "Task D"; for i in $(seq 20); do curl -s -m 5 -D - -o /dev/null "$URL/api/status" | tr -d '\r' | awk -v i=$i 'tolower($1)=="x-backend:"{b=$2} tolower($1)=="x-upstream:"{u=$2} /^HTTP/{s=$2} END{printf "  %2d  HTTP %s  X-Backend %s  %s\n",i,s,b,u}'; done; } | save "$E/04-load-balancing/lb-20-requests-$TS.txt"
  { hdr "Task F, through the HTTPS edge"; run "curl -sI $URL/api/cache"; ET=$(curl -sI $URL/api/cache | tr -d '\r' | awk 'tolower($1)=="etag:"{print $2}'); run "curl -sI -H 'If-None-Match: $ET' $URL/api/cache"; run "curl -sI $URL/api/status | grep -i cache-control"; } | save "$E/06-caching/caching-edge-$TS.txt"
  { hdr "Ext F, healthy baseline"; ./troubleshoot/diagnose.sh 2>&1 | sed $'s/\e\\[[0-9;]*m//g'; } | save "$E/13-troubleshooting/diagnose-healthy-$TS.txt" ;;
failover)
  sudo -v; { hdr "Ext A"; run "networksetup -getdnsservers Wi-Fi"; flush; run "dig $APP"
    pause "Mac 1: stop dnsmasq now (./demo.sh dns stop)" 2>&1; flush; run "dig +time=2 +tries=1 @$MAC1_IP $APP | tail -2"; run "dig $APP"; run "curl -s -o /dev/null -w 'HTTP %{http_code} in %{time_total}s\n' $URL/api/status"
    pause "Mac 1: start dnsmasq again (./demo.sh dns normal)" 2>&1; flush; run "dig $APP"; } | save "$E/08-backup-dns/failover-$TS.txt" ;;
drill)
  { hdr "Ext F drill"; pause "A teammate breaks exactly one thing, and does not say what" 2>&1; echo; echo "### BROKEN"; ./troubleshoot/diagnose.sh 2>&1 | sed $'s/\e\\[[0-9;]*m//g'
    read -r -p ">> Type the layer, cause and fix you named: " a </dev/tty; echo; echo "Named by the team: $a"; pause "Apply the fix" 2>&1; echo; echo "### FIXED"; ./troubleshoot/diagnose.sh 2>&1 | sed $'s/\e\\[[0-9;]*m//g'; } | save "$E/13-troubleshooting/drill-$TS.txt" ;;
firewall) { hdr "Ext C"; run "pfctl -s info | head -3"; run "pfctl -a com.apple/team1-backend -sr"; } | save "$E/11-service-isolation/pf-rules-$WHO-$TS.txt" ;;
*) sed -n '2,12p' "$0" ;;
esac
