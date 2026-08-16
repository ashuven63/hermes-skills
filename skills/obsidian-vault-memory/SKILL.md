---
name: obsidian-vault-memory
description: "Obsidian vault memory: daily notes, living files, routing."
---

# Obsidian Vault Memory

The vault is persistent long-term memory. Three tiers:

- **Tier 1 — Hot memory**: `MEMORY.md` / `USER.md` in `~/.hermes/memories/`
  (injected every turn, kept under ~4000 chars). Active projects, recent
  corrections, preferences, procedural quirks.
- **Tier 2 — Vault living files**: `System/Assistant/{context,preferences,
  environment}.md`. Stable reference, read on demand when deeper context is
  needed. When hot memory approaches capacity, promote stable entries here.
- **Tier 3 — Daily notes**: `Daily/YYYY-MM-DD.md`, append-only timestamped
  timeline. Search these to recall what happened on a given date.

## Vault path

Vault root = `$OBSIDIAN_VAULT_PATH` (from `~/.hermes/.env`), else
`~/vault`. Resolve it to a concrete absolute path before any file tool call.

## Structure

```
Vault/
├── Daily/                    # YYYY-MM-DD.md daily notes — append-only
├── System/Assistant/
│   ├── context.md            # operations, health, family overview
│   ├── preferences.md        # communication style, delivery rules
│   ├── environment.md        # hardware, services, known issues
│   └── logs/issues-fixes-log.md
├── Work/Business/            # work documents, reports, logs
├── Personal/Projects/        # side projects, personal tracking
├── People/                   # contacts, relationships, MOC
└── Inbox/                    # unclassified incoming — file later
```

## Daily notes

- Create `Daily/YYYY-MM-DD.md` each day if it does not exist.
- Frontmatter: `date: YYYY-MM-DD`, `type: daily`, `tags: [daily]`.
- Sections in order: `## Tasks`, `## Schedule`, `## Log`, `## Wins`, `## Context`.
- Tasks use checkboxes with priorities: `- [ ] Task (p2)`.
- Log entries: `- HH:MM AM/PM — what happened`.
- Wins: `✅ Task description`.
- **APPEND ONLY** — never delete content from daily notes.

## Content routing

When the user says "log it" / "save it", route by type:

- Operational events (meetings, calls, decisions) → today's Daily note `## Log`
- System issues / technical fixes → `System/Assistant/logs/issues-fixes-log.md`
- Learned corrections / preferences → hot memory (or vault if stable)
- Recurring workflows → save as a reusable skill
- Unknown incoming → `Inbox/` until classified

## Vault hygiene

- Use wiki-links: `[[People/Name]]`, `[[Daily/2026-04-23]]`. Build the link
  graph — every person, decision, and file mentioned should be linked.
- Flag orphaned notes (no incoming links) unprompted.
- Never delete vault content without explicit user confirmation.
- Prefer file tools (`read_file`, `write_file`, `patch`, `search_files`) with
  resolved absolute paths; vault paths may contain spaces.

## Weekly / monthly maintenance

- Weekly: check for orphaned notes; review MEMORY.md and prune stale entries;
  promote entries if MEMORY.md exceeds ~4000 chars.
- Monthly: audit folder structure; refresh System/Assistant files; review the
  issues log for recurring patterns worth turning into skills.
- On a breakage: log it in issues-fixes-log.md; if the fix is recurring, save a
  skill; update environment.md with the new known-issue pattern.
