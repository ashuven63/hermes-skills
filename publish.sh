#!/bin/bash
# publish.sh — recreate the hermes-skills tap repo and push to GitHub.
# Generated from the verified source. Run ONCE on the host:
#   bash publish.sh [target-dir]   (default: $HOME/hermes-skills)
set -euo pipefail

REPO_DIR="${1:-$HOME/hermes-skills}"

echo "→ Creating repo at $REPO_DIR"
mkdir -p "$REPO_DIR/skills/research-digest"

cat > "$REPO_DIR/skills/research-digest/SKILL.md" <<'PUB_SKILL_EOF'
---
name: research-digest
description: Turn a research request into a self-contained interactive HTML report saved to the research vault and served for viewing on any device. Use when the user asks to "research", "digest", "summarize and visualize", "make a report/dashboard", or "produce an artifact" about a topic — and wants the output as a viewable HTML page instead of chat markdown.
---

# Research Digest — interactive HTML reports

## What this produces
Instead of dumping markdown into chat, you produce a single self-contained
`.html` file (inline CSS/JS, no build step) that the user opens in a browser —
desktop or phone. The report lives in the research vault and is served by
`research-serve` so it is reachable from anywhere (via Tailscale/LAN).

## Storage
- Vault dir: `$RESEARCH_DIR` (env), default `~/research/`.
- Each report: `<slug>.html` (slug = date + topic key, e.g.
  `2026-08-09-local-llm-inference.html`).
- Also maintain `index.json` manifest — an array of
  `{slug, title, date, tags, path}` — so `research-serve` can list reports at `/`.

## Workflow
1. Research the topic with `web_search` + `web_extract`. Gather real sources
   (keep their URLs — you must cite them).
2. Decide the structure: overview, key findings, comparison table, timeline,
   charts, sources. Match depth to the ask.
3. Generate ONE self-contained HTML file. Follow the HTML pattern below.
   Keep it dependency-light: inline CSS, vanilla JS. For charts, prefer simple
   inline SVG / CSS bars; use a CDN (Chart.js) only if a real chart is needed.
4. `write_file` to `$RESEARCH_DIR/<slug>.html`.
5. Update `index.json` (append the entry; create the file if missing).
6. Ensure the server is up: `cd <skill-dir> && ./start.sh`. It is idempotent —
   if the port is already listening it no-ops.
7. Deliver to the user: post the URL
   `http://<host>:<port>/<slug>.html` (and/or attach the file). On Slack a link
   is best — mobile opens it in its in-app browser.

## HTML pattern (self-contained)
```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>TITLE</title>
  <style>/* inline, responsive, light or dark */</style>
</head>
<body>
  <header>...</header>
  <main>
    <section>overview</section>
    <section>key findings</section>
    <section>sources (cite as <a href>)</section>
  </main>
  <script>/* optional vanilla JS: tabs, filters */</script>
</body>
</html>
```
For visual polish on demand, load the `popular-web-designs` or `claude-design`
skill and apply a real design system.

## Serving (research-serve)
- `serve.py`: stdlib `http.server`, serves `$RESEARCH_DIR`, binds
  `$RESEARCH_HOST` (default 127.0.0.1) on `$RESEARCH_PORT` (default 8088).
- Phone access: run behind Tailscale with `RESEARCH_HOST=0.0.0.0`, then open
  `http://<tailscale-ip>:8088/`. Never expose publicly without auth.
- `start.sh [port]` launches in background, logs to `<skill-dir>/serve.log`.

## Architecture rules
- Never overwrite an existing `<slug>.html` without reading it first. New topic
  = new slug (date-prefixed avoids collisions).
- Cite sources inline — the report must be self-verifying.
- Keep it one file. No external CSS/JS except optional CDN charts.
- `index.json` is the only shared mutable file — read before patch, append only.
PUB_SKILL_EOF

cat > "$REPO_DIR/skills/research-digest/serve.py" <<'PUB_SERVE_EOF'
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
PUB_SERVE_EOF

cat > "$REPO_DIR/skills/research-digest/start.sh" <<'PUB_START_EOF'
#!/bin/bash
# Start the research-digest static server (idempotent).
# Usage: ./start.sh [port]   (default 8088, or $RESEARCH_PORT)
set -e
cd "$(dirname "$0")"
PORT="${1:-${RESEARCH_PORT:-8088}}"
HOST="${RESEARCH_HOST:-127.0.0.1}"

# No-op if something is already listening on the port.
if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "research-serve already listening on $PORT — leaving it running."
    exit 0
  fi
fi

mkdir -p "$HOME/research"
nohup python3 "$PWD/serve.py" "$PORT" > "$PWD/serve.log" 2>&1 &
echo "research-serve started (PID $!) on http://$HOST:$PORT"
echo "Logs: $PWD/serve.log"
PUB_START_EOF

cat > "$REPO_DIR/install.sh" <<'PUB_INSTALL_EOF'
#!/bin/bash
# install.sh — self-contained installer for the research-digest skill.
# No network needed: all files are embedded below.
# Run on the HOST (where Hermes lives):  bash install.sh
set -e

SKILL_DIR="${HOME}/.hermes/skills/research-digest"
RESEARCH_DIR="${RESEARCH_DIR:-${HOME}/research}"

echo "→ Installing research-digest into $SKILL_DIR"
mkdir -p "$SKILL_DIR"

# ---- SKILL.md ----
cat > "$SKILL_DIR/SKILL.md" <<'SKILL_EOF'
---
name: research-digest
description: Turn a research request into a self-contained interactive HTML report saved to the research vault and served for viewing on any device. Use when the user asks to "research", "digest", "summarize and visualize", "make a report/dashboard", or "produce an artifact" about a topic — and wants the output as a viewable HTML page instead of chat markdown.
---

# Research Digest — interactive HTML reports

## What this produces
Instead of dumping markdown into chat, you produce a single self-contained
`.html` file (inline CSS/JS, no build step) that the user opens in a browser —
desktop or phone. The report lives in the research vault and is served by
`research-serve` so it is reachable from anywhere (via Tailscale/LAN).

## Storage
- Vault dir: `$RESEARCH_DIR` (env), default `~/research/`.
- Each report: `<slug>.html` (slug = date + topic key, e.g.
  `2026-08-09-local-llm-inference.html`).
- Also maintain `index.json` manifest — an array of
  `{slug, title, date, tags, path}` — so `research-serve` can list reports at `/`.

## Workflow
1. Research the topic with `web_search` + `web_extract`. Gather real sources
   (keep their URLs — you must cite them).
2. Decide the structure: overview, key findings, comparison table, timeline,
   charts, sources. Match depth to the ask.
3. Generate ONE self-contained HTML file. Follow the HTML pattern below.
   Keep it dependency-light: inline CSS, vanilla JS. For charts, prefer simple
   inline SVG / CSS bars; use a CDN (Chart.js) only if a real chart is needed.
4. `write_file` to `$RESEARCH_DIR/<slug>.html`.
5. Update `index.json` (append the entry; create the file if missing).
6. Ensure the server is up: `cd <skill-dir> && ./start.sh`. It is idempotent —
   if the port is already listening it no-ops.
7. Deliver to the user: post the URL
   `http://<host>:<port>/<slug>.html` (and/or attach the file). On Slack a link
   is best — mobile opens it in its in-app browser.

## HTML pattern (self-contained)
```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>TITLE</title>
  <style>/* inline, responsive, light or dark */</style>
</head>
<body>
  <header>...</header>
  <main>
    <section>overview</section>
    <section>key findings</section>
    <section>sources (cite as <a href>)</section>
  </main>
  <script>/* optional vanilla JS: tabs, filters */</script>
</body>
</html>
```
For visual polish on demand, load the `popular-web-designs` or `claude-design`
skill and apply a real design system.

## Serving (research-serve)
- `serve.py`: stdlib `http.server`, serves `$RESEARCH_DIR`, binds
  `$RESEARCH_HOST` (default 127.0.0.1) on `$RESEARCH_PORT` (default 8088).
- Phone access: run behind Tailscale with `RESEARCH_HOST=0.0.0.0`, then open
  `http://<tailscale-ip>:8088/`. Never expose publicly without auth.
- `start.sh [port]` launches in background, logs to `<skill-dir>/serve.log`.

## Architecture rules
- Never overwrite an existing `<slug>.html` without reading it first. New topic
  = new slug (date-prefixed avoids collisions).
- Cite sources inline — the report must be self-verifying.
- Keep it one file. No external CSS/JS except optional CDN charts.
- `index.json` is the only shared mutable file — read before patch, append only.
SKILL_EOF

# ---- serve.py ----
cat > "$SKILL_DIR/serve.py" <<'SERVE_EOF'
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
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
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
        pass


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
SERVE_EOF

# ---- start.sh ----
cat > "$SKILL_DIR/start.sh" <<'START_EOF'
#!/bin/bash
# Start the research-digest static server (idempotent).
# Usage: ./start.sh [port]   (default 8088, or $RESEARCH_PORT)
set -e
cd "$(dirname "$0")"
PORT="${1:-${RESEARCH_PORT:-8088}}"
HOST="${RESEARCH_HOST:-127.0.0.1}"

if command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "research-serve already listening on $PORT — leaving it running."
    exit 0
  fi
fi

mkdir -p "$HOME/research"
nohup python3 "$PWD/serve.py" "$PORT" > "$PWD/serve.log" 2>&1 &
echo "research-serve started (PID $!) on http://$HOST:$PORT"
echo "Logs: $PWD/serve.log"
START_EOF

chmod +x "$SKILL_DIR/start.sh" "$SKILL_DIR/serve.py"

# First-run: create vault + start server
mkdir -p "$RESEARCH_DIR"
( cd "$SKILL_DIR" && bash ./start.sh 8088 ) || true

echo
echo "════════════════════════════════════════════"
echo " ✓ research-digest installed"
echo "   Skill:  $SKILL_DIR"
echo "   Vault:  $RESEARCH_DIR"
echo "   Server: http://localhost:8088"
echo "════════════════════════════════════════════"
echo " Next: restart your Hermes profile so it loads the skill,"
echo " then say: 'Research X and make an HTML report.'"
PUB_INSTALL_EOF

cat > "$REPO_DIR/README.md" <<'PUB_README_EOF'
# hermes-skills

A personal tap of [Hermes Agent](https://github.com/NousResearch/hermes-agent) skills.

## Skills in this tap

| Skill | What it does |
|---|---|
| [`research-digest`](skills/research-digest/) | Turn a research request into a self-contained interactive HTML report, saved to `~/research/` and served on `http://localhost:8088` for viewing on any device (via Tailscale/LAN). Fixes the "wall of markdown in Slack" problem. |

## Install via Hermes skill tap (recommended)

```bash
hermes skills tap add <your-github-user>/hermes-skills
hermes skills install <your-github-user>/hermes-skills/research-digest
```

Then restart your profile and say:
> Research the differences between llama.cpp and vLLM and make an HTML report.

## Install directly (no Hermes CLI / manual)

```bash
curl -fsSL https://raw.githubusercontent.com/<your-github-user>/hermes-skills/main/install.sh | bash
```

`install.sh` is fully self-contained (embeds every file), creates
`~/.hermes/skills/research-digest/`, and starts the report server on port 8088.

## How `research-digest` works

1. Agent researches the topic with `web_search` + `web_extract`.
2. Writes one self-contained `YYYY-MM-DD-<slug>.html` report to `~/research/`.
3. Updates `~/research/index.json` (manifest).
4. Starts `research-serve` (port 8088, localhost by default).
5. Delivers the URL to you — open it in any browser (desktop or phone via Tailscale).

Security note: the report server has no auth. Keep it on `127.0.0.1` or behind
Tailscale (`RESEARCH_HOST=0.0.0.0`). Do not expose it to the public internet.

## License

MIT — reuse freely.
PUB_README_EOF

cat > "$REPO_DIR/.gitignore" <<'PUB_GITIGNORE_EOF'
# Ignore local vault contents and runtime artifacts
research/
serve.log
*.pyc
__pycache__/
.DS_Store
PUB_GITIGNORE_EOF


chmod +x "$REPO_DIR/install.sh" "$REPO_DIR/skills/research-digest/start.sh" "$REPO_DIR/skills/research-digest/serve.py"

cd "$REPO_DIR"
git init -q -b main 2>/dev/null || git init -q
# Set a repo-local identity only if the host has none — never touch global config.
if ! git config user.email >/dev/null 2>&1; then
  git config user.email "hermes-skills@localhost"
  git config user.name "Hermes Skills"
fi
git add -A
git commit -qm "Add research-digest skill tap"

# --- Publish -------------------------------------------------------------
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  GH_USER="$(gh api user -q .login)"
  echo "→ Publishing as $GH_USER"
  sed -i "s|<your-github-user>|$GH_USER|g" README.md
  git add README.md && git commit -qm "Set repo owner in README" || true
  gh repo create hermes-skills --public --source=. --push
  echo
  echo "✓ Done: https://github.com/$GH_USER/hermes-skills"
  echo "  Install with:"
  echo "    hermes skills tap add $GH_USER/hermes-skills"
  echo "    hermes skills install $GH_USER/hermes-skills/research-digest"
elif git remote get-url origin >/dev/null 2>&1; then
  echo "→ Pushing to existing remote"
  git push -u origin main
  echo "✓ Pushed. (README still has <your-github-user> placeholders — edit if needed.)"
else
  echo
  echo "⚠ No authenticated gh CLI and no origin remote found."
  echo "  The repo is ready at: $REPO_DIR"
  echo "  Push manually with:"
  echo "    cd $REPO_DIR"
  echo "    gh repo create hermes-skills --public --source=. --push"
  echo "  (or: git remote add origin <your-repo-url> && git push -u origin main)"
  exit 1
fi
