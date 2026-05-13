# Lifecycle — registry, lockfiles, sub-verbs, reboot recovery

Owned by `SKILL.md` orchestration. This file is the contract for state
on disk: shapes, paths, permissions, and the orchestration shapes for
the `list` / `stop` / `status` / `rearm` sub-verbs and the
`SessionStart` hook.

---

## Files

| Path | What | Permissions |
|---|---|---|
| `~/.claude/channels/telegram/.cos-bot-autopilot.json` | Registry — one entry per armed autopilot (user + supervisor) | `0600` |
| `~/.claude/channels/telegram/.cos-bot-autopilot-<slug>.pid` | Lockfile — sleeper PID for `<slug>` | `0600` |
| `~/.claude/commands/<slug>.md` | Generated runner (user scope) | `0644` |
| `~/.claude/commands/_autopilot-supervisor.md` | Generated supervisor runner | `0644` |

All registry and lockfile writes use the channel directory (`~/.claude/
channels/telegram/`) — already created and `0700`-protected by
`/telegram:configure`. Reuses existing infra; no new directories.

Runners go to **user scope** (`~/.claude/commands/`) — not project
scope. Project scope is reserved for the recipes installed by
`/cos-bot:install-recipes`. The two never collide.

---

## Registry shape

```json
{
  "version": 1,
  "entries": {
    "prep-autopilot": {
      "slug": "prep-autopilot",
      "task": "prep",
      "role": "user",
      "mechanism": "claude-p",
      "cadence": {
        "shape": "time",
        "times": ["09:00"],
        "days": ["Mon","Tue","Wed","Thu","Fri"],
        "interval": null,
        "next_delta_seconds": null
      },
      "anchor": "2026-05-13T08:30:00-05:00",
      "started_at": "2026-05-13T08:30:00-05:00",
      "next_fire": "2026-05-14T09:00:00-05:00",
      "runs": [
        { "ts": "2026-05-13T09:00:01-05:00", "status": "ok", "signals": {} }
      ],
      "last_status": "active",
      "stopped_at": null,
      "consecutive_failures": 0,
      "max_runs": null,
      "stop_by": "2026-06-13T00:00:00Z",
      "sleeper_pid": 12345,
      "last_heal_at": null,
      "chat_id": "<int as string>",
      "project_dir": "/Users/.../project"
    },
    "_autopilot-supervisor": {
      "slug": "_autopilot-supervisor",
      "task": null,
      "role": "supervisor",
      "mechanism": "claude-p",
      "cadence": { "shape": "fixed", "interval": 1800 },
      "anchor": "2026-05-13T08:30:00-05:00",
      "next_fire": "2026-05-13T09:00:00-05:00",
      "runs": [],
      "last_status": "active",
      "sleeper_pid": 12346,
      "chat_id": "<int as string>"
    }
  }
}
```

**Write protocol.** Always read-modify-write via `jq`:

```bash
REG=~/.claude/channels/telegram/.cos-bot-autopilot.json
test -f "$REG" || printf '{"version":1,"entries":{}}' > "$REG"
chmod 600 "$REG"
TMP=$(mktemp)
jq --arg slug "$SLUG" --argjson row "$ROW_JSON" \
  '.entries[$slug] = $row' "$REG" > "$TMP" && mv "$TMP" "$REG"
chmod 600 "$REG"
```

Never clobber the whole file from a model-mediated `Write` — concurrent
firings could race.

---

## Lockfile shape

One file per slug:
`~/.claude/channels/telegram/.cos-bot-autopilot-<slug>.pid`.

Contents: the integer PID of the `sh -c` parent of the sleeper, no
trailing newline:

```
$ cat ~/.claude/channels/telegram/.cos-bot-autopilot-prep-autopilot.pid
12345
```

The lockfile is the source of truth for "is this autopilot's sleeper
alive right now." Cross-check on every sub-verb and supervisor cycle:

```bash
PID=$(cat "$LOCKFILE" 2>/dev/null || echo 0)
if [[ "$PID" -gt 0 ]] && kill -0 "$PID" 2>/dev/null; then
  ALIVE=1
else
  ALIVE=0
fi
```

If the registry says `sleeper_pid` but the lockfile is gone or its PID
is dead → re-arm. If the lockfile is present but the registry has no
entry → orphan, delete.

---

## Collision detection (arming flow A3)

When the user runs `/cos-bot:autopilot /<task> ...`:

1. Read the registry. Look for `<task>-autopilot`.
2. If present and `last_status == "active"` and lockfile PID is alive:
   collision. Ask "Replace or cancel?"
3. If present but `last_status` is anything else, or PID is dead:
   not really a collision — proceed (the existing row will be
   overwritten by the arming flow).

A killed `claude` session mid-arm leaves no row in the registry yet
(register-then-lock-then-fire ordering means the registry only mentions
the slug after the sleeper is alive). Safe to re-run.

---

## `rearm` sub-verb (and `SessionStart` hook entry point)

Called on demand and on every `claude` session start. Flow:

1. Read the registry. If missing or empty entries, print:
   ```
   No autopilots to re-arm.
   ```
   …and stop. With `--silent`, suppress output entirely.

2. For each entry with `last_status == "active"`:
   - Check the lockfile + `kill -0`. If alive, leave alone.
   - If dead:
     - Compute next-fire from stored cadence + anchor.
     - If `next_fire < now`, set `next_fire = now + 60s` (don't fire
       immediately on session start — give the user a moment).
     - Spawn the sleeper. Capture `$!`. Write lockfile and registry.
     - Post to Telegram (unless `--silent`):
       ```
       Re-armed /<task> after session start. Next fire <ISO>.
       ```

3. If the registry has user entries but no `_autopilot-supervisor` entry,
   install the supervisor (read `references/supervisor-template.md`,
   write, register, fire).

4. Print a final summary unless `--silent`:
   ```
   Re-armed: <list of slugs>
   Already running: <list>
   Stopped (left alone): <list>
   ```

---

## Failure modes (what the user actually sees)

| Condition | User sees | Action |
|---|---|---|
| Sleeper dies (laptop reboot, kill) | Nothing immediately; next `list` shows `(dead)` | Supervisor health-check re-arms within 30 min. `SessionStart` re-arms on next Claude launch. |
| Recipe errors transiently | Telegram silent for one fire; next fire applies 1×/2×/4× backoff | Auto-recovery; user can `status <slug>` to see the failures. |
| Recipe errors persistently (4×) | Telegram: "Autopilot halted: <slug> — last error: <…>" | `last_status = "halted"`. User runs `rearm` once they fix the recipe, or `stop` + re-arm. |
| Registry corruption | `list` errors with parse failure | Show the user the file path; they can edit/delete and re-run `rearm`. |
| Supervisor itself dies | First missed cycle = invisible; next `SessionStart` re-arms | Reboot recovery is automatic via the hook. |
| All sleepers killed manually + Claude session never restarts | Nothing fires until the user opens Claude again | By design — the user effectively paused everything. |

---

## Reboot recovery, end-to-end

What happens to a `daily 9am /prep` autopilot when the user reboots their laptop at 11pm:

1. **Pre-reboot:** sleeper PID `12345` sitting in `sleep` until 9am tomorrow, registry has `next_fire = 09:00`.
2. **Reboot:** kernel kills PID 12345. Lockfile content stale. Registry untouched (on disk).
3. **User opens Claude in the morning at 8:45am:** the `SessionStart` hook in `plugin.json` runs `claude -p "/cos-bot:autopilot rearm --silent"`.
4. **`rearm` flow:**
   - Reads registry, finds `prep-autopilot` with `next_fire = 09:00`.
   - Checks lockfile, runs `kill -0 12345` → fails. Dead.
   - Computes next-fire: 09:00 is still in the future (15 min away) → use as-is. `N = 900`.
   - Spawns new sleeper, captures new PID, writes lockfile + registry.
   - Posts (or suppresses with `--silent`).
5. **9am:** new sleeper wakes, fires the runner, runner runs `/prep`, recipe posts to Telegram, runner schedules the next firing for 09:00 the day after.

If the user opens Claude after 9am, the `rearm` flow's "if `next_fire < now`, set to `now + 60s`" rule fires the missed run ~1 minute later. The user gets a slightly late `/prep` and then the cadence catches up.

---

## What is NOT in the registry (intentional)

- **Source-of-truth state for the recipe itself.** Recipes manage their
  own state via the project's `.claude/projects/<slug>/memory/`
  directory. The registry tracks scheduling, not recipe progress.
- **Auth tokens.** Telegram tokens stay in `~/.claude/channels/
  telegram/.env`. Autopilot reads `access.json` for the chat-id at
  arm-time and stores only the chat-id in the registry. If the token
  is rotated, autopilots keep working.
- **Verbose run logs.** The `runs` array is truncated to the last 50
  entries per slug by the supervisor's cleanup pass. For longer-term
  history, recipes that need it should write to their own
  memory/project files.
