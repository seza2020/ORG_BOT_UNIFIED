from http.server import BaseHTTPRequestHandler, HTTPServer
import json, time

class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        b = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.endswith("/health"):
            return self._send(200, {"ok": True, "ts": time.time()})
        return self._send(404, {"ok": False})

    def do_POST(self):
        if self.path != "/decision":
            return self._send(404, {"decision":"BLOCK","reason":"bad_path"})
        n = int(self.headers.get("Content-Length","0"))
        _ = self.rfile.read(n) if n > 0 else b""
        return self._send(200, {"decision":"ALLOW","reason":"mock_allow"})

    def log_message(self, fmt, *args):
        return

if __name__ == "__main__":
    print("LOCAL_DECISION_SERVER_ALLOW listening on 127.0.0.1:8787")
    HTTPServer(("127.0.0.1", 8787), H).serve_forever()
