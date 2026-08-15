#!/bin/bash
# publish.sh — recreate the hermes-skills tap repo and push to GitHub.
# Generated from the verified source. Run ONCE on the host:
#   bash publish.sh [target-dir]   (default: $HOME/hermes-skills)
set -euo pipefail

REPO_DIR="${1:-$HOME/hermes-skills}"

echo "→ Creating repo at $REPO_DIR"
mkdir -p "$REPO_DIR/skills/research-digest"
mkdir -p "$REPO_DIR/skills/house-manager/references"
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

cat > "$REPO_DIR/skills/house-manager/SKILL.md" <<'PUB_HM_SKILL_EOF'
---
name: house-manager
description: "Daily house-helper briefing: chores by day + snack rotation."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [household, chores, house-helper, cron, briefing]
    related_skills: [personal-life-orchestration]
---

# House Manager

Daily briefing for the house helper: read the chore data file, work out what is due today, compose one clear message. Also governs how new chores get added (Ash dumps them in chat).

## When to Use
- Building or running the house-helper daily briefing (the cron job loads this skill)
- Ash dumps new chores: "add X", "we also need to Y"
- Any question about household chore scheduling for the helper

## Architecture (agreed with Ash — do not change casually)
Two layers, kept strictly separate:
1. **Data files, kept separate from the procedure (Ash-corrected: never baked into SKILL.md body):**
   - `references/chores.md` — the chore list only. Plain markdown, sections by area (`## Laundry`, `## Daycare`, `## Fridge`, `## House`, `## Meals`…), bullets as `- **Task name** — cadence. Detail/notes.` Editable directly on Ash's machine at `~/.hermes/skills/autonomous-ai-agents/house-manager/references/chores.md`.
   - `references/snacks.md` — rotation pool for daily packing, in its OWN file (Ash explicitly asked for this split: "add this to another snacks.md and then the skill can pick from this"). Holds the item pool + pairing rules; chores.md just points to it.
2. **This skill** — procedure only: where the data files live, how to compute today's list, message tone, delivery. NEVER bake chore data into SKILL.md — Ash explicitly asked why the task list would live in a skill; it shouldn't. Data goes in the editable markdown reference files.

Filesystem note: sandbox `/root` is a per-task MIRROR of the host home — `write_file`/`patch`/`terminal` writes do NOT reach Ash's machine. Authoritative writes go through `skill_manage` (and `memory`). Never write to `~/.hermes/` paths with sandbox tools.

## Adding chores (dump workflow)
1. Parse Ash's dump; don't ask anything that can be reasonably defaulted.
2. Patch `references/chores.md` (skill_manage action='patch', file_path='references/chores.md'), adding to the right section (create a new section if it's a new area).
3. Reply with a short echo ("how I read it back") + any scheduling calls made + "next batch?".
4. State interpretation of loose cadences and invite a veto: "every 2–3 days" → Mon/Wed/Fri; "as needed" → rides along with the related daily task line (e.g. paneer rides the daily fridge check); weekly with no day specified → default to Monday (clusters weekly deep-cleans) and say so; "whenever folding" fold-in rules → appear on the parent task's days (laundry days).
5. Respect hard vs soft tasks: Ash explicitly upgraded "clean the platform" from time-permitting to "required, not optional" — the message must state required tasks plainly and phrase soft ones as "if you have time". Never downgrade a required task.
6. Helper-facing conditional notes ("ask us", "check with me") MUST survive into the daily message — they are instructions to the helper, not metadata.

## Snack rotation (weekdays only, from snacks.md)
1. Only on weekdays (Mon–Fri) — no snack pack on weekends. Read `references/snacks.md` (via skill_view) pool; pick 2 different items for today.
2. Rules (follow snacks.md exactly): never repeat the previous day's pair; one vegetable + one nut/other — NEVER two vegetables on the same day (vegetable list is tagged in the file; avocado counts as fruit unless Ash says otherwise); if either pick is a small snack (pistachios, pumpkin seeds, makhana, puffs), add a third companion (one date, one anjeer, or raisins).
3. Make the rotation deterministic (e.g. keyed on day-of-year) so it survives restarts with no state file — no drift, no forgotten pairs.
4. Include picks in the briefing as "pack for Dhriti: X, Y".

## Daily run (cron)
1. Re-read the data files via `skill_view(name='house-manager', file_path='references/chores.md')` and `file_path='references/snacks.md'` — never trust a cached copy.
2. Compute due tasks for today, date-aware (weekday names, e.g. baby laundry on Sun/Wed).
3. Meals: dinner prep every day; lunch prep only on work-from-home days. Office days (no lunch prep): Monday & Thursday always; Tuesday/Wednesday vary — on Tue/Wed add a conditional line ("If we're going to office today: dinner prep only, no lunch prep"). On office days note the extra time and surface the optional tasks.
4. Pick today's 2 snacks per the rotation rules above.
5. Compose ONE warm, simple message in English: greeting + checklist of today's tasks, each a single actionable line; required tasks stated plainly, time-permitting tasks as "if you have time"; keep "ask us" conditionals as helper instructions; include the meal-prep line and snack picks at the end.
6. Deliver to the helper target — see Open decisions; never claim delivery without a verified target.

## Open decisions (as of 2026-08-15)
- **Helper delivery channel: UNDECIDED** — options: Slack DM/channel in this workspace, email, or relay via home channel C0BPTSL0K08. Cron created with deliver=origin for the test; production target pending Ash's answer.
- Send time default 07:30; tone warm & simple; language English. Helper's name not yet provided.
- Profile: deliberately DEFAULT profile — one cron job doesn't justify a second profile/gateway/bot. Revisit if household domains grow (meal planning, family calendar) → `hermes profile create household --clone`, move skill + job over.

## Build status
- `references/chores.md` — LIVE (Laundry / Daycare / Fridge / House / Meals sections; inventory snapshot in `references/current-chores.md`).
- `references/snacks.md` — LIVE (11-item pool, rotation + pairing rules).
- Cron job — created 2026-08-15, schedule 07:30 daily, skills=[house-manager], deliver=origin pending helper target; test run in progress. Production delivery target still needs Ash's answer (helper's channel/email).

## Pitfalls
- Never bake chore data into SKILL.md — data lives in chores.md only.
- Cron delivery is NOT automatic: verify the target (Slack id / email) and gateway before promising the helper receives anything (see personal-life-orchestration).
- Don't silently invent cadences — echo the interpretation and invite a veto.
- Sandbox /root is a per-task mirror: `write_file`/`patch`/`terminal` writes do NOT reach the host — use `skill_manage` for authoritative writes.
- Keep "ask us" notes intact in the composed message (delicates question, >2-day fridge items).

## Verification
- After editing chores.md: read it back; confirm sections parse.
- After creating the cron: `cronjob(action="run")` and show Ash the composed message for review before relying on it.
PUB_HM_SKILL_EOF

cat > "$REPO_DIR/skills/house-manager/references/chores.md" <<'PUB_HM_CHORES_EOF'
# House Chores

House task list for the daily house-helper briefing. The house-manager skill reads
this file each morning and picks what is due today. Sections grow as we add them.

_Last updated: 2026-08-15_

## Laundry

- **Baby laundry** — Sunday & Wednesday.
- **Daycare blanket wash** — Saturday. Remove the pillow before washing; wash the blanket on a delicate cycle, separate from the main load.
- **Our laundry** — Saturday. Can be combined with the blanket's delicate cycle; if there are any other delicate items to wash, ask us first whether to include them.
- **Sock placement** — Whenever folding laundry: all socks (Dhriti's and ours) go in the shoe stand downstairs.
- **Stairs pickup** — Daily. Any leftover baby dirty clothes on the stairs go into the laundry basket.

## Daycare

- **Spare outfit check** — Weekdays (Mon–Fri). For Dhriti: check the extra clothes bag inside the daycare bag and keep one set (t-shirt, pants, socks) in it.

## Fridge

- **Fridge check** — Daily. Anything older than 2 days: check with us first, then throw it out.
- **Coriander** — Every 2–3 days: cut/trim the coriander.
- **Paneer** — As needed: if 2% milk is in the fridge, make paneer with it whenever you get time.

## House

- **Tidy living room & toys** — Daily.
- **Sweep kitchen** — Daily.
- **Sweep rest of house** — Daily, if time permits.
- **Clean the platform** — Daily (required, not optional).
- **Wipe dining table & high chair** — Daily, quick wipe.
- **High chair wash** — Weekly (once a week, default: Monday).
- **Instant pot clean** — Weekly (once a week, default: Monday, alongside the high chair wash).

## Meals

- **Dinner prep** — Daily.
- **Lunch prep** — Only on work-from-home days (office days: dinner prep only). Office days are Monday and Thursday, plus one of Tuesday/Wednesday (varies week to week). On office days the helper has extra time to do other things.

## Snacks for Dhriti (pack 2 daily)

Rotation pool lives in `snacks.md` — the skill picks the day's items from it each weekday (nothing on weekends).
PUB_HM_CHORES_EOF

cat > "$REPO_DIR/skills/house-manager/references/snacks.md" <<'PUB_HM_SNACKS_EOF'
# Dhriti's Snacks (pack on weekdays)

Rotation pool for Dhriti's daycare packing. The house manager skill picks items
from this list every weekday for the briefing.

Rules:
- Pack only on weekdays (Mon–Fri); no snack pack on weekends.
- Pick 2 different items each day.
- Avoid repeating the previous day's pair.
- Generally one vegetable + one nut/other — never two vegetables on the same day. Vegetables: carrots, cucumber, beetroot.
- Small-snack rule: if either pick is a small snack (15 pistachios, 15 pumpkin seeds, makhana, puffs), add a third companion — one date, one anjeer (fig), or some raisins.
- Everything else (paneer cubes, carrots, cucumber, beetroot, avocado, anjeer, date) pairs freely as one of the two.

## Pool

- 15 pistachios
- 15 pumpkin seeds
- makhana
- very small cubes of paneer
- sliced steamed carrots
- sliced cucumbers
- steamed beetroot
- cubed avocado, big pieces
- one anjeer (fig)
- one date
- puffs
- some raisins
PUB_HM_SNACKS_EOF

cat > "$REPO_DIR/skills/house-manager/references/current-chores.md" <<'PUB_HM_CURRENT_EOF'
# Chore inventory snapshot (as of 2026-08-15)

Source of truth is `references/chores.md` + `references/snacks.md` inside this skill — this file is context for agents, not the live data.
Always re-read the live files before editing or composing the daily briefing.

## Laundry
- Baby laundry — Sunday & Wednesday
- Daycare blanket wash — Saturday: remove the pillow before washing; delicate cycle, separate from the main load
- Our laundry — Saturday: may join the blanket's delicate cycle; if there are other delicates, message must tell the helper to ASK Ash first
- Sock placement — whenever folding: ALL socks (Dhriti's and ours; Ash corrected "even our socks") go in the shoe stand downstairs
- Stairs pickup — daily: any baby clothes left on the stairs go into the laundry basket

## Daycare
- Spare outfit check — weekdays (Mon–Fri), for Dhriti: the extra clothes bag inside the daycare bag must hold one set (t-shirt, pants, socks)

## Fridge
- Fridge check — daily: anything older than 2 days → ASK Ash first, then discard
- Coriander — every 2–3 days, scheduled Mon/Wed/Fri (interpretation stated to Ash, open to veto)
- Paneer — as needed: if 2% milk is in the fridge, make paneer when time permits (rides the daily fridge-check line)

## House
- Tidy living room & toys — daily
- Sweep kitchen — daily
- Sweep rest of house — daily, if time permits (soft)
- Clean the platform — daily, REQUIRED (Ash: "that's not optional")
- Wipe dining table & high chair — daily, quick wipe
- High chair wash — weekly, defaulted to Monday (flagged for veto)
- Instant pot clean — weekly, defaulted to Monday alongside high chair (flagged for veto)

## Meals
- Dinner prep — daily
- Lunch prep — only on work-from-home days. Office days (dinner prep only): Monday & Thursday always; one of Tuesday/Wednesday varies week to week. On office days the helper has extra time → briefing surfaces optional tasks and a conditional line on Tue/Wed.

## Snacks for Dhriti (pack on weekdays)
Pool lives in `references/snacks.md` (12 items: pistachios, pumpkin seeds, makhana, paneer cubes, steamed carrots, cucumbers, beetroot, avocado, anjeer, date, puffs, raisins).
Rules: weekdays only; 2/day, no repeat of yesterday's pair, one vegetable + one nut/other, NEVER two veggies (veggies = carrots, cucumber, beetroot; avocado = fruit); small-snack picks (pistachios, pumpkin seeds, makhana, puffs) get a third companion (date, anjeer, or raisins).

## Names & open decisions
- Dhriti = Ash's daughter (daycare age; spelled D-H-R-I-T-I, Ash corrected the spelling). Helper's name: not yet provided.
- Helper delivery channel: UNDECIDED (Slack DM/channel, email, or relay via home channel C0BPTSL0K08).
- Defaults proposed: send 07:30, warm & simple tone, English — not yet confirmed by Ash.
- Profile: default profile by design; promote to a `household` profile only if the domain grows.
PUB_HM_CURRENT_EOF


cat > "$REPO_DIR/install.sh" <<'PUB_INSTALL_EOF'
#!/bin/bash
# install.sh — self-contained installer for ALL skills in this tap.
# No network needed: all files are embedded below.
# Run on the HOST (where Hermes lives):  bash install.sh
set -e
# ================= research-digest =================
SKILL_DIR="${HOME}/.hermes/skills/research-digest"
RESEARCH_DIR="${RESEARCH_DIR:-${HOME}/research}"

echo "→ Installing research-digest into $SKILL_DIR"
mkdir -p "$SKILL_DIR"

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
SERVE_EOF

cat > "$SKILL_DIR/start.sh" <<'START_EOF'
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
START_EOF

chmod +x "$SKILL_DIR/start.sh" "$SKILL_DIR/serve.py"

# First-run: create vault + start server
mkdir -p "$RESEARCH_DIR"
( cd "$SKILL_DIR" && bash ./start.sh 8088 ) || true

echo
echo " ✓ research-digest installed"
echo "   Skill:  $SKILL_DIR"
echo "   Vault:  $RESEARCH_DIR"
echo "   Server: http://localhost:8088"
# ================= house-manager =================
SKILL_DIR="${HOME}/.hermes/skills/house-manager"

echo "→ Installing house-manager into $SKILL_DIR"
mkdir -p "$SKILL_DIR/references"

cat > "$SKILL_DIR/SKILL.md" <<'HM_SKILL_EOF'
---
name: house-manager
description: "Daily house-helper briefing: chores by day + snack rotation."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [household, chores, house-helper, cron, briefing]
    related_skills: [personal-life-orchestration]
---

# House Manager

Daily briefing for the house helper: read the chore data file, work out what is due today, compose one clear message. Also governs how new chores get added (Ash dumps them in chat).

## When to Use
- Building or running the house-helper daily briefing (the cron job loads this skill)
- Ash dumps new chores: "add X", "we also need to Y"
- Any question about household chore scheduling for the helper

## Architecture (agreed with Ash — do not change casually)
Two layers, kept strictly separate:
1. **Data files, kept separate from the procedure (Ash-corrected: never baked into SKILL.md body):**
   - `references/chores.md` — the chore list only. Plain markdown, sections by area (`## Laundry`, `## Daycare`, `## Fridge`, `## House`, `## Meals`…), bullets as `- **Task name** — cadence. Detail/notes.` Editable directly on Ash's machine at `~/.hermes/skills/autonomous-ai-agents/house-manager/references/chores.md`.
   - `references/snacks.md` — rotation pool for daily packing, in its OWN file (Ash explicitly asked for this split: "add this to another snacks.md and then the skill can pick from this"). Holds the item pool + pairing rules; chores.md just points to it.
2. **This skill** — procedure only: where the data files live, how to compute today's list, message tone, delivery. NEVER bake chore data into SKILL.md — Ash explicitly asked why the task list would live in a skill; it shouldn't. Data goes in the editable markdown reference files.

Filesystem note: sandbox `/root` is a per-task MIRROR of the host home — `write_file`/`patch`/`terminal` writes do NOT reach Ash's machine. Authoritative writes go through `skill_manage` (and `memory`). Never write to `~/.hermes/` paths with sandbox tools.

## Adding chores (dump workflow)
1. Parse Ash's dump; don't ask anything that can be reasonably defaulted.
2. Patch `references/chores.md` (skill_manage action='patch', file_path='references/chores.md'), adding to the right section (create a new section if it's a new area).
3. Reply with a short echo ("how I read it back") + any scheduling calls made + "next batch?".
4. State interpretation of loose cadences and invite a veto: "every 2–3 days" → Mon/Wed/Fri; "as needed" → rides along with the related daily task line (e.g. paneer rides the daily fridge check); weekly with no day specified → default to Monday (clusters weekly deep-cleans) and say so; "whenever folding" fold-in rules → appear on the parent task's days (laundry days).
5. Respect hard vs soft tasks: Ash explicitly upgraded "clean the platform" from time-permitting to "required, not optional" — the message must state required tasks plainly and phrase soft ones as "if you have time". Never downgrade a required task.
6. Helper-facing conditional notes ("ask us", "check with me") MUST survive into the daily message — they are instructions to the helper, not metadata.

## Snack rotation (weekdays only, from snacks.md)
1. Only on weekdays (Mon–Fri) — no snack pack on weekends. Read `references/snacks.md` (via skill_view) pool; pick 2 different items for today.
2. Rules (follow snacks.md exactly): never repeat the previous day's pair; one vegetable + one nut/other — NEVER two vegetables on the same day (vegetable list is tagged in the file; avocado counts as fruit unless Ash says otherwise); if either pick is a small snack (pistachios, pumpkin seeds, makhana, puffs), add a third companion (one date, one anjeer, or raisins).
3. Make the rotation deterministic (e.g. keyed on day-of-year) so it survives restarts with no state file — no drift, no forgotten pairs.
4. Include picks in the briefing as "pack for Dhriti: X, Y".

## Daily run (cron)
1. Re-read the data files via `skill_view(name='house-manager', file_path='references/chores.md')` and `file_path='references/snacks.md'` — never trust a cached copy.
2. Compute due tasks for today, date-aware (weekday names, e.g. baby laundry on Sun/Wed).
3. Meals: dinner prep every day; lunch prep only on work-from-home days. Office days (no lunch prep): Monday & Thursday always; Tuesday/Wednesday vary — on Tue/Wed add a conditional line ("If we're going to office today: dinner prep only, no lunch prep"). On office days note the extra time and surface the optional tasks.
4. Pick today's 2 snacks per the rotation rules above.
5. Compose ONE warm, simple message in English: greeting + checklist of today's tasks, each a single actionable line; required tasks stated plainly, time-permitting tasks as "if you have time"; keep "ask us" conditionals as helper instructions; include the meal-prep line and snack picks at the end.
6. Deliver to the helper target — see Open decisions; never claim delivery without a verified target.

## Open decisions (as of 2026-08-15)
- **Helper delivery channel: UNDECIDED** — options: Slack DM/channel in this workspace, email, or relay via home channel C0BPTSL0K08. Cron created with deliver=origin for the test; production target pending Ash's answer.
- Send time default 07:30; tone warm & simple; language English. Helper's name not yet provided.
- Profile: deliberately DEFAULT profile — one cron job doesn't justify a second profile/gateway/bot. Revisit if household domains grow (meal planning, family calendar) → `hermes profile create household --clone`, move skill + job over.

## Build status
- `references/chores.md` — LIVE (Laundry / Daycare / Fridge / House / Meals sections; inventory snapshot in `references/current-chores.md`).
- `references/snacks.md` — LIVE (11-item pool, rotation + pairing rules).
- Cron job — created 2026-08-15, schedule 07:30 daily, skills=[house-manager], deliver=origin pending helper target; test run in progress. Production delivery target still needs Ash's answer (helper's channel/email).

## Pitfalls
- Never bake chore data into SKILL.md — data lives in chores.md only.
- Cron delivery is NOT automatic: verify the target (Slack id / email) and gateway before promising the helper receives anything (see personal-life-orchestration).
- Don't silently invent cadences — echo the interpretation and invite a veto.
- Sandbox /root is a per-task mirror: `write_file`/`patch`/`terminal` writes do NOT reach the host — use `skill_manage` for authoritative writes.
- Keep "ask us" notes intact in the composed message (delicates question, >2-day fridge items).

## Verification
- After editing chores.md: read it back; confirm sections parse.
- After creating the cron: `cronjob(action="run")` and show Ash the composed message for review before relying on it.
HM_SKILL_EOF

cat > "$SKILL_DIR/references/chores.md" <<'HM_CHORES_EOF'
# House Chores

House task list for the daily house-helper briefing. The house-manager skill reads
this file each morning and picks what is due today. Sections grow as we add them.

_Last updated: 2026-08-15_

## Laundry

- **Baby laundry** — Sunday & Wednesday.
- **Daycare blanket wash** — Saturday. Remove the pillow before washing; wash the blanket on a delicate cycle, separate from the main load.
- **Our laundry** — Saturday. Can be combined with the blanket's delicate cycle; if there are any other delicate items to wash, ask us first whether to include them.
- **Sock placement** — Whenever folding laundry: all socks (Dhriti's and ours) go in the shoe stand downstairs.
- **Stairs pickup** — Daily. Any leftover baby dirty clothes on the stairs go into the laundry basket.

## Daycare

- **Spare outfit check** — Weekdays (Mon–Fri). For Dhriti: check the extra clothes bag inside the daycare bag and keep one set (t-shirt, pants, socks) in it.

## Fridge

- **Fridge check** — Daily. Anything older than 2 days: check with us first, then throw it out.
- **Coriander** — Every 2–3 days: cut/trim the coriander.
- **Paneer** — As needed: if 2% milk is in the fridge, make paneer with it whenever you get time.

## House

- **Tidy living room & toys** — Daily.
- **Sweep kitchen** — Daily.
- **Sweep rest of house** — Daily, if time permits.
- **Clean the platform** — Daily (required, not optional).
- **Wipe dining table & high chair** — Daily, quick wipe.
- **High chair wash** — Weekly (once a week, default: Monday).
- **Instant pot clean** — Weekly (once a week, default: Monday, alongside the high chair wash).

## Meals

- **Dinner prep** — Daily.
- **Lunch prep** — Only on work-from-home days (office days: dinner prep only). Office days are Monday and Thursday, plus one of Tuesday/Wednesday (varies week to week). On office days the helper has extra time to do other things.

## Snacks for Dhriti (pack 2 daily)

Rotation pool lives in `snacks.md` — the skill picks the day's items from it each weekday (nothing on weekends).
HM_CHORES_EOF

cat > "$SKILL_DIR/references/snacks.md" <<'HM_SNACKS_EOF'
# Dhriti's Snacks (pack on weekdays)

Rotation pool for Dhriti's daycare packing. The house manager skill picks items
from this list every weekday for the briefing.

Rules:
- Pack only on weekdays (Mon–Fri); no snack pack on weekends.
- Pick 2 different items each day.
- Avoid repeating the previous day's pair.
- Generally one vegetable + one nut/other — never two vegetables on the same day. Vegetables: carrots, cucumber, beetroot.
- Small-snack rule: if either pick is a small snack (15 pistachios, 15 pumpkin seeds, makhana, puffs), add a third companion — one date, one anjeer (fig), or some raisins.
- Everything else (paneer cubes, carrots, cucumber, beetroot, avocado, anjeer, date) pairs freely as one of the two.

## Pool

- 15 pistachios
- 15 pumpkin seeds
- makhana
- very small cubes of paneer
- sliced steamed carrots
- sliced cucumbers
- steamed beetroot
- cubed avocado, big pieces
- one anjeer (fig)
- one date
- puffs
- some raisins
HM_SNACKS_EOF

cat > "$SKILL_DIR/references/current-chores.md" <<'HM_CURRENT_EOF'
# Chore inventory snapshot (as of 2026-08-15)

Source of truth is `references/chores.md` + `references/snacks.md` inside this skill — this file is context for agents, not the live data.
Always re-read the live files before editing or composing the daily briefing.

## Laundry
- Baby laundry — Sunday & Wednesday
- Daycare blanket wash — Saturday: remove the pillow before washing; delicate cycle, separate from the main load
- Our laundry — Saturday: may join the blanket's delicate cycle; if there are other delicates, message must tell the helper to ASK Ash first
- Sock placement — whenever folding: ALL socks (Dhriti's and ours; Ash corrected "even our socks") go in the shoe stand downstairs
- Stairs pickup — daily: any baby clothes left on the stairs go into the laundry basket

## Daycare
- Spare outfit check — weekdays (Mon–Fri), for Dhriti: the extra clothes bag inside the daycare bag must hold one set (t-shirt, pants, socks)

## Fridge
- Fridge check — daily: anything older than 2 days → ASK Ash first, then discard
- Coriander — every 2–3 days, scheduled Mon/Wed/Fri (interpretation stated to Ash, open to veto)
- Paneer — as needed: if 2% milk is in the fridge, make paneer when time permits (rides the daily fridge-check line)

## House
- Tidy living room & toys — daily
- Sweep kitchen — daily
- Sweep rest of house — daily, if time permits (soft)
- Clean the platform — daily, REQUIRED (Ash: "that's not optional")
- Wipe dining table & high chair — daily, quick wipe
- High chair wash — weekly, defaulted to Monday (flagged for veto)
- Instant pot clean — weekly, defaulted to Monday alongside high chair (flagged for veto)

## Meals
- Dinner prep — daily
- Lunch prep — only on work-from-home days. Office days (dinner prep only): Monday & Thursday always; one of Tuesday/Wednesday varies week to week. On office days the helper has extra time → briefing surfaces optional tasks and a conditional line on Tue/Wed.

## Snacks for Dhriti (pack on weekdays)
Pool lives in `references/snacks.md` (12 items: pistachios, pumpkin seeds, makhana, paneer cubes, steamed carrots, cucumbers, beetroot, avocado, anjeer, date, puffs, raisins).
Rules: weekdays only; 2/day, no repeat of yesterday's pair, one vegetable + one nut/other, NEVER two veggies (veggies = carrots, cucumber, beetroot; avocado = fruit); small-snack picks (pistachios, pumpkin seeds, makhana, puffs) get a third companion (date, anjeer, or raisins).

## Names & open decisions
- Dhriti = Ash's daughter (daycare age; spelled D-H-R-I-T-I, Ash corrected the spelling). Helper's name: not yet provided.
- Helper delivery channel: UNDECIDED (Slack DM/channel, email, or relay via home channel C0BPTSL0K08).
- Defaults proposed: send 07:30, warm & simple tone, English — not yet confirmed by Ash.
- Profile: default profile by design; promote to a `household` profile only if the domain grows.
HM_CURRENT_EOF

echo
echo " ✓ house-manager installed"
echo "   Skill:  $SKILL_DIR"
echo "   Data:   $SKILL_DIR/references/chores.md + snacks.md (edit these directly)"

echo
echo "════════════════════════════════════════════"
echo " ✓ Tap installed"
echo " Next: restart your Hermes profile so it loads the skills,"
echo " then say: 'Research X and make an HTML report.' (research-digest)"
echo "      or: 'Run the house briefing.' (house-manager)"
echo "════════════════════════════════════════════"

PUB_INSTALL_EOF

cat > "$REPO_DIR/README.md" <<'PUB_README_EOF'
# hermes-skills

A personal tap of [Hermes Agent](https://github.com/NousResearch/hermes-agent) skills.

## Skills in this tap

| Skill | What it does |
|---|---|
| [`research-digest`](skills/research-digest/) | Turn a research request into a self-contained interactive HTML report, saved to `~/research/` and served on `http://localhost:8088` for viewing on any device (via Tailscale/LAN). Fixes the "wall of markdown in Slack" problem. |
| [`house-manager`](skills/house-manager/) | Daily house-helper briefing: reads the chore list (`references/chores.md`) and Dhriti's snack rotation pool (`references/snacks.md`), works out what's due on the current weekday, and composes one warm, short message. Both data files are plain markdown and editable directly. |

## Install via Hermes skill tap (recommended)

```bash
hermes skills tap add ashuven63/hermes-skills
hermes skills install ashuven63/hermes-skills/research-digest
hermes skills install ashuven63/hermes-skills/house-manager
```

Then restart your profile and say:
> Research the differences between llama.cpp and vLLM and make an HTML report.

or for the house manager:
> Run today's house briefing.

The `house-manager` skill ships with its data files as references
(`chores.md` + `snacks.md`) — edit those directly to change the chores;
the skill itself never needs touching.

## Install directly (no Hermes CLI / manual)

```bash
curl -fsSL https://raw.githubusercontent.com/ashuven63/hermes-skills/main/install.sh | bash
```

`install.sh` is fully self-contained (embeds every file) and installs all skills in this tap:
`~/.hermes/skills/research-digest/` (starts the report server on port 8088) and
`~/.hermes/skills/house-manager/` (with its `references/chores.md` + `snacks.md` data files).

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
git commit -qm "Add research-digest + house-manager skill taps"

# --- Publish -------------------------------------------------------------
if git remote get-url origin >/dev/null 2>&1; then
  echo "→ Pushing to existing remote"
  git push -u origin main
  echo "✓ Pushed."
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  GH_USER="$(gh api user -q .login)"
  echo "→ Publishing as $GH_USER"
  sed -i "s|<your-github-user>|$GH_USER|g" README.md
  git add README.md && git commit -qm "Set repo owner in README" || true
  if gh repo view "$GH_USER/hermes-skills" >/dev/null 2>&1; then
    git remote add origin "https://github.com/$GH_USER/hermes-skills.git"
    git push -u origin main
  else
    gh repo create hermes-skills --public --source=. --push
  fi
  echo
  echo "✓ Done: https://github.com/$GH_USER/hermes-skills"
  echo "  Install with:"
  echo "    hermes skills tap add $GH_USER/hermes-skills"
  echo "    hermes skills install $GH_USER/hermes-skills/research-digest"
  echo "    hermes skills install $GH_USER/hermes-skills/house-manager"
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

