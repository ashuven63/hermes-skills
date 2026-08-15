#!/usr/bin/env python3
"""Static file server for the research-digest vault.

Serves $RESEARCH_DIR (default ~/research/) over HTTP. Binds $RESEARCH_HOST
(default 127.0.0.1) on $RESEARCH_PORT (default 8088). Designed to sit behind
Tailscale (RESEARCH_HOST=0.0.0.0) for phone access. No auth by design — keep it
off the public internet.

Usage:
    python3 serve.py [port]
"""
import os
import sys
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

RESEARCH_DIR = Path(os.environ.get("RESEARCH_DIR", Path.home() / "research")).expanduser()
PORT = int(sys.argv[1] if len(sys.argv) > 1 else os.environ.get("RESEARCH_PORT", "8088"))
HOST = os.environ.get("RESEARCH_HOST", "127.0.0.1")


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(RESEARCH_DIR), **kwargs)

    def end_headers(self):
        # Prevent the browser from caching reports while you iterate.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        # Serve a generated index page at "/" from index.json if present.
        if self.path in ("/", "/index.html"):
            manifest = RESEARCH_DIR / "index.json"
            if manifest.exists():
                try:
                    entries = json.loads(manifest.read_text())
                except Exception:
                    entries = []
                body = self._render_index(entries)
                data = body.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
        super().do_GET()

    def _render_index(self, entries):
        rows = []
        for e in sorted(entries, key=lambda x: x.get("date", ""), reverse=True):
            slug = e.get("slug", "")
            title = e.get("title", slug)
            date = e.get("date", "")
            tags = " ".join("#" + t for t in e.get("tags", []))
            rows.append(
                f'<li><a href="/{slug}">{title}</a> '
                f'<span class="meta">{date} {tags}</span></li>'
            )
        row_html = "\n".join(rows) if rows else "<li><em>No reports yet.</em></li>"
        return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Research Vault</title>
<style>
 body {{ font-family: system-ui, sans-serif; max-width: 760px; margin: 2rem auto; padding: 0 1rem; }}
 h1 {{ font-size: 1.4rem; }}
 ul {{ list-style: none; padding: 0; }}
 li {{ padding: .6rem 0; border-bottom: 1px solid #eee; }}
 a {{ color: #2563eb; text-decoration: none; font-weight: 600; }}
 .meta {{ display: block; color: #888; font-size: .8rem; margin-top: .2rem; }}
</style></head>
<body>
<h1>Research Vault</h1>
<ul>{row_html}</ul>
</body></html>"""

    def log_message(self, fmt, *args):
        pass  # quiet


def main():
    RESEARCH_DIR.mkdir(parents=True, exist_ok=True)
    os.chdir(RESEARCH_DIR)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"research-serve: serving {RESEARCH_DIR} at http://{HOST}:{PORT}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
