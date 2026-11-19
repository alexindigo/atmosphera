#!/usr/bin/env python3
"""Loopback-only inert token counterpart; every path is supplied by the VM gate."""
import json
from pathlib import Path
import sys
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs

mode, folder = sys.argv[1], Path(sys.argv[2])
if mode == "release":
    (folder / "release").write_text(sys.argv[3])
    raise SystemExit(0)
assert mode == "serve" and folder.is_dir()
requests = []


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        assert self.path == "/token"
        body = self.rfile.read(int(self.headers["Content-Length"])).decode()
        values = parse_qs(body)
        assert values["grant_type"][0] in ("authorization_code", "refresh_token")
        assert self.headers["Authorization"].startswith("Basic ")
        requests.append(dict(number=len(requests) + 1, values=values))
        number = len(requests)
        temporary = folder / "announced.part"
        temporary.write_text(json.dumps(dict(number=number)))
        temporary.replace(folder / "announced.json")
        deadline = time.monotonic() + 15
        while int((folder / "release").read_text() or "0") < number:
            assert time.monotonic() < deadline, "fixture response release deadline"
            time.sleep(0.02)
        data = json.dumps(dict(access_token="fixture-token-" + str(number), refresh_token="fixture-refresh-" + str(number), expires_in=60)).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Explicit page destruction aborts its owned request.
        print(json.dumps(requests[-1]), flush=True)

    def log_message(self, *args):
        pass


(folder / "release").write_text("0")
server = HTTPServer(("127.0.0.1", 0), Handler)
(folder / "port").write_text(str(server.server_port))
server.serve_forever()
