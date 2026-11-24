#!/usr/bin/env python3

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import hashlib
import os

BACKEND_NAME = os.environ.get("BACKEND_NAME", "UNKNOWN")
PORT = int(os.environ.get("BACKEND_PORT", "3001"))

# ---------------------------------------------------------------------------
# /api/cache body is IDENTICAL on BOTH backends (no backend name in it)
# so the ETag is the same regardless of which backend nginx picks.
# ---------------------------------------------------------------------------
_CACHE_BODY = json.dumps(
    {"resource": "cn-phase1-cache-demo", "version": 1},
    indent=2,
    sort_keys=True,
).encode("utf-8")
_CACHE_ETAG = '"' + hashlib.md5(_CACHE_BODY).hexdigest() + '"'


class Handler(BaseHTTPRequestHandler):

    def send_json(self, data, status=200, extra_headers=None):
        """Send a JSON response.

        extra_headers: list of (name, value) tuples added after the
        standard headers.  Pass cache_control=None to suppress ETag /
        Cache-Control (used by /api/status).
        """
        body = json.dumps(data, indent=2).encode("utf-8")
        etag = '"' + hashlib.md5(body).hexdigest() + '"'

        if extra_headers is None:
            extra_headers = []

        # Build a quick lookup so callers can influence caching behaviour
        hdr_map = {k.lower(): v for k, v in extra_headers}

        # Conditional request check (only when we are sending an ETag)
        if "cache-control" in hdr_map and hdr_map["cache-control"] != "no-store":
            if self.headers.get("If-None-Match") == etag:
                self.send_response(304)
                self.send_header("ETag", etag)
                self.send_header("X-Backend", BACKEND_NAME)
                for k, v in extra_headers:
                    self.send_header(k, v)
                self.end_headers()
                return

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Backend", BACKEND_NAME)

        for k, v in extra_headers:
            self.send_header(k, v)

        # Send ETag only when caching is enabled (not no-store)
        if "cache-control" in hdr_map and hdr_map["cache-control"] != "no-store":
            self.send_header("ETag", etag)

        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _send_cache_endpoint(self):
        """Handle /api/cache with a fixed body identical on A and B."""
        # Conditional GET — ETag is precomputed and backend-independent
        if self.headers.get("If-None-Match") == _CACHE_ETAG:
            self.send_response(304)
            self.send_header("ETag", _CACHE_ETAG)
            self.send_header("Cache-Control", "max-age=60")
            self.send_header("X-Backend", BACKEND_NAME)
            self.end_headers()
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(_CACHE_BODY)))
        self.send_header("Cache-Control", "max-age=60")
        self.send_header("ETag", _CACHE_ETAG)
        self.send_header("X-Backend", BACKEND_NAME)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(_CACHE_BODY)

    def do_HEAD(self):
        # curl -I sends HEAD: same headers as GET, no body
        self.do_GET()

    def do_GET(self):

        if self.path == "/":
            self.send_json(
                {
                    "service": "Computer Networks Phase 1",
                    "backend": BACKEND_NAME,
                    "status": "ok",
                },
                extra_headers=[("Cache-Control", "max-age=60")],
            )

        elif self.path == "/api/status":
            # no-store: browser must NOT cache this so load-balancing is visible
            self.send_json(
                {"backend": BACKEND_NAME, "status": "ok"},
                extra_headers=[("Cache-Control", "no-store")],
            )

        elif self.path == "/api/cache":
            self._send_cache_endpoint()

        else:
            self.send_json(
                {"error": "Not Found", "path": self.path},
                status=404,
                extra_headers=[("Cache-Control", "no-store")],
            )

    def log_message(self, format, *args):
        print("[%s] %s" % (BACKEND_NAME, format % args))


server = HTTPServer(("0.0.0.0", PORT), Handler)

print("=" * 50)
print(f"Backend {BACKEND_NAME}")
print(f"Listening on 0.0.0.0:{PORT}")
print("Endpoints:")
print("  GET /            -> service info")
print("  GET /api/status  -> no-store (shows load balancing)")
print("  GET /api/cache   -> max-age=60 + ETag (identical on A & B)")
print("=" * 50)

server.serve_forever()