#!/bin/bash
# MAC 2 - nginx edge.   Run:  ./tests/test-mac2.sh
# Covers: Task A, Task D (nginx LB), Task E (cert + TLS), Ext C (edge CAN reach backends),
# Ext D (real failover + 502, proven on a private test copy of nginx so the live edge is untouched)
source "$(dirname "$0")/lib.sh"
start_log mac2
section "Role check"; check_role "$MAC2_IP"
net_tests

CERTS="${NGINX_PREFIX:-$HOME/cn-phase1/edge/nginx}/certs"; CRT="$CERTS/app.$DOMAIN.crt"; KEY="$CERTS/app.$DOMAIN.key"
CONF="${NGINX_PREFIX:-$HOME/cn-phase1/edge/nginx}/conf/nginx.conf"
EDGE_IP="${TEST_EDGE_IP:-$MAC2_IP}"; EP="${TEST_EDGE_PORT:-$HTTPS_PORT}"
E=(curl -s --max-time 5 --cacert "$CA" --resolve "$APP:$EP:$EDGE_IP" --resolve "$API:$EP:$EDGE_IP")
EURL="https://$APP:$EP"

section "Task E - certificate"
if [ -f "$CRT" ] && [ -f "$KEY" ]; then
  openssl verify -CAfile "$CA" "$CRT" >/dev/null 2>&1 && pass "server cert is signed by Team1 Local CA (team1-ca.crt)" || fail "cert not signed by team1-ca.crt" "./edge/mac2-certs.sh"
  san=$(openssl x509 -in "$CRT" -noout -ext subjectAltName 2>/dev/null)
  [[ "$san" == *"DNS:$APP"* && "$san" == *"DNS:$API"* ]] && pass "SAN covers $APP and $API" || fail "SAN missing a name: $san" "./edge/mac2-certs.sh"
  openssl x509 -in "$CRT" -noout -ext extendedKeyUsage 2>/dev/null | grep -q "Server Authentication" && pass "extendedKeyUsage = serverAuth (required by Safari/Chrome)" || fail "no serverAuth EKU" "./edge/mac2-certs.sh"
  openssl x509 -in "$CRT" -noout -checkend 2592000 >/dev/null && pass "valid for at least 30 more days ($(openssl x509 -in "$CRT" -noout -enddate | cut -d= -f2))" || fail "cert expires within 30 days" "./edge/mac2-certs.sh"
  [ "$(openssl x509 -in "$CRT" -noout -modulus | md5)" = "$(openssl rsa -in "$KEY" -noout -modulus 2>/dev/null | md5)" ] && pass "private key matches certificate" || fail "key does not match cert"
else fail "certificate files missing in $CERTS" "./edge/mac2-certs.sh"; fi

section "Task D - nginx configuration"
if [ -f "$CONF" ]; then
  grep -q "server $MAC3_IP:$BACKEND_A_PORT" "$CONF" && grep -q "server $MAC4_IP:$BACKEND_B_PORT" "$CONF" \
    && pass "upstream pool = Mac 3:$BACKEND_A_PORT + Mac 4:$BACKEND_B_PORT (round-robin)" || { [ -n "${TEST_EDGE_PORT:-}" ] && warn "upstream uses test addresses" || fail "upstream IPs differ from config.env" "./edge/nginx-script.sh reload"; }
  grep -q "max_fails=1 fail_timeout=10s" "$CONF" && grep -q "proxy_next_upstream" "$CONF" && pass "passive health check + retry on other backend configured (Ext D)" || fail "failover directives missing" "git pull && ./edge/nginx-script.sh start"
  grep -q "http2 on" "$CONF" && pass "HTTP/2 enabled" || warn "HTTP/2 not enabled"
  grep -q 'X-Edge' "$CONF" && pass "X-Edge header configured" || warn "X-Edge header missing" "git pull && ./edge/nginx-script.sh start"
else fail "no generated nginx config at $CONF" "./edge/nginx-script.sh start"; fi

section "Task D/E - live edge on this Mac"
if [ "$("${E[@]}" -o /dev/null -w '%{http_code}' "$EURL/api/status")" = 200 ]; then
  pass "nginx answers HTTPS on $EDGE_IP:$EP with a cert that validates against our CA"
  # openssl instead of curl: macOS curl cannot force a TLS version reliably
  for v in 1_2 1_3; do s=$(echo | openssl s_client -connect "$EDGE_IP:$EP" -servername "$APP" -CAfile "$CA" -tls$v 2>/dev/null)
    echo "$s" | grep -q "Verify return code: 0" && pass "TLS ${v/_/.} handshake OK, certificate verified ($(echo "$s" | awk '/Cipher is/{print $NF; exit}'))" \
      || fail "TLS ${v/_/.} handshake failed"; done
  [ "$("${E[@]}" -o /dev/null -w '%{http_version}' --http2 "$EURL/")" = 2 ] && pass "HTTP/2 via ALPN" || warn "HTTP/2 not negotiated"
  seq=""; a=0; b=0
  for _ in 1 2 3 4 5 6; do x=$("${E[@]}" -D - -o /dev/null "$EURL/api/status" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-backend"{print $2}')
    seq="$seq ${x:--}"; [ "$x" = A ] && a=$((a+1)); [ "$x" = B ] && b=$((b+1)); done
  info "X-Backend sequence:$seq"
  [ $a -gt 0 ] && [ $b -gt 0 ] && pass "round-robin across A and B" || fail "only A=$a B=$b" "check both backends"
  [ "$("${E[@]}" -o /dev/null -w '%{http_code}' "https://$API:$EP/api/status")" = 200 ] && pass "$API served too" || fail "$API not served"
else fail "nginx is not serving HTTPS on $EDGE_IP:$EP" "./edge/nginx-script.sh start"; fi

section "Ext C - the edge CAN reach both backends directly"
for t in "A:${TEST_BACKEND_A:-$MAC3_IP:$BACKEND_A_PORT}" "B:${TEST_BACKEND_B:-$MAC4_IP:$BACKEND_B_PORT}"; do
  n=${t%%:*}; addr=${t#*:}
  h=$(curl -s --max-time 4 -D - -o /dev/null "http://$addr/api/status" | tr -d '\r')
  echo "$h" | grep -qi "^x-backend: $n" && pass "Mac 2 -> Backend $n ($addr) OK (allowed by firewall)" \
    || fail "Mac 2 cannot reach Backend $n at $addr" "backend running? firewall must allow $MAC2_IP"
done

section "Ext D + 6.3 - failover and 502 (private test edge on port 18443)"
T=$(mktemp -d); mkdir -p "$T/certs"; cp "$CRT" "$KEY" "$T/certs/" 2>/dev/null
REAL_B="${TEST_BACKEND_B:-$MAC4_IP:$BACKEND_B_PORT}"; DEAD="127.0.0.1:39999"
run_edge() { NGINX_PREFIX="$T" PORT=18443 BACKEND_A="$1" BACKEND_B="$2" ./edge/nginx-script.sh "$3" primary >/dev/null 2>&1; }
TE=(curl -s --max-time 8 --cacert "$CA" --resolve "$APP:18443:127.0.0.1")
if run_edge "$DEAD" "$REAL_B" start; then
  ok=0; bb=0
  for _ in 1 2 3 4 5 6; do r=$("${TE[@]}" -D - -o /dev/null "https://$APP:18443/api/status" | tr -d '\r')
    echo "$r" | head -1 | grep -q " 200" && ok=$((ok+1)); echo "$r" | grep -qi "^x-backend: B" && bb=$((bb+1)); done
  [ $ok -eq 6 ] && [ $bb -eq 6 ] && pass "Backend A dead: 6/6 requests still 200, all served by B (retry + passive health check)" \
    || fail "with A dead only $ok/6 succeeded (B served $bb)"
  # full restart (not reload) so no old worker with the previous pool can answer
  NGINX_PREFIX="$T" PORT=18443 ./edge/nginx-script.sh stop >/dev/null 2>&1; sleep 1
  run_edge "$DEAD" "127.0.0.1:39998" start; sleep 0.5
  r=$("${TE[@]}" -o /dev/null -w '%{http_code}' "https://$APP:18443/api/status")
  [ "$r" = 502 ] && pass "both backends dead: TLS still works, nginx returns 502 Bad Gateway" || fail "both dead returned $r (expected 502)"
  NGINX_PREFIX="$T" PORT=18443 ./edge/nginx-script.sh stop >/dev/null 2>&1
else fail "could not start the private test edge" "is port 18443 free? nginx installed?"; fi
rm -rf "$T"

summary
