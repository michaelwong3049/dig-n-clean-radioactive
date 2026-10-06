"""Localhost sink for export-merged-nuke-meshes.luau: Studio POSTs mesh text, this writes it.

Usage: python tools/studio-migrations/mesh_sink.py merged-nukes
"""
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
SAFE = re.compile(r"^[A-Za-z0-9_.-]+$")


class Sink(BaseHTTPRequestHandler):
    def do_GET(self):
        # /read?file=batch_01.json hands a written file back (the apply step's
        # manifests); anything else is a ping.
        q = parse_qs(urlparse(self.path).query)
        name = q.get("file", [""])[0]
        if name:
            path = os.path.join(OUT, name)
            if not SAFE.match(name) or not os.path.isfile(path):
                self.send_response(404)
                self.end_headers()
                return
            with open(path, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def do_POST(self):
        q = parse_qs(urlparse(self.path).query)
        name = q.get("file", [""])[0]
        mode = "a" if q.get("mode", ["w"])[0] == "a" else "w"
        if not SAFE.match(name):
            self.send_response(400)
            self.end_headers()
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        with open(os.path.join(OUT, name), mode, encoding="utf-8", newline="\n") as f:
            f.write(body.decode("utf-8"))
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


HTTPServer(("127.0.0.1", 59999), Sink).serve_forever()
