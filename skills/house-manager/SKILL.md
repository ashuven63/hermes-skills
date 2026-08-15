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
