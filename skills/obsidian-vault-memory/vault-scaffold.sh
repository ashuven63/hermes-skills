#!/bin/bash
# vault-scaffold.sh — create the Obsidian long-term-memory vault structure.
# Run ONCE on the HOST (Hetzner) where Hermes lives:
#   VAULT_PATH=/root/vault bash vault-scaffold.sh
set -e

VAULT_PATH="${VAULT_PATH:?Set VAULT_PATH, e.g. VAULT_PATH=/root/vault}"
TODAY="$(date +%Y-%m-%d)"

echo "→ Scaffolding vault at $VAULT_PATH"
mkdir -p "$VAULT_PATH"/{Daily,System/Assistant/logs,Work/Business,Personal/Projects,People,Inbox}

# --- System/Assistant/context.md ---
cat > "$VAULT_PATH/System/Assistant/context.md" <<'EOF'
# Assistant — Context

Current life situation, health protocols, and active things to track.
Read when context matters for decisions or advice.

---

## Operations

- Describe your main work or business here
- Note any secondary projects or side operations

## Health

- Goals and baselines
- Any recurring protocols or reminders

## Family

- Key people and relationships
- Link to People/ folder for details

## Work Dependencies

- Who you wait on for approvals or sign-offs
- Blockers and their schedules

## Location & Timezone

- Home address (optional)
- Timezone
- Weather location

---

*Last updated: YYYY-MM-DD*
EOF

# --- System/Assistant/preferences.md ---
cat > "$VAULT_PATH/System/Assistant/preferences.md" <<'EOF'
# Assistant — Preferences

How you like things done. Read this when unsure about tone, format, or approach.

---

## Communication

- Concise, direct. Dry wit welcome. Never sycophantic.
- One clear sentence beats three hedged ones.
- When something is urgent, say so plainly.

## Operations Separation

- Keep work and personal clearly separated
- Never mix contexts without explicit labeling

## Agenda & Briefings

- Priority ordering: Due today > Active/P1 > Bills > Upcoming
- Morning brief: always read from actual daily note. Never show template placeholders.

## Task Management

- Every task completion paired with a log entry in daily note
- EOD wrap-ups sourced from daily note log

## Delivery Preferences

- Where should scheduled summaries go? (email, messaging app, etc.)

## Session Style

- Continuous same-session conversations or fresh starts each day?

---

*Last updated: YYYY-MM-DD*
EOF

# --- System/Assistant/environment.md ---
cat > "$VAULT_PATH/System/Assistant/environment.md" <<'EOF'
# Assistant — Environment & Technical Setup

Hardware, tools, quirks, and gotchas. Read when troubleshooting or configuring.

---

## Hardware

- Primary machine and specs
- Any secondary devices or servers

## Services

- Key services, ports, and endpoints
- API configurations

## Key Paths

 Resource | Path
----------|------
 Vault | VAULT_PATH_PLACEHOLDER
 Daily notes | VAULT_PATH_PLACEHOLDER/Daily/YYYY-MM-DD.md

## Known Issues & Patterns

- Document any recurring problems and their fixes here

---

*Last updated: YYYY-MM-DD*
EOF
sed -i "s|VAULT_PATH_PLACEHOLDER|$VAULT_PATH|g" "$VAULT_PATH/System/Assistant/environment.md"

# --- System/Assistant/logs/issues-fixes-log.md ---
cat > "$VAULT_PATH/System/Assistant/logs/issues-fixes-log.md" <<'EOF'
# Issues & Fixes Log

Append-only record of system issues, technical failures, and their resolutions.

Format: Symptom → Root Cause → Fix → Status

---

*No entries yet.*
EOF

# --- People/MOC.md ---
cat > "$VAULT_PATH/People/MOC.md" <<'EOF'
# People — Map of Content

Contacts and relationships. Each person gets their own note in this folder.

---

## Family

- [[People/Partner]] — spouse/partner
- [[People/Child]] — children

## Work

- [[People/Colleague]] — key colleagues

## Personal

- [[People/Friend]] — friends and acquaintances

---

*Last updated: YYYY-MM-DD*
EOF

# --- Today's daily note ---
if [ ! -f "$VAULT_PATH/Daily/$TODAY.md" ]; then
cat > "$VAULT_PATH/Daily/$TODAY.md" <<EOF
---
date: $TODAY
type: daily
tags: [daily]
---

## Tasks — $TODAY

### Work

- [ ] Task description (p2)

### Personal

- [ ] Personal task (p4)

### Overdue

None

### Waiting / Blocked

None

## Schedule — $TODAY

- 09:00 AM — Morning meeting

## Log

- $(date '+%I:%M %p') — Started daily note

## Wins — $TODAY

## Context

- People: 
- Decisions: None
- Files: None
EOF
echo "→ Created Daily/$TODAY.md"
fi

echo
echo "═══════════════════════════════════════════"
echo " ✓ Vault scaffolded at $VAULT_PATH"
echo "   Next: add this line to ~/.hermes/.env on the host:"
echo "   OBSIDIAN_VAULT_PATH=$VAULT_PATH"
echo "   Then install the obsidian-vault-memory skill (see README)."
echo "═══════════════════════════════════════════"
