#!/bin/bash
# MAC 4 - Backend B + backup DNS + main test client.   Run:  ./tests/test-mac4.sh
# Covers: Task A, Task C + F (Backend B), Ext A (backup DNS on this Mac), and the whole
# client side: Task B/D/E/F, 6.3 failure simulations, Ext A/B/C/E, Task G evidence
source "$(dirname "$0")/lib.sh"
start_log mac4
section "Role check"; check_role "$MAC4_IP"
net_tests
backend_tests B "$BACKEND_B_PORT"

section "Ext A - backup DNS server on this Mac"
if pgrep -x dnsmasq >/dev/null || pgrep -f dns_server.py >/dev/null; then pass "backup DNS process is running"
else fail "backup DNS is not running" "sudo ./dns/mac4-backup-dns.sh"; fi
a=$(dig +short +time=2 +tries=1 "@${TEST_DNS_LOCAL:-$MAC4_IP}" ${TEST_DNS_PORT:+-p $TEST_DNS_PORT} "$APP" | grep -E '^[0-9.]+$' | tail -1)
[ "$a" = "$EXPECTED_TARGET" ] && pass "backup DNS answers $APP -> $a" || fail "backup DNS answers '${a:-nothing}'" "sudo ./dns/mac4-backup-dns.sh"

client_tests

section "Task G - packet capture evidence"
pc=$(ls -t evidence/05-wireshark/*.pcap* 2>/dev/null | head -1)
if [ -n "$pc" ] && [ -s "$pc" ]; then
  pass "capture file present: $pc ($(wc -c < "$pc" | tr -d ' ') bytes)"
  if tcpdump -nn -r "$pc" 2>/dev/null | grep -q "\.53: "; then pass "capture contains the DNS query"; else warn "no DNS packets in capture" "flush cache before capturing (the capture script does this)"; fi
  tcpdump -nn -r "$pc" "tcp[tcpflags] & tcp-syn != 0" 2>/dev/null | grep -q "\.$HTTPS_PORT" && pass "capture contains the TCP handshake to $HTTPS_PORT" || warn "no SYN to $HTTPS_PORT in capture"
else warn "no .pcap yet" "sudo ./client/mac4-task-g-capture.sh"; fi

summary
