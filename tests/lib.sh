#!/bin/bash
# Shared helpers for tests/test-macN.sh  (do not run directly)
# Every check prints PASS / FAIL / WARN, and the whole run is saved to
# evidence/test-results/<mac>-<time>.txt
#   FAIL = something in the PDF does not work  -> must be fixed
#   WARN = optional / not started yet (e.g. firewall not applied right now)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# shellcheck disable=SC1091
source "${TEST_CONFIG:-$ROOT/config.env}"
DOMAIN="$PROJECT_DOMAIN"; APP="app.$DOMAIN"; API="api.$DOMAIN"
P=""; [ "$HTTPS_PORT" != "443" ] && P=":$HTTPS_PORT"
URL="https://$APP$P"
CA="$ROOT/team1-ca.crt"
EXPECTED_TARGET="${APP_TARGET_IP:-$MAC2_IP}"
# TEST_* variables exist only for rehearsing on one laptop. Leave them unset.
DIG_SRV="${TEST_DIG_SERVER:-}"            # e.g. "@127.0.0.1 -p 5300"
CURL_X=(); [ -n "${TEST_CURL_EXTRA:-}" ] && read -r -a CURL_X <<< "$TEST_CURL_EXTRA"
DNS1="${TEST_DNS1:-@$MAC1_IP}"; DNS4="${TEST_DNS4:-@$BACKUP_DNS_IP}"   # "@ip" or "@ip -p port"

G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
NP=0; NF=0; NW=0; FAILED=()
pass() { echo "  ${G}PASS${N}  $1"; NP=$((NP+1)); }
fail() { echo "  ${R}FAIL${N}  $1"; [ -n "${2:-}" ] && echo "        ${D}fix: $2${N}"; NF=$((NF+1)); FAILED+=("$1"); }
warn() { echo "  ${Y}WARN${N}  $1"; [ -n "${2:-}" ] && echo "        ${D}$2${N}"; NW=$((NW+1)); }
info() { echo "        ${D}$1${N}"; }
section() { echo; echo "${B}== $1 ==${N}"; }

start_log() {  # $1 = mac name
  mkdir -p "$ROOT/evidence/test-results"
  LOGFILE="$ROOT/evidence/test-results/$1-$(date +%Y%m%d-%H%M%S).txt"
  exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' > "$LOGFILE")) 2>&1
  echo "${B}TEAM 1 - $1 test run   $(date)${N}"
  echo "domain $DOMAIN | Mac1 $MAC1_IP | Mac2 $MAC2_IP | Mac3 $MAC3_IP | Mac4 $MAC4_IP | target $EXPECTED_TARGET"
}

summary() {
  echo; echo "${B}================ SUMMARY ================${N}"
  echo "  ${G}$NP passed${N}   ${R}$NF failed${N}   ${Y}$NW warnings${N}"
  if [ "$NF" -gt 0 ]; then echo "  Failed:"; for f in "${FAILED[@]}"; do echo "   - $f"; done; fi
  [ "$NF" -eq 0 ] && echo "  ${G}${B}ALL REQUIRED CHECKS PASSED${N}"
  echo "  (saved to ${LOGFILE#"$ROOT"/})"
  sleep 0.3; [ "$NF" -eq 0 ]
}

IFACE=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}'); IFACE=${IFACE:-en0}
MYIP=$(ipconfig getifaddr "$IFACE" 2>/dev/null)
WIFI=$(networksetup -listnetworkserviceorder 2>/dev/null | awk -v d="Device: $IFACE)" \
  '/^\([0-9]+\)/{n=$0; sub(/^\([0-9]+\) /,"",n)} index($0,d){print n; exit}'); WIFI=${WIFI:-Wi-Fi}

c()        { curl -s --max-time 5 "${CURL_X[@]}" "$@"; }                 # trust store of this Mac
code()     { c -o /dev/null -w '%{http_code}' "$@" 2>/dev/null; }
hdr()      { c -o /dev/null -D - "${@:2}" 2>/dev/null | tr -d '\r' | awk -v h="$(echo "$1" | tr A-Z a-z)" -F': ' 'tolower($1)==h{print $2; exit}'; }
digq()     { dig +short +time=2 +tries=1 $DIG_SRV "$@" 2>/dev/null | grep -E '^[0-9.]+$' | tail -1; }
reach_tcp(){ nc -z -G 3 "$1" "$2" >/dev/null 2>&1; }

check_role() {  # $1 = expected IP for this role
  if [ "$MYIP" = "$1" ] || [ -n "${TEST_SKIP_IP:-}" ]; then pass "this Mac's IP $MYIP matches config.env"
  else fail "this Mac is $MYIP but config.env says $1" "fix config.env (Mac 1 commits it), everyone git pull"; fi
}

# ---------------- Task A: LAN ----------------
net_tests() {
  section "Task A - private LAN"
  local mask gw mac; mask=$(ipconfig getoption "$IFACE" subnet_mask 2>/dev/null)
  gw=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}'); mac=$(ifconfig "$IFACE" 2>/dev/null | awk '/ether/{print $2}')
  info "interface $IFACE | IPv4 $MYIP | mask $mask | gateway $gw | MAC $mac"
  [ -n "$MYIP" ] && pass "has a private IPv4 address on $IFACE" || fail "no IPv4 address on $IFACE" "join the team Wi-Fi"
  for i in 1 2 3 4; do local v="MAC${i}_IP"; local ip="${!v}"
    [ "$ip" = "$MYIP" ] && continue
    if ping -c 2 -t 3 -q "$ip" >/dev/null 2>&1; then pass "ping Mac $i ($ip)"
    else fail "ping Mac $i ($ip)" "same Wi-Fi? hotspot client isolation? Firewall stealth mode off?"; fi
  done
}

# ---------------- Task C + F: one backend ----------------
backend_tests() {  # $1 = A|B  $2 = port
  local name=$1 port=$2 base="http://127.0.0.1:$2"
  section "Task C/F - Backend $name on port $port"
  if ! reach_tcp 127.0.0.1 "$port"; then
    fail "Backend $name is not running on port $port" "BACKEND_NAME=$name BACKEND_PORT=$port python3 backend/backend.py"; return; fi
  pass "Backend $name is listening on $port"
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | grep -q "127.0.0.1:$port"; then
    fail "bound to 127.0.0.1 only - other Macs cannot reach it" "bind 0.0.0.0"
  else pass "bound to all interfaces (0.0.0.0), reachable on the LAN"; fi
  [ "$(curl -s --max-time 4 -o /dev/null -w '%{http_code}' "$base/")" = 200 ] && pass "GET / -> 200" || fail "GET / does not return 200"
  local body; body=$(curl -s --max-time 4 "$base/api/status")
  echo "$body" | grep -q "\"backend\": *\"$name\"" && echo "$body" | grep -q '"status": *"ok"' \
    && pass "GET /api/status -> {\"backend\": \"$name\", \"status\": \"ok\"}" || fail "/api/status body wrong: $body"
  local h; h=$(curl -s --max-time 4 -D - -o /dev/null "$base/api/status" | tr -d '\r')
  echo "$h" | grep -qi "^x-backend: $name" && pass "header X-Backend: $name" || fail "missing header X-Backend: $name"
  echo "$h" | grep -qi "^cache-control: no-store" && pass "/api/status is Cache-Control: no-store (LB stays visible)" || warn "/api/status is not no-store"
  local ch etag; ch=$(curl -s --max-time 4 -I "$base/api/cache" | tr -d '\r')
  etag=$(echo "$ch" | awk -F': ' 'tolower($1)=="etag"{print $2}')
  echo "$ch" | head -1 | grep -q " 200" && pass "HEAD /api/cache works (curl -I)" || fail "HEAD /api/cache fails" "backend needs do_HEAD"
  echo "$ch" | grep -qi "^cache-control: .*max-age" && pass "/api/cache has Cache-Control max-age" || fail "/api/cache has no Cache-Control max-age"
  [ -n "$etag" ] && pass "/api/cache has ETag $etag" || fail "/api/cache has no ETag"
  [ "$(curl -s --max-time 4 -o /dev/null -w '%{http_code}' -H "If-None-Match: $etag" "$base/api/cache")" = 304 ] \
    && pass "conditional request (If-None-Match) -> 304 Not Modified" || fail "conditional request does not return 304"
  BACKEND_ETAG="$etag"
}

# ---------------- client side: DNS, HTTPS, LB, cache, failures, Phase 2 ----------------
client_tests() {
  section "Task B - DNS from this client"
  local dns; dns=$(networksetup -getdnsservers "$WIFI" 2>/dev/null | tr '\n' ' ')
  info "DNS servers on $WIFI: $dns"
  if [ -z "$DIG_SRV" ]; then
    [[ "$dns" == *"$MAC1_IP"* ]] && pass "client uses Mac 1 ($MAC1_IP) as DNS" || fail "client DNS is not Mac 1" "sudo ./dns/set-client-dns.sh set"
    [[ "$dns" == *"$BACKUP_DNS_IP"* ]] && pass "backup DNS ($BACKUP_DNS_IP) also listed (Ext A)" || fail "backup DNS $BACKUP_DNS_IP not listed" "sudo ./dns/set-client-dns.sh set"
  fi
  local full ans srv; full=$(dig +time=2 +tries=1 $DIG_SRV "$APP" 2>/dev/null)
  ans=$(echo "$full" | awk -v n="$APP." '$1==n && $4=="A"{print $5; exit}'); srv=$(echo "$full" | awk '/SERVER:/{print $3}')
  [ "$ans" = "$EXPECTED_TARGET" ] && pass "dig $APP -> $ans (edge)  [server $srv]" || fail "dig $APP -> '${ans:-no answer}' (expected $EXPECTED_TARGET)" "is dnsmasq running on Mac 1 / Mac 4?"
  [ "$(digq "$API")" = "$EXPECTED_TARGET" ] && pass "dig $API -> $EXPECTED_TARGET" || fail "dig $API wrong"
  local nx; nx=$(dig +time=2 +tries=1 $DIG_SRV "nope-$RANDOM.$DOMAIN" 2>/dev/null | awk '/status:/{print $6}' | tr -d ,)
  [ "$nx" = NXDOMAIN ] && pass "unknown name in $DOMAIN -> NXDOMAIN" || warn "unknown .test name gave '$nx' (expected NXDOMAIN)"
  [ -n "$(digq google.com)" ] && pass "internet names still resolve (google.com forwarded)" || warn "google.com does not resolve via team DNS" "check server= upstream in dnsmasq"
  if [ -z "$DIG_SRV" ]; then
    local os; os=$(dscacheutil -q host -a name "$APP" 2>/dev/null | awk '/ip_address/{print $2; exit}')
    [ "$os" = "$EXPECTED_TARGET" ] && pass "macOS resolver (used by curl/Safari) -> $os" || fail "macOS resolver gives '${os:-nothing}'" "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
  fi

  section "Ext A/B - both DNS servers"
  local a1 a4 t1 t4
  a1=$(dig +short +time=2 +tries=1 $DNS1 "$APP" | grep -E '^[0-9.]+$' | tail -1); a4=$(dig +short +time=2 +tries=1 $DNS4 "$APP" | grep -E '^[0-9.]+$' | tail -1)
  t1=$(dig +noall +answer +time=2 +tries=1 $DNS1 "$APP" | awk '$4=="A"{print $2; exit}'); t4=$(dig +noall +answer +time=2 +tries=1 $DNS4 "$APP" | awk '$4=="A"{print $2; exit}')
  [ "$a1" = "$EXPECTED_TARGET" ] && pass "primary DNS Mac 1 answers $a1" || fail "primary DNS Mac 1 answers '${a1:-nothing}'" "Mac 1: sudo ./dns/start-dns.sh"
  [ "$a4" = "$EXPECTED_TARGET" ] && pass "backup DNS Mac 4 answers $a4 (same record -> failover works)" || fail "backup DNS Mac 4 answers '${a4:-nothing}'" "Mac 4: sudo ./dns/mac4-backup-dns.sh"
  [ "$t1" = "$DNS_TTL" ] && [ "$t4" = "$DNS_TTL" ] && pass "TTL is ${DNS_TTL}s on both servers (Ext B)" || fail "TTL primary=${t1:-none} backup=${t4:-none} (expected $DNS_TTL)"

  section "Task E - HTTPS by name, certificate validated (no -k)"
  local out rc; out=$(c -v "$URL/api/status" 2>&1); rc=$?
  if [ $rc -eq 0 ] && echo "$out" | grep -qE "^< HTTP/[0-9.]+ 200"; then pass "curl $URL/api/status -> 200, certificate verify ok"
  elif [ $rc -eq 60 ]; then fail "certificate not trusted by this Mac's curl" "./client/mac4-client-setup.sh team1-ca.crt"
  else fail "HTTPS request failed (curl exit $rc)" "./troubleshoot/diagnose.sh"; fi
  echo "$out" | grep -E "subject:|issuer:" | sed 's/^\*/       /'
  [ "$(code "https://$API$P/api/status")" = 200 ] && pass "https://$API also valid (SAN covers api)" || fail "https://$API fails"
  [ "$(c -o /dev/null -w '%{http_version}' --http2 "$URL/")" = 2 ] && pass "HTTP/2 negotiated (ALPN)" || warn "HTTP/2 not negotiated"
  [ "$(c -o /dev/null -w '%{http_version}' --http1.1 "$URL/")" = 1.1 ] && pass "HTTP/1.1 also works" || fail "HTTP/1.1 fails"
  local tls12; tls12=$(c -o /dev/null -w '%{http_code}' --tlsv1.2 --tls-max 1.2 "$URL/" 2>/dev/null)
  [ "$tls12" = 200 ] && pass "TLS 1.2 handshake works (Certificate visible in Wireshark)" || warn "forced TLS 1.2 failed"
  local edge; edge=$(hdr X-Edge "$URL/api/status")
  [ -n "$edge" ] && pass "served by edge: X-Edge: $edge" || warn "no X-Edge header" "Mac 2: git pull && ./edge/nginx-script.sh start"

  section "Task D - load balancing through the edge"
  local seq="" a=0 b=0 x round
  # Round-robin is shared by ALL clients: if another Mac is testing at the same moment it can
  # take every other turn, so retry (with a pause) before calling it a failure.
  for round in 1 2 3; do
    for _ in 1 2 3 4 5 6 7 8; do x=$(hdr X-Backend "$URL/api/status"); seq="$seq ${x:--}"
      [ "$x" = A ] && a=$((a+1)); [ "$x" = B ] && b=$((b+1)); done
    [ $a -gt 0 ] && [ $b -gt 0 ] && break
    [ $((a+b)) -eq 0 ] && break; sleep $((round * 2))
  done
  info "X-Backend sequence:$seq"
  [ $a -gt 0 ] && [ $b -gt 0 ] && pass "both backends serve traffic (A=$a B=$b)" || fail "only A=$a B=$b answered" "is the other backend running?"

  section "Task F - HTTP caching through the edge"
  local ch etag n304=0; ch=$(c -I "$URL/api/cache" | tr -d '\r')
  echo "$ch" | grep -iE "^(cache-control|etag|x-backend):" | sed 's/^/        /'
  etag=$(echo "$ch" | awk -F': ' 'tolower($1)=="etag"{print $2}')
  echo "$ch" | grep -qi "^cache-control: .*max-age" && pass "Cache-Control max-age present" || fail "no Cache-Control on /api/cache"
  for _ in 1 2 3 4; do [ "$(code -H "If-None-Match: $etag" "$URL/api/cache")" = 304 ] && n304=$((n304+1)); done
  [ $n304 -eq 4 ] && pass "4/4 conditional requests -> 304 (works on A and B)" || fail "only $n304/4 conditional requests returned 304" "ETag must be identical on both backends"
  [ "$(hdr Cache-Control "$URL/api/status")" = no-store ] && pass "/api/status no-store (never cached)" || warn "/api/status is cacheable"

  section "Section 6.3 - failure behaviour (simulated, nothing is stopped)"
  [ -z "$(dig +short +time=2 +tries=1 @8.8.8.8 "$APP" | grep -E '^[0-9.]+$')" ] && ping -c 1 -t 2 "$EXPECTED_TARGET" >/dev/null 2>&1 \
    && pass "wrong DNS server (8.8.8.8): name fails, but ping to the edge IP works" || warn "wrong-DNS simulation inconclusive"
  local wrong="$MAC1_IP"; c --resolve "$APP:${HTTPS_PORT}:$wrong" -o /dev/null "$URL/" 2>/dev/null; rc=$?
  [ $rc -eq 7 ] || [ $rc -eq 28 ] && pass "DNS pointing to wrong IP ($wrong): connection refused (DNS is only a directory)" || warn "wrong-IP simulation gave curl exit $rc"
  local wp=8443; [ "$HTTPS_PORT" = 8443 ] && wp=9443
  c -o /dev/null "https://$APP:$wp/" 2>/dev/null; rc=$?
  [ $rc -eq 7 ] && pass "wrong port $wp: host up, TCP refused (port = service)" || warn "wrong-port test gave curl exit $rc"
  info "one-backend-down and both-down (502) are tested on Mac 2 with a private test edge"

  section "Ext C - backends not reachable directly from a client"
  local tgt port ipv
  for tgt in "3:$BACKEND_A_PORT" "4:$BACKEND_B_PORT"; do
    ipv="MAC${tgt%%:*}_IP"; port="${tgt#*:}"
    [ "${!ipv}" = "$MYIP" ] && continue   # own port goes over loopback, which pf skips
    if reach_tcp "${!ipv}" "$port"; then warn "Mac ${tgt%%:*}:$port is reachable directly - firewall not applied" "Mac ${tgt%%:*}: sudo ./firewall/backend-firewall.sh apply  (WARN is expected before Ext C)"
    else pass "direct access to Mac ${tgt%%:*}:$port blocked (only the edges may connect)"; fi
  done

  section "Ext E - standby edge on Mac 3"
  local sh; sh=$(curl -s --max-time 5 "${CURL_X[@]}" --resolve "$APP:${HTTPS_PORT}:${TEST_STANDBY_IP:-$STANDBY_EDGE_IP}" -D - -o /dev/null "$URL/api/status" 2>/dev/null | tr -d '\r')
  if echo "$sh" | head -1 | grep -q " 200"; then
    echo "$sh" | grep -qi "x-edge: mac3-standby" && pass "standby edge answers with valid cert (X-Edge: mac3-standby)" || warn "standby answered but X-Edge is not mac3-standby"
  else warn "standby edge not running" "Mac 3: ./edge/mac3-standby-edge.sh start   (needed only for Ext E)"; fi
}
