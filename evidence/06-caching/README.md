# Evidence: Task F — Caching

Capture these artefacts before the viva.

## Commands to run (copy-paste)

```bash
# 1. Cold request — 200 + ETag + Cache-Control: max-age=60
curl -I https://app.team1.test/api/cache 2>&1 | tee evidence/06-caching/01-cold-200.txt

# 2. Six conditional requests — all must be 304
ETAG=$(curl -sI https://app.team1.test/api/cache | grep -i '^etag:' | tr -d '\r' | awk '{print $2}')
for i in {1..6}; do
  curl -s -o /dev/null -w "Request $i: HTTP %{http_code}\n" \
    -H "If-None-Match: $ETAG" https://app.team1.test/api/cache
done | tee evidence/06-caching/02-conditional-304.txt

# 3. /api/status must show no-store (not cached)
curl -sI https://app.team1.test/api/status | grep -i cache-control \
  | tee evidence/06-caching/03-status-no-store.txt

# 4. Same ETag on both backends (first: source config.env)
echo "Backend A:"; curl -sI http://$MAC3_IP:3001/api/cache | grep -i etag
echo "Backend B:"; curl -sI http://$MAC4_IP:3002/api/cache | grep -i etag
```

## Chrome DevTools screenshots needed
- **05-chrome-304.png** — Second reload (Ctrl+Shift+R or regular F5): DevTools > Network > /api/cache → Status 304
- **06-chrome-disk.png** — Visit within 60 s without reload: Status 200 / (disk cache) or (memory cache)
