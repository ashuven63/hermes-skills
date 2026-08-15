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
