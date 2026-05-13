---
name: autopilot
description: Put any recipe on autopilot — set a recurring/adaptive schedule that runs locally and reschedules itself after each run (no cron, no remote agent). Default mechanism is nested `claude -p` via `nohup sleep N && claude -p` — survives terminal exit, supports any interval, adaptive cadence, and stop conditions. ScheduleWakeup is offered as a live-session demo flavor. Use when the user says "run /prep every day at 9AM locally," "keep checking my inbox until X," "watch for replies," or "set this task on autopilot."
user-invocable: true
model: haiku
allowed-tools:
  - Read
  - Write
  - AskUserQuestion
  - Bash(ls *)
  - Bash(cat *)
  - Bash(test *)
  - Bash(pwd)
  - Bash(mkdir -p *)
  - Bash(chmod *)
  - Bash(rm *)
  - Bash(printf *)
  - Bash(date *)
  - Bash(nohup *)
  - Bash(kill *)
  - Bash(ps *)
  - Bash(jq *)
  - Bash(claude --permission-mode bypassPermissions -p)
---

# /cos-bot:autopilot — local self-rescheduling runner for any recipe

Turns "task + cadence policy" into a **self-rescheduling slash command**
that runs entirely on the user's machine. The skill scaffolds a separate
runner at `~/.claude/commands/<slug>-autopilot.md` whose body is
"Run `/<task>` → check stop condition → schedule next run." Each
invocation re-fires the *runner*, so the loop logic stays in one place
and the underlying recipe stays independently usable.

**Why a new mechanism.** `/schedule`'s routines run as **remote agents**
on Anthropic's infrastructure — they can't reach the user's local
Telegram bot (`~/.claude/channels/telegram/`) or local `claude -p` shell.
`/loop` works live but dies with the terminal. `ScheduleWakeup`
self-paces inside `/loop` but is clamped to ≤1h and session-bound. The
autopilot pattern uses `nohup sh -c 'sleep N && claude -p "/..." &'` so
the loop survives terminal exit, supports any interval, and can run any
local-only recipe.

Arguments passed: `$ARGUMENTS`

State and lockfiles live in `~/.claude/channels/telegram/` (mode `0600`),
so they share the cos-bot channel directory alongside `access.json` and
`.cos-bot-recipes.json`.

## Companion files

`SKILL.md` is the orchestrator. Deep material lives in `references/`:

- `references/mechanisms.md` — decision tree + one canonical snippet per mechanism (nested `claude -p` and `ScheduleWakeup`).
- `references/cadence.md` — fixed / time-of-day / adaptive specs, failure backoff, absolute next-fire-time.
- `references/runner-template.md` — canonical body of the generated runner with placeholders.
- `references/supervisor-template.md` — canonical body of the auto-installed supervisor.
- `references/lifecycle.md` — PID/lockfile shape, registry shape, list/stop/status/rearm verbs, supervisor bootstrap, failure modes.

Read each lazily — pull the companion only when its step runs.

---

## Step 0a — tool-denial early abort (every run, every code path)

If **any** Bash, Write, or AskUserQuestion call returns a permission
denial during this skill, **abort immediately** with this message and
stop:

```
Cannot arm autopilot — the harness denied a tool call.

Re-run with:
  claude --permission-mode bypassPermissions  (one-shot, sandbox use)
or accept the prompts when they appear (interactive Claude Code).

Files attempted: <list>
Files actually written: <list> (or "none")
Lockfile state:        <held|released|absent>

Re-running with permissions granted is safe — the skill is idempotent.
```

A half-written runner + held lockfile is the worst failure mode (the
user thinks the autopilot is armed; nothing actually fires). Detect
denial up-front and hard-abort. Pattern copied from
`plugins/cos-bot/skills/install-recipes/SKILL.md` § 0a.

---

## Step 0b — capture working dir + registry path

1. `pwd` → `state.projectDir`.
2. Compute paths once and reuse:
   - Registry: `~/.claude/channels/telegram/.cos-bot-autopilot.json`
   - Lockfile dir: `~/.claude/channels/telegram/` (one
     `.cos-bot-autopilot-<slug>.pid` per armed autopilot).
   - Runner dir: `~/.claude/commands/` (user scope — survives project
     deletion; `/cos-bot:install-recipes` writes to **project** scope
     `.claude/commands/`, autopilot writes to **user** scope to avoid
     polluting the project git tree).
3. `mkdir -p ~/.claude/commands ~/.claude/channels/telegram` and
   `chmod 700 ~/.claude/channels/telegram`. Idempotent.

---

## Dispatch on `$ARGUMENTS`

Parse the first whitespace-separated token:

- `/<task>` *(starts with `/`)* — **arm a new autopilot for `<task>`.**
  Remainder of the args is the cadence spec (see *Arming flow* below).
  Examples: `/prep daily 9am`, `/inbox-triage every 2h`,
  `/awaiting adaptive stop_by 2026-05-13T18:00`.
- `<task>` *(no leading slash)* — same as above; `/` is optional shorthand.
- `list` — print the registry: each entry's slug, mechanism, next fire,
  sleeper PID (live/dead), last status, max_runs / stop_by. Include the
  `[supervisor]` entry with that tag. Read-only.
- `stop <slug>` — kill the sleeper PID (if alive), remove the lockfile,
  mark the registry entry `stopped`, post "Autopilot stopped: <slug>"
  to the user's Telegram chat. If `<slug>` is the only user-armed entry,
  also offer to uninstall the supervisor (or let the supervisor
  uninstall itself on its next cycle).
- `status <slug>` — print one entry's full registry row + recent runs
  log. Read-only.
- `rearm` *(optional flag `--silent`)* — walk the registry; for every
  entry whose sleeper PID is dead, re-arm it using the stored cadence.
  Used by the `SessionStart` hook and after reboots. `--silent`
  suppresses Telegram messages and is intended for hook use.
- `run-supervisor` — force-run the supervisor's health-check + cleanup
  pass now (debugging / testing).
- `defaults` *(special, immediately after `/<task>`)* — "arm with stock
  cadence for this recipe, no questions." Used for fast install. The
  stock map is in `references/cadence.md` § *Default cadence per recipe*.
- *(empty / unrecognized)* — print usage and stop:
  `/cos-bot:autopilot /<task> <cadence>   |   list   |   stop <slug>   |   status <slug>   |   rearm`

If the arg shape doesn't match any of the above, show usage and stop.
Do **not** fall through.

---

## Sub-verb: `list`

1. Read the registry. If missing or empty, print "No autopilots armed." and stop.
2. For each entry, check `kill -0 <sleeper_pid>` to derive a live/dead tag.
3. Print one line per entry, fixed-width:
   ```
   <slug>            mechanism      next_fire           pid (alive|dead)  status
   prep-autopilot    claude-p       2026-05-14T09:00    12345 (alive)     ok
   _autopilot-…      claude-p       2026-05-13T18:00     6789 (alive)     ok    [supervisor]
   ```
4. Stop. Read-only; no Telegram post.

---

## Sub-verb: `stop <slug>`

1. Read the registry. If `<slug>` not present, print "No autopilot named
   `<slug>`." and stop.
2. Read the lockfile `~/.claude/channels/telegram/.cos-bot-autopilot-<slug>.pid`.
   If the PID is alive (`kill -0 <pid>` returns 0), `kill <pid>`.
3. Remove the lockfile and the runner at `~/.claude/commands/<slug>-autopilot.md`.
4. Update the registry: set `<slug>.last_status = "stopped"`,
   `<slug>.stopped_at = <ISO now>`. Keep the row so `list` shows it was
   stopped (a future `rearm` ignores `stopped` entries).
5. Post to Telegram: "Autopilot stopped: `<slug>`."
6. If the registry now has no `last_status: active` user entries, post a
   second message: "No user-armed autopilots left — supervisor will
   uninstall on its next cycle (or stop it with `/cos-bot:autopilot
   stop _autopilot-supervisor`)."

---

## Sub-verb: `status <slug>`

Print the registry row for `<slug>` plus the last 10 entries in the
`runs` log. Read-only.

---

## Sub-verb: `rearm [--silent]`

The reboot-recovery and `SessionStart`-hook entry point. See
`references/lifecycle.md` § *Rearm flow* for the orchestration.
Summary:

1. Read the registry. If missing, print one line and stop (nothing to
   rearm).
2. For each entry with `last_status: active`:
   - If its sleeper PID is alive (`kill -0`), leave it alone.
   - If dead, compute the next-fire-time from stored cadence + last run
     and spawn a fresh `nohup sh -c 'sleep N && claude -p "/<slug>-autopilot" &'`.
     Record the new sleeper PID.
3. If `--silent`, suppress per-entry Telegram messages and only post a
   single summary message if anything was re-armed. Otherwise post per-entry.
4. If the registry has any user entries but no supervisor entry, install
   the supervisor (see *Supervisor bootstrap* below).

---

## Sub-verb: `run-supervisor`

Run the supervisor's body inline once and stop. Used for testing and for
the verification harness. Identical to what the supervisor cron does on
each cycle; see `references/supervisor-template.md`.

---

## Arming flow (when `$ARGUMENTS` starts with `/<task>` or `<task>`)

### A1. Validate the task exists

The recipe must exist at one of:

- `<projectDir>/.claude/commands/<task>.md` — project-installed recipe (most common).
- `~/.claude/commands/<task>.md` — user-scoped command.

If neither, abort with:

```
No recipe found for /<task>. Install it first:
  /cos-bot:install-recipes <task>
```

Reserve the slug `<task>-autopilot` for the runner filename. Refuse to
arm an autopilot for a task that itself ends in `-autopilot` (don't let
the user accidentally nest autopilots).

### A2. Check Telegram pairing

Read `~/.claude/channels/telegram/access.json` (mode `0600`). Look for a
chat-id (same pattern as `/cos-bot:demo` § Step 0). If missing, abort:

```
Telegram isn't paired yet. Finish /cos-bot:setup or /cos-bot:connect,
pair via DM, then re-run /cos-bot:autopilot.
```

Capture the chat-id in `state.chatId`. The runner posts results here.

### A3. Collision check

Read the registry. If `<task>-autopilot` already exists with
`last_status: active`:

```
Autopilot for /<task> is already armed (next fire <ISO>, sleeper PID <N>
alive).

What now?
  - Replace existing — stop current, re-arm with new cadence
  - Cancel — keep the current armed
```

Use `AskUserQuestion`. If "Replace existing," run the `stop <slug>` flow
inline before proceeding. Never silently double-arm.

### A4. Cadence interview

Skip this entirely if `$ARGUMENTS` is `<task> defaults` — jump to A5
with the recipe's stock cadence from `references/cadence.md` §
*Default cadence per recipe*.

Otherwise, one batched `AskUserQuestion` call (≤4 questions):

| Field | Question | Options |
|---|---|---|
| `shape` | "How often should this run?" | `Fixed interval` / `Time-of-day` / `Adaptive (recipe decides)` / `One-shot at time` |
| `intervalOrTime` | (depends on shape — see `references/cadence.md`) | Free-text via "Other" for irregular times |
| `stop` | "When should it stop?" | `After N runs` / `By date` / `On condition emitted by recipe` |
| `flavor` | "Watch it live in this session, or fire-and-forget?" | `Fire-and-forget (recommended)` / `Live (this session only)` |

Parse free-text inputs per `references/cadence.md` § *Parsing*.

### A5. Mechanism selection

Apply the decision tree from `references/mechanisms.md`:

- `flavor === "Live"` and `shape === "Fixed interval"` and interval < 1h
  → `mechanism = "schedule-wakeup"` (the live-session demo flavor).
- **Everything else** → `mechanism = "claude-p"` (the canonical default).

Record `state.mechanism`.

### A6. Compute first next-fire-time

Per `references/cadence.md` § *Absolute next-fire-time*:

- Fixed interval: `next_fire = now + interval` (first fire is "after one
  interval," not "immediately") **unless** the user passed `defaults`,
  in which case `now + 60s` so the smoke test sees a fire quickly.
- Time-of-day: `next_fire = next occurrence of HH:MM in local TZ` (today
  if that time hasn't passed, otherwise tomorrow).
- Adaptive: `next_fire = now + initial_interval` (the recipe will tune
  it on each run via the runner's state-write protocol — see
  `references/cadence.md`).
- One-shot: `next_fire = <given ISO>`.

### A7. Scaffold the runner

Read `references/runner-template.md`. Substitute placeholders:

| Placeholder | Value |
|---|---|
| `{{SLUG}}` | `<task>-autopilot` |
| `{{TASK}}` | `<task>` (no slash) |
| `{{TASK_PATH}}` | absolute path to recipe file (project or user scope) |
| `{{CHAT_ID}}` | `state.chatId` |
| `{{MECHANISM}}` | `state.mechanism` |
| `{{CADENCE_BLOCK}}` | cadence spec as JSON (shape + intervalOrTime + stop) |
| `{{REGISTRY_PATH}}` | `~/.claude/channels/telegram/.cos-bot-autopilot.json` |
| `{{LOCKFILE_PATH}}` | `~/.claude/channels/telegram/.cos-bot-autopilot-<task>-autopilot.pid` |

Write to `~/.claude/commands/<task>-autopilot.md` via the `Write` tool.

### A8. Register, lock, fire first run

1. **Register.** Read-modify-write the registry. Add/update the entry:
   ```json
   {
     "slug": "<task>-autopilot",
     "task": "<task>",
     "mechanism": "<claude-p|schedule-wakeup>",
     "cadence": { "shape": "...", "intervalOrTime": "...", "stop": { ... } },
     "next_fire": "<ISO>",
     "started_at": "<ISO now>",
     "anchor": "<ISO now>",
     "runs": [],
     "last_status": "active",
     "consecutive_failures": 0,
     "max_runs": <N|null>,
     "stop_by": "<ISO|null>",
     "sleeper_pid": null,
     "chat_id": "<state.chatId>",
     "project_dir": "<state.projectDir>"
   }
   ```
   `chmod 600` the registry. Use `jq` for read-modify-write to avoid
   clobbering siblings.
2. **Lock.** Compute seconds-until-next-fire `N`. Spawn the sleeper:
   ```bash
   nohup sh -c 'sleep <N> && claude --permission-mode bypassPermissions -p "/<task>-autopilot" >/dev/null 2>&1' >/dev/null 2>&1 &
   echo $!
   ```
   Capture the printed PID (the `sh -c` parent, **not** the `sleep`
   sub-process — that's what `kill` needs to take down both). Write it
   to the lockfile and to `<slug>.sleeper_pid` in the registry.

   For `mechanism === "schedule-wakeup"`: skip `nohup` and instead emit
   a one-line note to the user about the live-session limitation —
   the runner itself will call `ScheduleWakeup` on its next firing.

3. **Install supervisor if absent.** See *Supervisor bootstrap* below.
4. **Post Telegram.** Send to `state.chatId`:
   ```
   Autopilot armed: /<task>
   Next fire: <ISO>
   Mechanism: <claude-p|schedule-wakeup>
   Stop with: /cos-bot:autopilot stop <task>-autopilot
   ```
   Use the nested `claude -p` pattern (same as `/cos-bot:demo` Step 3).

### A9. Confirm summary in the calling session

Print to stdout (the user's terminal):

```
Armed: /<task>-autopilot
  Runner:       ~/.claude/commands/<task>-autopilot.md
  Registry:     ~/.claude/channels/telegram/.cos-bot-autopilot.json
  Lockfile:     ~/.claude/channels/telegram/.cos-bot-autopilot-<task>-autopilot.pid
  Sleeper PID:  <pid>
  Next fire:    <ISO>
  Mechanism:    <claude-p|schedule-wakeup>

Watch it:  /cos-bot:autopilot list
Stop it:   /cos-bot:autopilot stop <task>-autopilot
```

Stop.

---

## Supervisor bootstrap

The first time any user-armed autopilot exists in the registry, install
the supervisor:

1. Read `references/supervisor-template.md`. Substitute placeholders
   (only `{{REGISTRY_PATH}}`, `{{INTERVAL_SECONDS}}` = `1800`,
   `{{CHAT_ID}}`). Write to
   `~/.claude/commands/_autopilot-supervisor.md`.
2. Add a registry entry with slug `_autopilot-supervisor`, mechanism
   `claude-p`, no `max_runs` or `stop_by` (the supervisor self-removes
   when the registry has no other entries), and tag
   `role: "supervisor"`.
3. Spawn its sleeper exactly like a user autopilot.

The supervisor is intentionally not user-armable directly; it's an
internal artifact. `/cos-bot:autopilot list` shows it with a
`[supervisor]` tag for transparency.

The `SessionStart` hook in `plugin.json` runs `claude -p
"/cos-bot:autopilot rearm --silent"` on every session — that's the
second safety net for reboot recovery.

---

## Implementation notes

- **Skill scope ends at "armed."** The runner is what actually executes
  the recipe on each fire; the skill scaffolds it and starts the loop,
  then exits. The runner doesn't reference this skill at runtime.
- **State file == registry.** No separate per-step state machine —
  unlike `/cos-bot:install-recipes`, this skill is short and not
  resumable. If the user kills it mid-arm, the lockfile won't exist and
  re-running is safe.
- **Mandatory finiteness.** A4 must collect `max_runs` *or* `stop_by`
  *or* `On condition`. The interview is structured to make this
  unavoidable — there's no "run forever" option. The supervisor is the
  only exception, and it self-uninstalls when the registry is empty.
- **Absolute next-fire-time.** Compute next fire from `anchor +
  n*interval`, not `now + interval`. Prevents drift across many cycles.
- **Sleeper PID = `sh -c` parent.** When `nohup sh -c 'sleep N && cmd
  &'` is backgrounded, `$!` is the `sh` PID. Killing it kills the
  whole subtree on signal propagation. Don't try to track the `sleep`
  PID — it's a grandchild and races.
- **Telegram receipt is best-effort.** If the nested `claude -p` Telegram
  post fails (chat-id changed, bot revoked), record the failure to the
  registry's `runs` log but don't abort the autopilot — the user can
  still inspect via `list`/`status`.
- **No emoji in summaries.** ASCII only. Matches the cos-bot voice.
