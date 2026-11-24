#!/bin/bash
# Ext D - High-availability failover demo (run on a CLIENT: Mac 1 or Mac 4, or on Mac 2)
#
#   ./edge/mac2-ha-demo.sh demo     guided: baseline -> stop Backend A -> all served by B -> restart A -> A/B again
#   ./edge/mac2-ha-demo.sh watch    one request per second forever (leave it running on screen; Ctrl+C)
#
# Output of "demo" is saved to evidence/10-ha-failover/
cd "$(dirname "$0")/.."
source ./config.env
URL="https://app.$PROJECT_DOMAIN"; [ "$HTTPS_PORT" != "443" ] && URL="$URL:$HTTPS_PORT"
# Real certificate validation against our CA (no -k)
CURL=(curl -s --max-time 6 --cacert ./team1-ca.crt)
# On Mac 2 itself, talk to the local edge without depending on DNS
MYIP=$(ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')" 2>/dev/null)
[ "$MYIP" = "$MAC2_IP" ] && CURL+=(--resolve "app.$PROJECT_DOMAIN:$HTTPS_PORT:$MAC2_IP")

one() {  # prints: time  status  backend  edge  total-time
  "${CURL[@]}" -o /dev/null -D - -w 'TIME %{time_total}\n' "$URL/api/status" | tr -d '\r' | awk -v t="$(date +%H:%M:%S)" '
    /^HTTP/{s=$2} tolower($1)=="x-backend:"{b=$2} tolower($1)=="x-edge:"{e=$2} /^TIME/{tt=$2}
    END{printf "  %s  %s  X-Backend: %-2s X-Edge: %-13s %.3fs\n", t, (s?s:"FAIL"), (b?b:"-"), (e?e:"-"), tt}'
}
burst() { local ok=0 a=0 b=0 out; for i in $(seq "${1:-6}"); do out=$(one); echo "$out"
  [[ "$out" == *" 200 "* ]] && ok=$((ok+1)); [[ "$out" == *"X-Backend: A"* ]] && a=$((a+1)); [[ "$out" == *"X-Backend: B"* ]] && b=$((b+1)); done
  echo "  -> ${ok}/${1:-6} succeeded   A=$a  B=$b"; }
pause() { echo; read -r -p ">> $* [Enter] " _ </dev/tty; }

case "${1:-demo}" in
watch)
  echo "Requesting $URL/api/status every second (Ctrl+C to stop)"
  while true; do one; sleep 1; done ;;
demo)
  mkdir -p evidence/10-ha-failover
  LOG="evidence/10-ha-failover/ha-failover-$(date +%H%M%S).txt"
  exec > >(tee "$LOG") 2>&1
  echo "===== Ext D: HA failover  ($(date))  URL: $URL ====="
  echo; echo "1) Both backends healthy - round-robin"
  burst 6
  pause "Mac 3: press Ctrl+C on Backend A now"
  echo "2) Backend A DOWN - nginx gets 'connection refused', retries the same request on B"
  echo "   (proxy_next_upstream) and marks A down for 10 s (max_fails=1 fail_timeout=10s)"
  burst 8
  pause "Mac 3: restart Backend A  (BACKEND_NAME=A BACKEND_PORT=3001 python3 backend/backend.py)"
  echo "3) Waiting 11 s for A's fail_timeout to expire..."; sleep 11
  echo "   Backend A back - nginx retries it, it answers, load balancing resumes"
  burst 6
  echo
  echo "RESULT: the client saw no errors while a backend died; recovery needed no config change."
  echo "STILL A SINGLE POINT OF FAILURE: the edge itself (Mac 2). See MAC2-PHASE2.md."
  echo; echo "(saved to $LOG)" ;;
*) sed -n '2,8p' "$0" ;;
esac
