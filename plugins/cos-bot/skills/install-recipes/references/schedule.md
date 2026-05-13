# Schedule — autopilot mapping + nested dispatch

The schedule step offers cadence setup for any recipes whose
`schedule` knob is **not** `On-demand only`. cos-bot recipes are
**local** — they post through the user's Telegram bot (which only the
local machine can reach) and dispatch via local `claude -p`. So the
default mechanism here is `/cos-bot:autopilot` (local, self-
rescheduling), not `/schedule` (remote agent).

The SKILL.md owns the orchestration (decide whether to run this step,
which recipes are eligible, persist `state.scheduled`); this file owns
the cadence table and the dispatch logic.

---

## Why autopilot, not `/schedule`?

`/schedule` routines execute as remote agents on Anthropic's
infrastructure. They have **no path to** the user's local Telegram
bot (`~/.claude/channels/telegram/`), can't run local `claude -p`, and
can't read the project's `.claude/commands/`. Every cos-bot recipe
needs at least one of those. So `/schedule` is fundamentally the wrong
mechanism for these recipes.

`/cos-bot:autopilot` is the local-runner equivalent: it scaffolds a
self-rescheduling slash command that runs on the user's machine via
`nohup sleep N && claude -p ...`, survives terminal exit, supports
adaptive cadence, and can talk to the local Telegram bot. See
`/plugins/cos-bot/skills/autopilot/SKILL.md` for the details.

Use `/schedule` only when the user is explicitly asking for a remote
agent (e.g. "I want this to run even when my laptop is asleep").

---

## Cadence mapping (autopilot)

Map options to the literal `/cos-bot:autopilot` arguments:

| Slug | Schedule choice | Autopilot cadence spec |
|---|---|---|
| `prep` | Q-dispatcher | `daily 9am` (the prep recipe self-filters by today's meetings) |
| `prep` | D-loop | `every 15m` with `stop_by` end-of-day (interval auto-resets at midnight) |
| `inbox-triage` | 11+3 | `at 11:00,15:00 weekdays` |
| `inbox-triage` | 3 only | `at 15:00 weekdays` |
| `awaiting` | Tue+Thu | `at 10:00 Tue,Thu` |

`/who` and `/catchup` are always on-demand (no schedule offer).

**Runner name = slug.** The autopilot writes to
`~/.claude/commands/<slug>-autopilot.md`. The user invokes the
underlying recipe via its original slug (`/prep`, `/inbox-triage`,
etc.); the autopilot runner is what reschedules itself.

---

## Offer Q&A

If at least one recipe in `state.selected` has a non-`On-demand`
schedule, ask via `AskUserQuestion` (multi-select):

> Put any of these on autopilot now? (Runs locally — fires the recipe,
> DMs the result to your Telegram, schedules its own next run. Survives
> terminal exit. You can re-run `/cos-bot:autopilot` later for any you
> skip.)
>
> - `/prep` — daily 9am
> - `/inbox-triage` — `<chosen cadence>`
> - `/awaiting` — Tue + Thu 10am
> - **None — I'll arm manually later**

If the list is empty, skip this step entirely.

---

## Authorization

For each selected recipe, dispatch `/cos-bot:autopilot` via a nested
`claude -p` call, **after explicit authorization** (mirrors
cos-bot:setup step 4):

> To arm the autopilot, I need to spawn a nested `claude -p` with
> `--permission-mode bypassPermissions` so it can run without an
> approval prompt for each recipe. Authorize?
>
> - **Yes — use claude -p with bypassPermissions**
> - **No — I'll run /cos-bot:autopilot myself** (I'll print the exact
>   commands)

If yes, for each scheduled recipe, run:

```
printf '/cos-bot:autopilot /<slug> <cadence spec> stop_by <ISO date 30 days out>\n' \
  | claude --permission-mode bypassPermissions -p
```

Example for `inbox-triage` with the 11+3 choice:

```
printf '/cos-bot:autopilot /inbox-triage at 11:00,15:00 weekdays stop_by 2026-06-13\n' \
  | claude --permission-mode bypassPermissions -p
```

If no, print the exact commands the user can paste:

```
/cos-bot:autopilot /inbox-triage at 11:00,15:00 weekdays stop_by 2026-06-13
/cos-bot:autopilot /awaiting     at 10:00 Tue,Thu       stop_by 2026-06-13
```

Append each successfully scheduled slug to `state.scheduled`.

---

## Cloud-only fallback (sidebar)

If the user says they want a cloud-resident scheduler instead (e.g.
"my laptop sleeps and I want this firing regardless"), the legacy
`/schedule` path is still available. Cron mapping:

| Slug | Cron | Note |
|---|---|---|
| `prep` | `30 7 * * 1-5` | Q-dispatcher style, weekday mornings |
| `inbox-triage` | `0 11,15 * * 1-5` | 11+3 weekday |
| `awaiting` | `0 10 * * 2,4` | Tue+Thu |

Dispatch (only if the user explicitly opted into the cloud path):

```
/schedule create "<routine-name>" --cron "<cron>" --agent chief-of-staff --command "/<slug>"
```

**Limitations the user should understand if they pick this path:**

- Results won't go to their local Telegram bot — `/schedule` routines
  run on Anthropic infra and can't reach the local channel directory.
- The recipe will need to do its own delivery (email, Slack, etc.).
- Recipes that read project-local `.claude/commands/<slug>.md` or
  project-local memory won't have access to those.

For cos-bot's bot-DM-style delivery, autopilot is the right choice.
`/schedule` is the right choice for recipes that are fully cloud-
resident (a future use case, not the current cos-bot recipes).

---

## Implementation notes

- **Slash commands aren't tool calls.** A running model can't dispatch
  `/cos-bot:autopilot` directly — same constraint as `cos-bot:setup`
  and `/telegram:configure`. The nested `claude -p
  --permission-mode bypassPermissions` pattern is the canonical
  workaround. Get authorization first (`AskUserQuestion`); fall through
  to user-dispatched commands if the nested call doesn't behave.
- **`bypassPermissions` on nested calls is gated.** The harness denies
  it on child agents unless explicitly authorized in the parent
  session. The authorization question above is on the record; don't
  assume it carries over from a prior `cos-bot:setup` run.
- **Carry the authorization to demo.** If the user authorized
  `bypassPermissions` here, `/cos-bot:demo` (or the chained activate
  step) can re-use that authorization in the same session — but only
  after re-asking, since auth is per-`AskUserQuestion`-record. Don't
  silently inherit.
- **The autopilot installs a supervisor automatically.** The first
  `/cos-bot:autopilot` arm writes a supervisor runner that
  health-checks every 30 minutes. The install-recipes flow doesn't
  need to mention this; autopilot's confirm message handles it.
