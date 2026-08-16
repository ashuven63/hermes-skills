# hermes-skills

A personal tap of [Hermes Agent](https://github.com/NousResearch/hermes-agent) skills.

## Skills in this tap

| Skill | What it does |
|---|---|
| [`research-digest`](skills/research-digest/) | Turn a research request into a self-contained interactive HTML report, saved to `~/research/` and served on `http://localhost:8088` for viewing on any device (via Tailscale/LAN). Fixes the "wall of markdown in Slack" problem. |
| [`house-manager`](skills/house-manager/) | Daily house-helper briefing: reads the chore list (`references/chores.md`) and Dhriti's snack rotation pool (`references/snacks.md`), works out what's due on the current weekday, and composes one warm, short message. Both data files are plain markdown and editable directly. |
| [`obsidian-vault-memory`](skills/obsidian-vault-memory/) | Persistent long-term memory via an Obsidian vault: daily notes (append-only timeline), System/Assistant living files (context/preferences/environment), content routing, wiki-link hygiene. Scaffold with `skills/obsidian-vault-memory/vault-scaffold.sh`. |

## Install via Hermes skill tap (recommended)

```bash
hermes skills tap add ashuven63/hermes-skills
hermes skills install ashuven63/hermes-skills/research-digest
hermes skills install ashuven63/hermes-skills/house-manager
hermes skills install ashuven63/hermes-skills/obsidian-vault-memory
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

## Obsidian vault memory setup

```bash
# 1. On the host: scaffold the vault (adjust path)
VAULT_PATH=/root/vault bash skills/obsidian-vault-memory/vault-scaffold.sh

# 2. Point Hermes at it
echo 'OBSIDIAN_VAULT_PATH=/root/vault' >> ~/.hermes/.env

# 3. Install the skill (if not using the tap flow above)
hermes skills install ashuven63/hermes-skills/obsidian-vault-memory
```

Sync to your local machine (recommended: Syncthing — bidirectional, real-time):

```bash
sudo apt-get install -y syncthing
sudo systemctl enable --now syncthing@$(whoami)
# GUI on http://127.0.0.1:8384 — share the vault folder with your devices
```

Phone access: Android = Syncthing app; iPhone = Mobius Sync (paid). Both work
over Tailscale if the server is on a tailnet. Add a `.stignore` for
`.obsidian/workspace.json` + `.obsidian/cache/` to avoid sync churn.

## License

MIT — reuse freely.
