# Schedule — compaction routine + autopilot dispatch

The schedule step offers a recurring **memory-inbox compaction** routine.
`inbox/` ships in every preset (it's the single freeform-capture file),
so this offer always applies.

The SKILL.md owns the orchestration (whether to run the step, persist
`state.scheduled`); this file owns the routine's command body, the
cadence, and the dispatch logic.

---

## Why autopilot, not `/schedule`?

Same reasoning as `install-recipes/references/schedule.md`: `/schedule`
routines run as **remote agents** on Anthropic's infrastructure. They
have no path to the project's local `memory/` folder or `.claude/commands/`.
A compaction routine has to read and rewrite local files, so it must run
locally.

`/cos-bot:autopilot` is the local-runner equivalent: it scaffolds a
self-rescheduling slash command that runs on the user's machine via
`nohup sleep N && claude -p ...`, survives terminal exit, and can post a
summary to the user's Telegram bot. See
`plugins/cos-bot/skills/autopilot/SKILL.md`.

---

## The compaction command

`/cos-bot:autopilot` arms an existing slash command — it requires a
recipe file at `<project>/.claude/commands/<task>.md`. So the schedule
step first **writes the compaction command**, then arms autopilot on it.

Write this body to `<project>/.claude/commands/compact-memory.md` (via
the `Write` tool, skip-if-exists like every other write in this skill):

````markdown
---
description: Compact the Markdown memory inbox into durable memory files.
---

# Compact memory inbox

Read `PROTOCOL.md` and `memory/MEMORY.md` first.

1. Read the current monthly inbox file (`memory/inbox/<current YYYY-MM>.md`).
   If it doesn't exist or has no entries beyond the template, stop —
   nothing to compact.
2. For each entry, decide its durable home: `decisions.md`, `workflows.md`,
   a `projects/` / `people/` / `companies/` file, or `active.md`. Create
   entity files as needed.
3. Move durable items there as compact Markdown. Delete temporary items.
   Move anything stale-but-historical to `memory/archive/`.
4. Update `memory/active.md` if priorities or open loops changed.
5. Leave the inbox file with just its header and the current date.
6. Post a 2–3 line summary of what moved where to the user's Telegram chat.

Keep the final memory short. Never overwrite unrelated content — only
touch what you're compacting.
````

`compact-memory` is a normal project command after this — the user can
also run `/compact-memory` by hand any time.

---

## Cadence

Memory-inbox compaction is a low-frequency housekeeping task. Offer two
cadences via the offer Q&A; default to weekly.

| Choice | Autopilot cadence spec |
|---|---|
| **Weekly** (recommended) | `at 17:00 Fri` |
| **Monthly** | `at 17:00` on the 1st — pass as `adaptive` with a 1-per-month note, or let the user free-text it |
| **Not now** | skip — print the paste-able command for later |

Weekly Friday-evening is the sensible default: a week's worth of inbox
notes is enough to be worth compacting, not so much that it piles up.

---

## Offer Q&A

One `AskUserQuestion` (single-select):

> Memory inboxes pile up. Want a recurring routine that compacts
> `memory/inbox/` into your durable memory files and DMs you a summary?
> Runs locally, survives terminal exit, reschedules itself.
>
> - **Weekly — Friday 5pm** (recommended)
> - **Monthly — 1st of the month**
> - **Not now** — I'll arm it later

If "Not now," skip to the paste-able-command fallback below.

---

## Authorization

Arming autopilot needs a nested `claude -p` with
`--permission-mode bypassPermissions`. Get explicit authorization first
(mirrors `install-recipes/references/schedule.md`):

> To arm the routine I need to spawn a nested `claude -p` with
> `--permission-mode bypassPermissions` so it runs without an approval
> prompt. Authorize?
>
> - **Yes — use claude -p with bypassPermissions**
> - **No — I'll run /cos-bot:autopilot myself** (I'll print the command)

If **yes**, dispatch:

```
printf '/cos-bot:autopilot /compact-memory <cadence spec> stop_by <ISO date 90 days out>\n' \
  | claude --permission-mode bypassPermissions -p
```

Example (weekly choice, 90 days out from 2026-05-14):

```
printf '/cos-bot:autopilot /compact-memory at 17:00 Fri stop_by 2026-08-12\n' \
  | claude --permission-mode bypassPermissions -p
```

If **no**, print the exact command for the user to paste:

```
/cos-bot:autopilot /compact-memory at 17:00 Fri stop_by 2026-08-12
```

Persist `state.scheduled = true` on a successful arm (or on printing the
fallback command — the offer was made either way). Then
`state.step = "done"`.

---

## Implementation notes

- **Slash commands aren't tool calls.** A running model can't dispatch
  `/cos-bot:autopilot` directly — the nested `claude -p
  --permission-mode bypassPermissions` pattern is the canonical
  workaround. Get authorization first; fall through to a paste-able
  command if the nested call misbehaves.
- **`bypassPermissions` on nested calls is gated.** The harness denies
  it on child agents unless explicitly authorized in the parent session.
  The authorization question above is on the record — don't assume it
  carries over from a prior run.
- **The autopilot installs a supervisor automatically.** The first
  `/cos-bot:autopilot` arm writes a health-check supervisor. This skill
  doesn't need to mention it; autopilot's own confirm message does.
- **`compact-memory.md` is written even on "No".** The command file is
  the durable artifact; arming is optional. A user who picks "Not now"
  still gets `/compact-memory` to run by hand.
