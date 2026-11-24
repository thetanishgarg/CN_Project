#!/bin/bash
# MAC 3 - Backend A + standby edge.   Run:  ./tests/test-mac3.sh
# Covers: Task A, Task C + F (Backend A), identical cache ETag with Backend B,
# Ext C (firewall rules on this Mac), Ext E (standby edge on this Mac)
source "$(dirname "$0")/lib.sh"
start_log mac3
section "Role check"; check_role "$MAC3_IP"
net_tests
backend_tests A "$BACKEND_A_PORT"

section "Task F - same ETag on Backend B (so 304 works through the load balancer)"
BB="${TEST_BACKEND_B:-$MAC4_IP:$BACKEND_B_PORT}"
eb=$(curl -s --max-time 4 -I "http://$BB/api/cache" | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}')
if [ -z "$eb" ]; then fail "cannot read /api/cache from Backend B ($BB)" "Mac 4 backend running? firewall must allow the standby edge $STANDBY_EDGE_IP"
elif [ "$eb" = "${BACKEND_ETAG:-x}" ]; then pass "Backend A and B /api/cache ETag identical ($eb)"
else fail "ETag differs: A=$BACKEND_ETAG B=$eb" "both Macs must run the same backend/backend.py (git pull)"; fi

section "Ext C - backend firewall on this Mac"
AF=/etc/pf.anchors/team1-backend
if [ -f "$AF" ]; then
  grep -q "$MAC2_IP" "$AF" && pass "rule allows the primary edge $MAC2_IP" || fail "firewall does not allow Mac 2" "sudo ./firewall/backend-firewall.sh apply"
  grep -q "$STANDBY_EDGE_IP" "$AF" && pass "rule allows the standby edge $STANDBY_EDGE_IP" || fail "firewall does not allow the standby edge"
  grep -q "$BACKEND_A_PORT" "$AF" && pass "rule protects port $BACKEND_A_PORT" || fail "firewall rule is not for port $BACKEND_A_PORT"
  if sudo -n pfctl -a com.apple/team1-backend -sr >/dev/null 2>&1; then
    [ -n "$(sudo -n pfctl -a com.apple/team1-backend -sr 2>/dev/null)" ] && pass "rules are LOADED in pf (active now)" || warn "rule file exists but not loaded" "sudo ./firewall/backend-firewall.sh apply"
  else info "run 'sudo ./firewall/backend-firewall.sh status' to confirm the rules are loaded"; fi
  [ -f /etc/pf.anchors/team1-backend.bak ] && pass "rollback backup exists (remove restores original pf state)" || warn "no rollback backup file"
else warn "firewall not applied on this Mac" "sudo ./firewall/backend-firewall.sh apply   (expected only during Ext C)"; fi

section "Ext E - standby edge on this Mac"
SIP="${TEST_STANDBY_IP:-$MAC3_IP}"; SP="${TEST_STANDBY_PORT:-$HTTPS_PORT}"
S=(curl -s --max-time 5 --cacert "$CA" --resolve "$APP:$SP:$SIP")
C3="$HOME/cn-phase1/edge/nginx/certs/app.$DOMAIN"
if [ -f "$C3.crt" ]; then
  openssl verify -CAfile "$CA" "$C3.crt" >/dev/null 2>&1 && pass "edge certificate imported and signed by Team1 Local CA" || fail "imported cert not signed by our CA"
else warn "edge certificate not imported" "Mac 2: ./edge/mac2-export-certs.sh, AirDrop, then ./edge/mac2-import-certs.sh <tgz>"; fi
h=$("${S[@]}" -D - -o /dev/null "https://$APP:$SP/api/status" | tr -d '\r')
if echo "$h" | head -1 | grep -q " 200"; then
  echo "$h" | grep -qi "^x-edge: mac3-standby" && pass "standby nginx serves HTTPS, X-Edge: mac3-standby" || fail "edge on this Mac is not in standby role" "./edge/mac3-standby-edge.sh start"
  seq=""; a=0; b=0
  for _ in 1 2 3 4 5 6; do x=$("${S[@]}" -D - -o /dev/null "https://$APP:$SP/api/status" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-backend"{print $2}')
    seq="$seq ${x:--}"; [ "$x" = A ] && a=$((a+1)); [ "$x" = B ] && b=$((b+1)); done
  info "X-Backend sequence via standby:$seq"
  [ $a -gt 0 ] && [ $b -gt 0 ] && pass "standby edge load-balances to both backends" || fail "standby reaches only A=$a B=$b" "Backend B firewall must allow $STANDBY_EDGE_IP"
else warn "standby edge not running on this Mac" "./edge/mac3-standby-edge.sh start   (needed only for Ext E)"; fi

summary
