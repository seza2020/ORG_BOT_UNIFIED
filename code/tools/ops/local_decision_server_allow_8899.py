from http.server import BaseHTTPRequestHandler, HTTPServer
import json, time

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        t0 = time.time()
        ln = int(self.headers.get('Content-Length','0') or '0')
        _ = self.rfile.read(ln) if ln>0 else b''
        resp = {"decision":"ALLOW","reason":"local_allow","latency_ms": (time.time()-t0)*1000.0}
        b = json.dumps(resp).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

if __name__ == "__main__":
    print(f"LOCAL_DECISION_SERVER_ALLOW listening on 127.0.0.1:{ 8899 }")
    HTTPServer(("127.0.0.1", 8899), H).serve_forever()
