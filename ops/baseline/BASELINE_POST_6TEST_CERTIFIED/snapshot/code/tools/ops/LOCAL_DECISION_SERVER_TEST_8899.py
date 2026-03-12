from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"decision":"ALLOW"}')

print("LISTENING 127.0.0.1:8899")
HTTPServer(("127.0.0.1",8899),H).serve_forever()
