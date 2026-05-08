# Schedule — cron mapping + nested `claude -p` dispatch

The schedule step offers `/schedule` setup for any recipes whose
`schedule` knob is **not** `On-demand only`. This file documents the
cron forms, the routine-naming convention, and the nested `claude -p`
authorization pattern.

The SKILL.md owns the orchestration (decide whether to run this step,
which recipes are eligible, persist `state.scheduled`); this file owns
the cron table and the dispatch logic.

---

## Cron mapping

Map options to the literal `/schedule` arguments these recipes' files
document:

| Slug | Routine name (pin) | Schedule choice | Cron / form |
|---|---|---|---|
| `prep` | `prep` | Q-dispatcher | `30 7 * * 1-5` (a once-daily dispatcher routine that schedules per-meeting one-shots) |
| `prep` | `prep` | D-loop | a `/loop` watcher every 15 min — surface as `/loop 15m /prep` |
| `inbox-triage` | `inbox-triage` | 11+3 | `0 11,15 * * 1-5` |
| `inbox-triage` | `inbox-triage` | 3 only | `0 15 * * 1-5` |
| `awaiting` | `awaiting` | Tue+Thu | `0 10 * * 2,4` |

`/who` and `/catchup` are always on-demand (no schedule offer).

**Routine name = slug.** The canonical recipe files use longer
metadata names (`meeting-prep`, `morning-brief`, etc.) but the
slash command, the `state.selected` slug, and the `/schedule` routine
name are all the **slug** form (`prep`, `brief`, `inbox-triage`, …).
Always pass the slug as `<routine-name>` in the `/schedule` create
command — it matches the slash command name the user types and the
filename in `.claude/commands/`.

---

## Offer Q&A

If at least one recipe in `state.selected` has a non-`On-demand`
schedule, ask via `AskUserQuestion` (multi-select):

> Schedule any of these now? You can re-run `/schedule` later for any
> you skip.
>
> - `/prep` — `<chosen cron>`
> - `/inbox-triage` — `<chosen cron>`
> - `/awaiting` — Tue + Thu 10am
> - **None — I'll schedule manually later**

If the list is empty, skip this step entirely.

---

## Authorization

For each selected one, dispatch `/schedule` via a nested `claude -p`
call, **after explicit authorization** (mirrors cos-bot:setup step 4):

> To create the schedule, I need to spawn a nested `claude -p` with
> `--permission-mode bypassPermissions` so it can dispatch `/schedule`
> without an approval prompt for each routine. Authorize?
>
> - **Yes — use claude -p with bypassPermissions**
> - **No — I'll run /schedule myself** (I'll print the exact commands)

If yes, for each scheduled recipe, run:

```
printf '/schedule create "<routine-name>" --cron "<cron>" --agent chief-of-staff --command "/<slug>"\n' \
  | claude --permission-mode bypassPermissions -p
```

(The exact `/schedule` argument shape may vary by the user's installed
schedule skill — defer to whatever the running version of `/schedule`
documents. Confirm by reading `<schedule-plugin-root>/SKILL.md` or by
`/schedule --help` if unsure. If the nested call returns text asking
for more info, fall through to the user-dispatched fallback.)

If no, print the exact commands the user can paste:

```
/schedule create "inbox-triage" --cron "0 11,15 * * 1-5" --agent chief-of-staff --command "/inbox-triage"
/schedule create "awaiting"     --cron "0 10 * * 2,4"   --agent chief-of-staff --command "/awaiting"
```

Append each successfully scheduled slug to `state.scheduled`.

---

## Implementation notes

- **Slash commands aren't tool calls.** A running model can't dispatch
  `/schedule` directly — same constraint as `cos-bot:setup` and
  `/telegram:configure`. The nested `claude -p
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
