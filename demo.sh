#!/bin/bash
# =====================================================================
#  FINAL PRESENTATION - one script for all 4 Macs (role detected from
#  this Mac's IP vs config.env).  Follows the PDF's 11 demo steps.
#
#   ./demo.sh ready        start everything this Mac needs, reset to the
#                          clean starting state, then run this Mac's tests
#   ./demo.sh check        10-second pre-flight (no sudo) - run right before presenting
#   ./demo.sh logs         this Mac's live log window (keep it on screen)
#   ./demo.sh capture      (Mac 4) fresh clean Wireshark capture of one full request
#   ./demo.sh 1 ... 10     this Mac's part of demo step N
#   ./demo.sh 9a|9b|9c|9e  Phase 2: backup DNS | TTL | firewall | edge cutover
#   ./demo.sh dns standby|normal   (Mac 1 / Mac 4) point app.team1.test at
#                          the standby edge / back to the primary edge
#   ./demo.sh cleanup      after the presentation: undo everything on this Mac
# =====================================================================
cd "$(dirname "$0")" || exit 1
ROOT="$PWD"
# shellcheck disable=SC1091
source "${TEST_CONFIG:-./config.env}"
APP="app.$PROJECT_DOMAIN"; P=""; [ "$HTTPS_PORT" != "443" ] && P=":$HTTPS_PORT"
URL="https://$APP$P"; CA="$ROOT/team1-ca.crt"
LOG="$ROOT/logs"; mkdir -p "$LOG"
PCAP=$(ls -t evidence/05-wireshark/*.pcap* 2>/dev/null | head -1)
TSHARK=$(command -v tshark || ls /Applications/Wireshark.app/Contents/MacOS/tshark 2>/dev/null)
WIRESHARK=$(ls /Applications/Wireshark.app/Contents/MacOS/Wireshark 2>/dev/null)

B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'
title() { echo; echo "${B}${C}=== STEP $1 ===${N}"; }
say()   { echo "${B}$*${N}"; }
tell()  { echo "${Y}  SAY:${N} $*"; }
ok()    { echo "  ${G}OK${N}  $*"; }
bad()   { echo "  ${R}!!${N}  $*"; }
show()  { echo "${D}\$ $*${N}"; }
pause() { echo; read -r -p "${C}>> $1  [Enter]${N} " _ </dev/tty; }
flush() { sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder 2>/dev/null; }
up()    { nc -z -G 2 "$1" "$2" >/dev/null 2>&1; }
pcap_edge() {  # edge IP from the capture's own DNS answer for app.<domain>
  [ -n "$PCAP" ] || return
  if [ -n "$TSHARK" ]; then "$TSHARK" -r "$PCAP" -Y "dns.qry.name==\"$APP\" && dns.a" -T fields -e dns.a 2>/dev/null | head -1 | cut -d, -f1; return; fi
  local id; id=$(tcpdump -nn -r "$PCAP" "udp dst port 53" 2>/dev/null | awk -v n="A? $APP." 'index($0,n){sub(/\+$/,"",$6); print $6; exit}')
  tcpdump -nn -r "$PCAP" "udp src port 53" 2>/dev/null | awk -v id="$id" '{x=$6; sub(/[*+]$/,"",x)} x==id{for(i=7;i<=NF;i++) if($i=="A"){v=$(i+1); sub(/[^0-9.]+$/,"",v); print v; exit}}'
}

IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}'); IFACE=${IFACE:-en0}
MYIP=$(ipconfig getifaddr "$IFACE" 2>/dev/null)
ROLE="${DEMO_ROLE:-}"
if [ -z "$ROLE" ]; then
  for i in 1 2 3 4; do v="MAC${i}_IP"; [ "${!v}" = "$MYIP" ] && ROLE="mac$i"; done
fi
if [ -z "$ROLE" ]; then
  bad "This Mac ($MYIP) is not in config.env."
  echo "     Fix config.env (Mac 1 commits it, everyone git pull), or run with DEMO_ROLE=macN"; exit 1
fi
is_client() { [ "$ROLE" = mac1 ] || [ "$ROLE" = mac4 ]; }
case $ROLE in
  mac1) NAME="Mac 1 - primary DNS + client" ;;
  mac2) NAME="Mac 2 - nginx edge (TLS + load balancer)" ;;
  mac3) NAME="Mac 3 - Backend A + standby edge" ;;
  mac4) NAME="Mac 4 - Backend B + backup DNS + main client" ;;
esac

# ---------------- service helpers ----------------
start_backend() {  # name port
  if up 127.0.0.1 "$2"; then ok "Backend $1 already running on :$2"; return; fi
  nohup env BACKEND_NAME="$1" BACKEND_PORT="$2" python3 -u backend/backend.py >"$LOG/backend-$1.log" 2>&1 &
  sleep 1; up 127.0.0.1 "$2" && ok "Backend $1 started on :$2 (log: logs/backend-$1.log)" || bad "Backend $1 failed - see logs/backend-$1.log"
}
stop_backend() { local p; p=$(lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null); [ -n "$p" ] && kill $p; sleep 0.5; }
dns_start() {  # [target ip]
  local t="${1:-$APP_TARGET_IP}"
  sudo -v || return 1   # refresh sudo now: a password prompt in the background would hang
  sudo pkill -x dnsmasq 2>/dev/null; sleep 0.5
  sudo nohup ./dns/start-dns.sh --target "$t" >"$LOG/dns.log" 2>&1 &
  for _ in 1 2 3 4 5 6 7 8; do sleep 1
    [ "$(dig +short +time=1 +tries=1 @"$MYIP" "$APP" 2>/dev/null | tail -1)" = "$t" ] && { ok "DNS on this Mac answers $APP -> $t (TTL ${DNS_TTL}s)"; return; }
  done; bad "DNS did not come up - see logs/dns.log"
}
edge_ok() { curl -s -m 4 --cacert "$CA" --resolve "$APP:$HTTPS_PORT:$1" -o /dev/null -w '%{http_code}' "$URL/api/status" 2>/dev/null | grep -q 200; }
fw_on()  { sudo ./firewall/backend-firewall.sh apply; }
fw_off() { if [ -f /etc/pf.anchors/team1-backend ]; then sudo ./firewall/backend-firewall.sh remove >/dev/null && ok "firewall removed (clean start for Ext C)"; else ok "firewall off (clean start for Ext C)"; fi; }
client_ready() {
  sudo ./dns/set-client-dns.sh set >/dev/null 2>&1; flush
  ok "client DNS -> $MAC1_IP (primary) + $BACKUP_DNS_IP (backup)"
  local rc; curl -s -m 6 -o /dev/null "$URL/api/status"; rc=$?
  if [ $rc -eq 60 ]; then say "  CA not trusted yet - installing it"; ./client/mac4-client-setup.sh team1-ca.crt >/dev/null && ok "CA trusted"; fi
}

# ---------------- ready / logs / cleanup ----------------
cmd_ready() {
  say "Getting $NAME ready  (IP $MYIP)"
  git fetch -q 2>/dev/null && [ "$(git rev-list --count HEAD..@{u} 2>/dev/null)" != 0 ] && bad "you are behind GitHub - run: git pull  (then ./demo.sh ready again)"
  sudo -v || exit 1
  case $ROLE in
    mac1) dns_start; client_ready ;;
    mac2) ./edge/nginx-script.sh start >/dev/null && edge_ok "$MYIP" && ok "nginx edge serving https://$APP on $MYIP:$HTTPS_PORT" || bad "nginx not serving - run ./edge/nginx-script.sh start" ;;
    mac3) start_backend A "$BACKEND_A_PORT"; fw_off
          if edge_ok "$MYIP"; then ok "standby edge already running"
          elif [ -f "$HOME/cn-phase1/edge/nginx/certs/app.$PROJECT_DOMAIN.key" ]; then ./edge/mac3-standby-edge.sh start >/dev/null 2>&1; edge_ok "$MYIP" && ok "standby edge started (for Ext E)" || bad "standby edge failed: ./edge/mac3-standby-edge.sh start"
          else bad "edge cert not imported (needed for Ext E): Mac 2 ./edge/mac2-export-certs.sh -> AirDrop -> ./edge/mac2-import-certs.sh <tgz>"; fi ;;
    mac4) start_backend B "$BACKEND_B_PORT"; fw_off; dns_start; client_ready
          if [ -z "$PCAP" ]; then bad "no capture yet: ./demo.sh capture"
          elif [ "$(pcap_edge)" != "$MAC2_IP" ]; then bad "capture is from an old network (edge $(pcap_edge)) - recapture: ./demo.sh capture"
          else ok "saved capture matches today's network: $PCAP"; fi ;;
  esac
  echo; say "Self-test:"; is_client && echo "${D}  (Mac 1 and Mac 4: run tests one after the other, not at the same time)${N}"
  ./tests/test-"$ROLE".sh | tail -8
  echo; say "Ready. Keep a second tab open with:  ./demo.sh logs"
}
cmd_logs() {
  case $ROLE in
    mac1) say "Live DNS queries (dnsmasq)  - Ctrl+C to stop"; touch "$LOG/dns.log"; tail -n 5 -f "$LOG/dns.log" | grep --line-buffered -E "query|reply|config|forwarded|cached" ;;
    mac2) say "Live edge log: client ip:port, TLS, request, status, which backend - Ctrl+C to stop"; ./edge/nginx-script.sh logs ;;
    mac3) say "Live Backend A log - Ctrl+C to stop"; touch "$LOG/backend-A.log"; tail -f "$LOG/backend-A.log" ;;
    mac4) say "Live Backend B log + backup DNS queries - Ctrl+C to stop"; touch "$LOG/backend-B.log"
          touch "$LOG/dns.log"; tail -n 5 -f "$LOG/backend-B.log" "$LOG/dns.log" | grep --line-buffered -vE "^$|compile time|started, version" ;;
  esac
}
cmd_cleanup() {
  sudo -v || exit 1
  is_client && { sudo ./dns/set-client-dns.sh restore >/dev/null 2>&1; flush; ok "client DNS back to automatic"; }
  case $ROLE in
    mac1) sudo pkill -x dnsmasq; ok "DNS stopped" ;;
    mac2) ./edge/nginx-script.sh stop ;;
    mac3) fw_off; ./edge/mac3-standby-edge.sh stop >/dev/null 2>&1; ok "standby edge stopped"; stop_backend "$BACKEND_A_PORT"; ok "Backend A stopped" ;;
    mac4) fw_off; sudo pkill -x dnsmasq; ok "backup DNS stopped"; stop_backend "$BACKEND_B_PORT"; ok "Backend B stopped" ;;
  esac
}
cmd_dns() {
  is_client || { bad "only Mac 1 and Mac 4 run DNS"; exit 1; }
  sudo -v || exit 1
  case "${1:-}" in
    standby) dns_start "$STANDBY_EDGE_IP" ;;
    normal)  dns_start "$APP_TARGET_IP" ;;
    stop)    sudo pkill -x dnsmasq; ok "DNS stopped on this Mac" ;;
    *) echo "usage: ./demo.sh dns standby|normal|stop" ;;
  esac
}

cmd_capture() {  # clean capture of ONE full flow, only team traffic (no other apps' noise)
  is_client || { bad "run the capture on a client: Mac 4 (or Mac 1)"; exit 1; }
  sudo -v || exit 1
  mkdir -p evidence/05-wireshark
  local out="evidence/05-wireshark/demo-$(date +%H%M%S).pcap"
  local filt="(udp port 53 and (host $MAC1_IP or host $BACKUP_DNS_IP)) or (tcp port $HTTPS_PORT and host $APP_TARGET_IP)"
  say "Capturing on $IFACE:  $filt"
  sudo tcpdump -i "$IFACE" -s 0 -U -w "$out" "$filt" >/dev/null 2>&1 &
  local tp=$!; sleep 1.5
  flush; sleep 0.5
  echo "  1) TLS 1.2 request (certificate visible in the capture)"
  curl -s -m 8 --tlsv1.2 --tls-max 1.2 -o /dev/null -w "     %{http_code}  TLS1.2  local port %{local_port}\n" "$URL/api/status"
  echo "  2) normal requests (TLS 1.3, HTTP/2) - load balanced"
  for i in 1 2 3; do curl -s -m 8 -D - -o /dev/null "$URL/api/status" | tr -d '\r' | awk '/^HTTP/{s=$2} tolower($1)=="x-backend:"{print "     " s "  X-Backend: " $2}'; done
  curl -s -m 8 -I "$URL/api/cache" >/dev/null
  sleep 1.5; sudo kill -INT $tp 2>/dev/null; wait $tp 2>/dev/null
  sudo chown "$(id -u)" "$out"
  local n; n=$(tcpdump -nn -r "$out" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n" -gt 10 ]; then ok "saved $out ($n packets)"; PCAP="$out"; else bad "capture has only $n packets - is DNS set to Mac 1? (./demo.sh ready)"; fi
  echo "  Show it with:  ./demo.sh 6"
}
cmd_check() {  # quick pre-flight, no sudo, any Mac
  say "Pre-flight from $NAME ($MYIP)"
  local i v
  for i in 1 2 3 4; do v="MAC${i}_IP"; [ "${!v}" = "$MYIP" ] && continue
    ping -c 1 -t 2 "${!v}" >/dev/null 2>&1 && ok "Mac $i ${!v} reachable" || bad "Mac $i ${!v} NOT reachable"; done
  for v in "$MAC1_IP:primary" "$BACKUP_DNS_IP:backup"; do
    [ "$(dig +short +time=2 +tries=1 @"${v%%:*}" "$APP" | tail -1)" = "$APP_TARGET_IP" ] && ok "${v#*:} DNS (${v%%:*}) answers $APP -> $APP_TARGET_IP" || bad "${v#*:} DNS (${v%%:*}) wrong/no answer"; done
  local ec; ec=$(curl -s -m 6 --cacert "$CA" --resolve "$APP:$HTTPS_PORT:$MAC2_IP" -o /dev/null -w '%{http_code}' "$URL/api/status" 2>/dev/null)
  case "$ec" in
    200) ok "primary edge https://$APP on $MAC2_IP OK (cert verified)" ;;
    502|504) bad "edge is up and TLS works, but returns $ec - it cannot reach the backends (Mac 3 / Mac 4 running and on the Wi-Fi?)" ;;
    000) bad "primary edge not answering HTTPS on $MAC2_IP:$HTTPS_PORT (Mac 2: ./demo.sh ready)" ;;
    *) bad "primary edge returned $ec" ;;
  esac
  edge_ok "$STANDBY_EDGE_IP" && ok "standby edge on $STANDBY_EDGE_IP OK" || echo "  ${Y}--${N}  standby edge not running (only needed for 9e)"
  local seq; seq=$(for _ in 1 2 3 4; do curl -s -m 4 --cacert "$CA" --resolve "$APP:$HTTPS_PORT:$MAC2_IP" -D - -o /dev/null "$URL/api/status" | tr -d '\r' | awk 'tolower($1)=="x-backend:"{printf $2}'; done)
  [[ "$seq" == *A* && "$seq" == *B* ]] && ok "load balancing A+B ($seq)" || bad "load balancing only '$seq'"
  if is_client; then
    [ "$(dscacheutil -q host -a name "$APP" | awk '/ip_address/{print $2; exit}')" = "$APP_TARGET_IP" ] && ok "this Mac resolves $APP by name" || bad "this Mac does not resolve $APP -> ./demo.sh ready"
    curl -s -m 5 -o /dev/null "$URL/api/status" && ok "this Mac trusts the certificate (curl, no -k)" || bad "curl by name fails -> ./demo.sh ready"
  fi
  [ "$ROLE" = mac4 ] && { [ "$(pcap_edge)" = "$APP_TARGET_IP" ] && ok "capture matches today's IPs" || bad "capture is old -> ./demo.sh capture"; }
}

# ---------------- the 11 steps ----------------
client_only() { is_client || { echo "  This step is presented from ${B}Mac 4${N} (client). $1"; return 1; }; }

step1() { title "1 - Topology and IP / service inventory"
  printf "  ${B}%-6s %-40s %-16s %s${N}\n" Mac Role IP "Service : port"
  printf "  %-6s %-40s %-16s %s\n" "Mac 1" "Primary DNS (dnsmasq) + test client" "$MAC1_IP" "UDP 53" \
    "Mac 2" "Edge: nginx TLS termination + LB" "$MAC2_IP" "TCP 443" \
    "Mac 3" "Backend A + standby edge (Ext E)" "$MAC3_IP" "TCP 3001 (+443 standby)" \
    "Mac 4" "Backend B + backup DNS + test client" "$MAC4_IP" "TCP 3002, UDP 53"
  echo; echo "  DNS records: $APP, api.$PROJECT_DOMAIN -> $APP_TARGET_IP  (TTL ${DNS_TTL}s)"
  echo "  Flow: client -> DNS (Mac 1, backup Mac 4) -> HTTPS to Mac 2 (nginx) -> Backend A (Mac 3) or B (Mac 4)"
  echo "  Cloud: DNS = Route 53 | nginx = AWS ALB | backends = EC2 target group | firewall = security group"
  echo; ok "this Mac: $NAME"
  [ "$ROLE" = mac1 ] && { open docs/architecture.md 2>/dev/null; tell "Point at the diagram: clients only ever talk to Mac 2; DNS just gives them Mac 2's IP."; }
}
step2() { title "2 - All machines on the private LAN"
  show "ipconfig getifaddr $IFACE"; echo "  this Mac ($ROLE): $MYIP   mask $(ipconfig getoption "$IFACE" subnet_mask)   gateway $(route -n get default | awk '/gateway:/{print $2}')"
  for i in 1 2 3 4; do v="MAC${i}_IP"; [ "${!v}" = "$MYIP" ] && continue
    show "ping -c 3 ${!v}"; ping -c 3 -t 4 "${!v}" | tail -2 | sed 's/^/  /'; done
  tell "Same subnet, same gateway, every Mac answers ICMP - layer 3 works before any service."
}
step3() { title "3 - Resolve the private name from a client"
  client_only "Mac 1: keep './demo.sh logs' visible - the query appears live." || return
  flush; show "dig $APP"
  dig "$APP" | grep -E "status:|^$APP|SERVER:|Query time" | sed 's/^/  /'
  tell "Answer is Mac 2's IP ($APP_TARGET_IP), from OUR server on UDP 53 (SERVER line), TTL ${DNS_TTL}s."
  tell "DNS only finds the address - no connection to the app exists yet."
}
step4() { title "4 - HTTPS by name, no certificate warnings"
  if [ "$ROLE" = mac2 ]; then
    show "openssl x509 -in <edge cert> -noout -subject -issuer -ext subjectAltName -dates"
    openssl x509 -in "$HOME/cn-phase1/edge/nginx/certs/app.$PROJECT_DOMAIN.crt" -noout -subject -issuer -ext subjectAltName -dates | sed 's/^/  /'
    tell "Cert for app/api.team1.test, signed by our Team1 Local CA. TLS ends HERE; nginx -> backends is plain HTTP."
    tell "Handshake: ClientHello (SNI) -> ServerHello -> Certificate -> key exchange -> Finished."; return; fi
  client_only "" || return
  show "curl -v $URL/api/status"
  curl -sv "$URL/api/status" 2>&1 | grep -E "Connected to|SSL connection|ALPN: server|subject:|issuer:|verify ok|^< HTTP|^< x-backend|^< x-edge|^\{" | sed 's/^/  /'
  open -a Safari "$URL" 2>/dev/null
  tell "No -k: the certificate is verified against our CA, installed in this Mac's trust store. Safari shows the padlock, no IP in the URL."
}
step5() { title "5 - Load balancing across both backends"
  client_only "Mac 2: './demo.sh logs' shows upstream= alternating." || return
  show "for i in \$(seq 8); do curl -s -D - -o /dev/null $URL/api/status | grep -i x-backend; done"
  for i in 1 2 3 4 5 6 7 8; do curl -s -m 5 -D - -o /dev/null "$URL/api/status" | tr -d '\r' | awk -v i=$i '
    tolower($1)=="x-backend:"{b=$2} tolower($1)=="x-upstream:"{u=$2} END{printf "  request %d -> X-Backend: %s   (upstream %s)\n", i, b, u}'; done
  tell "Round-robin: one name, one IP, two servers. The client never learns the backend IPs."
}
step6() { title "6 - Wireshark: DNS, TCP and TLS"
  [ -n "$PCAP" ] || { bad "no capture yet - run on Mac 4:  ./demo.sh capture"; return; }
  say "  Capture: $PCAP"
  local edge; edge=$(pcap_edge)
  if [ -z "$TSHARK" ]; then step6_tcpdump "$edge"; return; fi
  local s1 s2 cs
  s1=$("$TSHARK" -r "$PCAP" -Y "tcp.flags.syn==1 && tcp.flags.ack==0 && ip.dst==$edge && tcp.dstport==$HTTPS_PORT" -T fields -e tcp.stream 2>/dev/null | head -1)
  s2=$("$TSHARK" -r "$PCAP" -Y "tcp.flags.syn==1 && tcp.flags.ack==0 && ip.dst==$edge && tcp.dstport==$HTTPS_PORT" -T fields -e tcp.stream 2>/dev/null | sed -n 2p)
  echo; say "  [1] DNS - Application layer over UDP 53 (client ephemeral port -> Mac 1:53)"
  "$TSHARK" -r "$PCAP" -Y "dns.qry.name==\"$APP\" && dns.qry.type==1" 2>/dev/null | head -2 | sed 's/^/    /'
  tell "Query from the client's random port to our DNS on 53/UDP; the response carries the edge IP $edge (TTL ${DNS_TTL}s)."
  pause "Next: TCP three-way handshake"
  say "  [2] TCP handshake - Transport layer (client port -> $edge:$HTTPS_PORT), connection $s1"
  "$TSHARK" -r "$PCAP" -Y "tcp.stream==$s1" 2>/dev/null | head -3 | sed 's/^/    /'
  tell "SYN (client ISN, relative Seq=0) -> SYN-ACK (server ISN, Ack=1) -> ACK. Only now can any data flow. Socket pair = client IP:port <-> $edge:$HTTPS_PORT."
  pause "Next: TLS handshake (TLS 1.2 connection, so the certificate is visible)"
  say "  [3] TLS handshake on the same connection"
  "$TSHARK" -r "$PCAP" -Y "tcp.stream==$s1 && (tls.handshake || tls.change_cipher_spec)" 2>/dev/null | head -6 | sed 's/^/    /'
  cs=$("$TSHARK" -r "$PCAP" -Y "tcp.stream==$s1 && tls.handshake.type==11" -T fields -E separator='|' -e x509sat.uTF8String -e x509af.utcTime -e x509ce.dNSName -e x509sat.printableString 2>/dev/null | head -1)
  [ -n "$cs" ] && echo "    Certificate sent by the edge:  subject/issuer names: $(echo "$cs" | cut -d'|' -f1,4 | tr '|' ' ')" && echo "                                   valid: $(echo "$cs" | cut -d'|' -f2)   SAN: $(echo "$cs" | cut -d'|' -f3)"
  tell "ClientHello carries SNI=$APP -> ServerHello picks version/cipher -> Certificate (signed by Team1 Local CA) -> key exchange (ECDHE) -> ChangeCipherSpec + Finished. From here on everything is encrypted."
  if [ -n "$s2" ]; then
    pause "Next: the same thing with TLS 1.3 (what browsers use)"
    say "  [4] TLS 1.3 connection $s2 - the Certificate is now encrypted"
    "$TSHARK" -r "$PCAP" -Y "tcp.stream==$s2 && tls" 2>/dev/null | head -3 | sed 's/^/    /'
    tell "In TLS 1.3 everything after ServerHello is encrypted, including the certificate, and the handshake is 1 round trip instead of 2."
  fi
  pause "Next: the HTTP request itself"
  say "  [5] HTTP - Application Data (record type 23): encrypted"
  "$TSHARK" -r "$PCAP" -Y "tcp.stream==$s1 && tls.record.content_type==23" 2>/dev/null | head -3 | sed 's/^/    /'
  tell "The GET /api/status and its X-Backend header are inside these records - unreadable on the wire. That's why we read headers with curl -v at the endpoint."
  local f="dns.qry.name contains \"$PROJECT_DOMAIN\" || tcp.stream==$s1${s2:+ || tcp.stream==$s2}"
  echo; say "  Opening Wireshark with filter:  $f"
  if [ -n "$WIRESHARK" ]; then nohup "$WIRESHARK" -r "$PCAP" -Y "$f" >/dev/null 2>&1 & fi
  echo "  In Wireshark: click a packet -> middle pane shows the layers: Frame / Ethernet II (MAC) / IPv4 / TCP or UDP / TLS or DNS."
  echo "  Filters to type:  dns   |   tcp.flags.syn==1   |   tls.handshake   |   tls.handshake.type==11   |   tls.record.content_type==23"
  echo "  Statistics > Flow Graph shows the whole ladder diagram."
}
step6_tcpdump() {  # fallback when tshark is not installed
  local edge=$1 sport
  echo "  -- DNS (client -> 53/UDP):"; tcpdump -nn -r "$PCAP" "udp port 53" 2>/dev/null | grep "$APP" | head -2 | sed 's/^/     /'
  sport=$(tcpdump -nn -r "$PCAP" "dst host $edge and dst port $HTTPS_PORT and tcp[tcpflags] & tcp-syn != 0" 2>/dev/null | head -1 | awk '{split($3,a,"."); print a[5]}')
  echo "  -- TCP handshake + TLS (port $sport -> $edge:$HTTPS_PORT):"
  tcpdump -nn -r "$PCAP" "host $edge and port $sport" 2>/dev/null | head -6 | sed 's/^/     /'
  [ -n "$WIRESHARK" ] && nohup "$WIRESHARK" -r "$PCAP" >/dev/null 2>&1 &
  echo "  Filters: dns | tcp.flags.syn==1 | tls.handshake | tls.record.content_type==23"
}
step7() { title "7 - HTTP headers and caching (304)"
  client_only "Mac 3 explains: /api/cache has the same ETag on A and B." || return
  show "curl -I $URL/api/cache"
  local h etag; h=$(curl -s -I "$URL/api/cache" | tr -d '\r'); echo "$h" | sed 's/^/  /'
  etag=$(echo "$h" | awk -F': ' 'tolower($1)=="etag"{print $2}')
  pause "Now a conditional request with that ETag"
  show "curl -I -H 'If-None-Match: $etag' $URL/api/cache"
  curl -s -I -H "If-None-Match: $etag" "$URL/api/cache" | tr -d '\r' | sed 's/^/  /'
  tell "Fresh hit: within max-age=60 the browser does not ask at all. Conditional: If-None-Match -> 304, headers only, no body. Full: 200 + body."
}
step8() { title "8 - Fail Backend A, service continues"
  case $ROLE in
    mac4) say "  Live requests every second. Mac 3 will stop Backend A. Ctrl+C here when done."; ./edge/mac2-ha-demo.sh watch ;;
    mac3) pause "Stop Backend A now? (Mac 4 should be running './demo.sh 8' first)"
          stop_backend "$BACKEND_A_PORT"; up 127.0.0.1 "$BACKEND_A_PORT" && bad "still running" || ok "Backend A STOPPED"
          tell "Requests keep succeeding via B: nginx got 'connection refused', retried on B, and benched A for 10 s."
          pause "Restart Backend A?"; start_backend A "$BACKEND_A_PORT"
          tell "After its 10 s fail_timeout nginx tries A again - load balancing resumes, no config change." ;;
    mac2) echo "  Watch './demo.sh logs': upstream= shows only Mac 4 while A is down."
          tell "Passive health check: max_fails=1 fail_timeout=10s + proxy_next_upstream. Remaining single point of failure: this edge." ;;
    *) echo "  Mac 3 stops Backend A, Mac 4 shows requests still succeeding." ;;
  esac
}
step9() { title "9 - Phase 2: DNS and resilience"
  echo "  9a  backup DNS failover (Ext A)    Mac 1 + Mac 4"
  echo "  9b  TTL and caching (Ext B)        Mac 4 runs it, Mac 1 + Mac 4 switch DNS"
  echo "  9c  backend firewall (Ext C)       Mac 3 + Mac 4 apply, Mac 1 + Mac 2 verify"
  echo "  9e  edge cutover (Ext E)           Mac 4 watches, Mac 1 + Mac 4 switch DNS"
  echo "  (Ext D failover was step 8)    Run: ./demo.sh 9a  etc."
}
step9a() { title "9a - Backup DNS failover (Ext A)"
  case $ROLE in
    mac1) pause "Stop the PRIMARY DNS on this Mac?"; sudo pkill -x dnsmasq; ok "primary DNS stopped"
          tell "Name resolution is a separate service from the app: clients now need the backup."
          pause "Restart the primary DNS?"; dns_start ;;
    mac4) pause "Run AFTER Mac 1 has stopped its DNS"; flush
          show "dig +time=2 +tries=1 $APP"; dig +time=2 +tries=1 "$APP" | grep -E "status:|^$APP|SERVER:" | sed 's/^/  /'
          show "curl -s $URL/api/status"; curl -s -m 8 "$URL/api/status" | sed 's/^/  /'; echo
          tell "SERVER is now Mac 4 ($BACKUP_DNS_IP): the backup has identical records, so the service keeps working."
          tell "DNS failure = names stop resolving. App failure = names resolve but the service is down." ;;
    *) echo "  Mac 1 stops its DNS, Mac 4 shows the backup answering." ;;
  esac
}
step9b() { title "9b - TTL and caching (Ext B)"
  case $ROLE in
    mac4) echo "  When the script asks you to change the record, in another tab on THIS Mac run:  ${B}./demo.sh dns standby${N}"
          echo "  and on Mac 1:  ${B}./demo.sh dns standby${N}.   Afterwards both run:  ${B}./demo.sh dns normal${N}"
          pause "Start the TTL demo"; ./dns/ttl-demo.sh ;;
    mac1) echo "  When Mac 4 asks: ${B}./demo.sh dns standby${N}   ... at the end: ${B}./demo.sh dns normal${N}" ;;
    *) echo "  Mac 4 runs the TTL demo; Mac 1 and Mac 4 switch DNS records." ;;
  esac
}
step9c() { title "9c - Backend isolation with pf firewall (Ext C)"
  direct() { for t in "3:$MAC3_IP:$BACKEND_A_PORT" "4:$MAC4_IP:$BACKEND_B_PORT"; do IFS=: read -r m ip port <<< "$t"
      [ "$ip" = "$MYIP" ] && continue; show "curl -m 4 http://$ip:$port/api/status"
      if curl -s -m 4 -o /dev/null "http://$ip:$port/api/status"; then echo "  Mac $m:$port -> ${G}REACHABLE${N}"; else echo "  Mac $m:$port -> ${R}BLOCKED (timeout)${N}"; fi; done; }
  case $ROLE in
    mac3|mac4) pause "Apply the firewall on this Mac? (Mac 1 shows 'before' first)"; fw_on
          tell "Only the edges ($MAC2_IP and standby $STANDBY_EDGE_IP) may reach this backend port; everyone else is silently dropped."
          echo "  Remove later with ./demo.sh cleanup (or: sudo ./firewall/backend-firewall.sh remove)" ;;
    mac1) say "  BEFORE (firewall off):"; direct
          pause "Mac 3 and Mac 4 apply their firewall now, then press Enter"
          say "  AFTER:"; direct
          show "curl -s -o /dev/null -w '%{http_code}' $URL/api/status"; echo "  through the edge -> $(curl -s -m 6 -o /dev/null -w '%{http_code}' "$URL/api/status")"
          tell "Clients can no longer bypass the edge, but the site still works through it - like a security group that only allows the ALB." ;;
    mac2) say "  The edge is still allowed:"; for t in "$MAC3_IP:$BACKEND_A_PORT" "$MAC4_IP:$BACKEND_B_PORT"; do
            show "curl http://$t/api/status"; curl -s -m 4 "http://$t/api/status" | sed 's/^/  /'; echo; done ;;
  esac
}
step9e() { title "9e - DNS-based edge cutover (Ext E)"
  case $ROLE in
    mac4) echo "  Leave this running. In ANOTHER tab on this Mac: ${B}./demo.sh dns standby${N}  (Mac 1 does the same)."
          echo "  Watch X-EDGE stay mac2-primary until the ${DNS_TTL}s TTL expires, then flip to mac3-standby."
          echo "  To restore, both run: ${B}./demo.sh dns normal${N}.   Ctrl+C here when done."; pause "Start watching"; ./edge/mac2-edge-watch.sh ;;
    mac1) echo "  When Mac 4 is watching:  ${B}./demo.sh dns standby${N}   ...then later:  ${B}./demo.sh dns normal${N}"
          tell "The DNS server changes instantly, but clients keep the cached answer for up to ${DNS_TTL}s. Keep the old edge running for one TTL - that's why you lower TTL before a migration." ;;
    mac3) edge_ok "$MYIP" && ok "standby edge on this Mac is serving (X-Edge: mac3-standby)" || bad "standby not running: ./edge/mac3-standby-edge.sh start" ;;
    mac2) tell "Both edges serve during the switch, so no request fails. Faster failover would need a floating IP (VRRP) or a managed LB." ;;
  esac
}
step10() { title "10 - Diagnose the injected fault"
  echo "  Order: DNS -> IP -> TCP -> TLS -> HTTP. Say each layer out loud."
  case $ROLE in
    mac4|mac1) ./troubleshoot/diagnose.sh ;;
    mac2) edge_ok "$MYIP" && ok "nginx is serving HTTPS on $MYIP:$HTTPS_PORT" || bad "nginx NOT serving: ./edge/nginx-script.sh start"
          show "tail -5 error.log"; tail -5 "$HOME/cn-phase1/edge/nginx/logs/error.log" | sed 's/^/  /'
          for t in "$MAC3_IP:$BACKEND_A_PORT" "$MAC4_IP:$BACKEND_B_PORT"; do up "${t%:*}" "${t#*:}" && ok "backend $t reachable" || bad "backend $t NOT reachable"; done ;;
    mac3) up 127.0.0.1 "$BACKEND_A_PORT" && ok "Backend A running" || bad "Backend A down: ./demo.sh ready"
          [ -f /etc/pf.anchors/team1-backend ] && echo "  firewall is ON - check it allows $MAC2_IP: sudo ./firewall/backend-firewall.sh status" ;;
  esac
  echo "  Runbook: troubleshoot/RUNBOOK.md"
}

case "${1:-}" in
  ready) cmd_ready ;; logs) cmd_logs ;; cleanup) cmd_cleanup ;; dns) cmd_dns "${2:-}" ;;
  capture) cmd_capture ;; check) cmd_check ;;
  1|2|3|4|5|6|7|8|9|10) "step$1" ;; 9a|9b|9c|9e) "step$1" ;;
  11) title "11 - Individual viva"; echo "  Answer from understanding. Revise: docs/edge-failover-and-cutover.md, troubleshoot/RUNBOOK.md, docs/phase2-report.md" ;;
  *) sed -n '2,17p' "$0"; echo; echo "  This Mac: $NAME ($MYIP)" ;;
esac
