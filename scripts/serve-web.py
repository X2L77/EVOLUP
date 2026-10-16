"""Serve the compiled Flutter app for Replit's development preview."""

from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class PreviewHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    web_root = Path(__file__).resolve().parent.parent / "build" / "web"
    if not (web_root / "index.html").is_file():
        raise SystemExit("Web build missing. Run bash scripts/run-web.sh first.")
    handler = partial(PreviewHandler, directory=str(web_root))
    server = ThreadingHTTPServer(("0.0.0.0", 5000), handler)
    print("Flutter web preview listening on 0.0.0.0:5000", flush=True)
    server.serve_forever()
