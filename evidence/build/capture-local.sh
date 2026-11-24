#!/bin/bash
# Evidence that can be recorded on ONE Mac (no sudo, no team LAN needed).
# Every output file says it is a single-Mac run. Multi-Mac proof comes from
# capture-lan.sh, run when all four Macs share one Wi-Fi.
cd "$(dirname "$0")/../.." || exit 1
source ./config.env
E=evidence; TMP=$(mktemp -d); PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf "$TMP"' EXIT
for p in 3001 3002 5300 5301; do lsof -nP -iTCP:$p -sTCP:LISTEN >/dev/null 2>&1 && { echo "port $p is in use - stop it first"; exit 1; }; done
hdr() { echo "SINGLE-MAC RUN   $(date)   host $(uname -srm)"; echo "$1"; echo "----------------------------------------------------------------"; }
run() { echo; echo "\$ $*"; eval "$*" 2>&1; }

BACKEND_NAME=A BACKEND_PORT=3001 python3 -u backend.py >"$TMP/A.log" 2>&1 & PIDS+=($!)
BACKEND_NAME=B BACKEND_PORT=3002 python3 -u backend.py >"$TMP/B.log" 2>&1 & PIDS+=($!)
disown -a
sleep 1.5

{ hdr "Both backend.py processes, real HTTP requests over loopback"
  run "curl -si http://127.0.0.1:3001/api/status"
  run "curl -si http://127.0.0.1:3002/api/status"
  run "curl -si http://127.0.0.1:3002/"
  run "curl -si http://127.0.0.1:3002/nope"
  run "lsof -nP -iTCP:3001 -iTCP:3002 -sTCP:LISTEN | awk '{print \$1, \$2, \$5, \$8, \$9, \$10}'"; } > $E/04-load-balancing/backends-local.txt

{ hdr "HTTP caching: 200 with ETag, then If-None-Match -> 304, on BOTH backends"
  run "curl -sI http://127.0.0.1:3001/api/cache"
  run "curl -sI http://127.0.0.1:3002/api/cache"
  ET=$(curl -sI http://127.0.0.1:3001/api/cache | tr -d '\r' | awk 'tolower($1)=="etag:"{print $2}')
  echo; echo "ETag taken from A, replayed to A and B:"
  for p in 3001 3002; do for i in 1 2 3; do curl -s -o /dev/null -H "If-None-Match: $ET" -w "  :$p request $i -> HTTP %{http_code}, %{size_download} body bytes\n" http://127.0.0.1:$p/api/cache; done; done
  run "curl -si -H 'If-None-Match: $ET' http://127.0.0.1:3002/api/cache"
  echo; echo "Wrong ETag must NOT give 304:"
  curl -s -o /dev/null -H 'If-None-Match: "deadbeef"' -w "  HTTP %{http_code}, %{size_download} body bytes\n" http://127.0.0.1:3002/api/cache
  run "curl -sI http://127.0.0.1:3002/api/status | grep -i cache-control"; } > $E/06-caching/caching-local.txt

mkconf() { cat > "$1" <<C
listen-address=127.0.0.1
bind-interfaces
port=$2
address=/app.$PROJECT_DOMAIN/$3
address=/api.$PROJECT_DOMAIN/$3
local-ttl=$DNS_TTL
local=/$PROJECT_DOMAIN/
local=/test/
server=8.8.8.8
server=8.8.4.4
no-resolv
no-hosts
log-queries
log-facility=-
keep-in-foreground
pid-file=$TMP/$2.pid
C
}
E1=10.128.139.225; E2=10.128.139.70        # addresses recorded on the 23 Nov demo LAN
mkconf "$TMP/p.conf" 5300 $E1; mkconf "$TMP/b.conf" 5301 $E1
dnsmasq -C "$TMP/p.conf" >"$TMP/p.log" 2>&1 & P=$!; PIDS+=($P)
dnsmasq -C "$TMP/b.conf" >"$TMP/b.log" 2>&1 & PIDS+=($!)
sleep 1
D="dig +time=2 +tries=1 @127.0.0.1"

{ hdr "dnsmasq with the same directives start-dns.sh generates, on 127.0.0.1:5300"
  run "grep -vE 'pid-file|keep-in' $TMP/p.conf" | sed "s#$TMP/##"
  run "$D -p 5300 app.$PROJECT_DOMAIN"
  run "$D -p 5300 +short api.$PROJECT_DOMAIN"
  run "$D -p 5300 nosuch.$PROJECT_DOMAIN | grep -E 'status:|flags:'"
  run "$D -p 5300 google.com A | grep -E 'status:|IN.A' | head -3"
  run "$D -p 5300 +tcp +short app.$PROJECT_DOMAIN"
  echo; echo "dnsmasq query log:"; grep -E 'team1.test' "$TMP/p.log" | sed 's/^/  /'; } > $E/02-dns/dns-local.txt

{ hdr "Ext A mechanism: primary (:5300) killed, backup (:5301) has the same record"
  run "$D -p 5300 app.$PROJECT_DOMAIN | grep -E 'status:|IN.A|SERVER'"
  run "$D -p 5301 app.$PROJECT_DOMAIN | grep -E 'status:|IN.A|SERVER'"
  echo; echo ">>> kill primary dnsmasq (pid $P)"; kill $P; wait $P 2>/dev/null; sleep .5
  run "$D -p 5300 app.$PROJECT_DOMAIN | tail -2"
  run "$D -p 5301 app.$PROJECT_DOMAIN | grep -E 'status:|IN.A|SERVER'"
  echo; echo "Scope: proves identical records and independent processes. Automatic switch-over by the macOS"
  echo "resolver needs two hosts on port 53 and is not shown here."; } > $E/08-backup-dns/backup-dns-local.txt

mkconf "$TMP/p.conf" 5300 $E1; dnsmasq -C "$TMP/p.conf" >"$TMP/p.log" 2>&1 & P=$!; PIDS+=($P); sleep .7
{ hdr "Ext B mechanism: record changed on the server, dig sees it at once (TTL $DNS_TTL)"
  run "$D -p 5300 +noall +answer app.$PROJECT_DOMAIN"
  echo; echo ">>> restart with target $E2"; kill $P; wait $P 2>/dev/null
  mkconf "$TMP/p.conf" 5300 $E2; dnsmasq -C "$TMP/p.conf" >"$TMP/p.log" 2>&1 & P=$!; PIDS+=($P); sleep .7
  run "$D -p 5300 +noall +answer app.$PROJECT_DOMAIN"
  echo; echo "Scope: the server side only. The client-cache side was recorded on the real LAN in 12-edge-cutover/."; } > $E/09-ttl/ttl-local.txt

{ hdr "Section 6.3 failure signatures that need no second Mac"
  echo; echo "A. DNS has no such name -> curl exit 6, before any TCP"; curl -sS -m 5 https://nosuch.team1.invalid/ ; echo "   curl exit code $?"
  echo; echo "B. Port with nothing listening -> TCP refused, curl exit 7"; curl -sS -m 5 http://127.0.0.1:8443/ ; echo "   curl exit code $?"
  echo; echo "C. Backend A killed -> its port refuses, B still answers"; kill ${PIDS[0]}; sleep .5
  curl -sS -m 5 http://127.0.0.1:3001/api/status; echo "   A: curl exit code $?"; curl -s -m 5 http://127.0.0.1:3002/api/status; echo "   B: curl exit code $?"
  echo; echo "D. Plain HTTP spoken to a TLS client -> TLS error, curl exit 35"; curl -sS -m 5 https://127.0.0.1:3002/ ; echo "   curl exit code $?"; } > $E/07-failures/failure-signatures-local.txt 2>&1

{ hdr "Ext F tool run with the team LAN absent (no fault was injected; DNS is genuinely unavailable)"
  echo; echo "\$ ./troubleshoot/diagnose.sh"; ./troubleshoot/diagnose.sh 2>&1 | sed $'s/\e\\[[0-9;]*m//g'; echo "exit code ${PIPESTATUS[0]}"; } > $E/13-troubleshooting/diagnose-no-lan.txt
echo done
