from http.server import BaseHTTPRequestHandler, HTTPServer
import json, time, socket

class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type","application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/health"):
            self._send(200, {"ok": True, "ts": time.time()})
            return
        self._send(404, {"ok": False, "error": "not_found", "path": self.path})

    def do_POST(self):
        if self.path != "/decision":
            self._send(404, {"ok": False, "error": "not_found", "path": self.path})
            return
        n = int(self.headers.get("Content-Length","0") or "0")
        raw = self.rfile.read(n).decode("utf-8", errors="replace") if n>0 else ""
        try:
            _ = json.loads(raw) if raw else {}
        except Exception:
            pass
        self._send(200, {"decision":"ALLOW","reason":"local_allow_v1","latency_ms":1})

def main():
    host=("127.0.0.1", 8787)
    print(f"LOCAL_DECISION_SERVER_ALLOW listening on {host[0]}:{host[1]}", flush=True)
    HTTPServer(host, H).serve_forever()

if __name__ == "__main__":
    main()
