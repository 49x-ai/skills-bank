# Supervisor template

The auto-installed health-check + cleanup task. Written once to
`~/.claude/commands/_autopilot-supervisor.md` the first time any
user-armed autopilot exists.

The supervisor is itself a self-rescheduling autopilot (same `sleep +
nohup` mechanism), but plays two extra roles:

1. **Health-check** — re-arm dead sleepers using stored cadence.
2. **Cleanup** — remove completed / expired entries, delete orphaned
   lockfiles, truncate old runs logs.

It runs every `{{INTERVAL_SECONDS}}` seconds (default `1800` = 30 min)
and self-uninstalls when the registry has no user entries.

---

## Placeholders

| Token | Replaced with |
|---|---|
| `{{REGISTRY_PATH}}` | `~/.claude/channels/telegram/.cos-bot-autopilot.json` |
| `{{INTERVAL_SECONDS}}` | `1800` (30 min) |
| `{{CHAT_ID}}` | the chat-id used for heal/halt notifications |

---

## Template body

```
---BEGIN---
---
name: _autopilot-supervisor
description: Internal cos-bot autopilot supervisor — health-check, cleanup, self-reschedule. Not user-armable. Manage via /cos-bot:autopilot.
allowed-tools:
  - Read
  - Write
  - Bash(jq *)
  - Bash(date *)
  - Bash(ps *)
  - Bash(kill *)
  - Bash(nohup *)
  - Bash(printf *)
  - Bash(test *)
  - Bash(rm *)
  - Bash(claude --permission-mode bypassPermissions -p)
---

# /_autopilot-supervisor — autopilot health-check + cleanup

Internal runner installed by `/cos-bot:autopilot`. Runs every
{{INTERVAL_SECONDS}}s. Not intended for user invocation.

---

## Health-check pass

Read the registry at {{REGISTRY_PATH}}. For each entry whose
`last_status == "active"` and `role != "supervisor"`:

1. Read `<entry>.sleeper_pid` and check `kill -0 <pid>` (silent;
   non-zero → dead).
2. Also check `started_at` of the sleeper against the entry's
   interval — if the sleeper has been alive longer than `2 ×
   interval`, treat as stuck (it should have been replaced by now).
3. If dead or stuck:
   - Compute `next_fire` per `references/cadence.md` § *Absolute
     next-fire-time*, using the stored cadence and apply failure
     backoff if `consecutive_failures > 0`.
   - Spawn a fresh sleeper exactly like the original arming flow:
     ```
     N=$(( <next_fire_ts> - $(date +%s) ))
     nohup sh -c "sleep $N && claude --permission-mode bypassPermissions -p '/<slug>' >/dev/null 2>&1" >/dev/null 2>&1 &
     ```
   - Update `<entry>.sleeper_pid` and `<entry>.next_fire`.
   - **Post once per heal** to Telegram chat {{CHAT_ID}}: `"Re-armed
     <slug> after detecting dead sleeper. Next fire <ISO>."`
     Don't spam on repeated heals of the same slug within 10 minutes
     (track via `<entry>.last_heal_at`).

---

## Cleanup pass

After the health-check, walk the registry again:

1. Remove entries where `last_status` is `completed` / `halted` /
   `stopped` AND `stopped_at` is older than 7 days. Delete their
   lockfiles.
2. Remove entries past `stop_by` (mark `last_status = "completed"`
   first, then remove on the next cycle so the user sees the
   completion in `list`).
3. Remove orphaned lockfiles in
   `~/.claude/channels/telegram/.cos-bot-autopilot-*.pid` whose slug
   no longer exists in the registry, or whose PID is dead.
4. Truncate each entry's `runs` array to the last 50 entries (keeps
   the registry small).

---

## Self-uninstall check

After cleanup, if the registry has zero user entries (only the
supervisor itself remains), uninstall:

1. Set the supervisor's `last_status = "stopped"`.
2. Remove the supervisor's own row from the registry (delete the
   whole file if the registry is now empty).
3. Remove the lockfile.
4. Remove this runner file (`~/.claude/commands/_autopilot-supervisor.md`).
5. Exit without rescheduling.

The next user `/cos-bot:autopilot` arm will reinstall a fresh
supervisor.

---

## Re-arm self

If the supervisor is not self-uninstalling, schedule its next cycle:

```
N={{INTERVAL_SECONDS}}
nohup sh -c "sleep $N && claude --permission-mode bypassPermissions -p '/_autopilot-supervisor' >/dev/null 2>&1" >/dev/null 2>&1 &
echo $! > ~/.claude/channels/telegram/.cos-bot-autopilot-_autopilot-supervisor.pid
# update registry: supervisor.sleeper_pid + supervisor.next_fire
```

---

## Notes

- The supervisor never declares `max_runs` or `stop_by`. It lives as
  long as there are user entries to watch.
- The supervisor's own `consecutive_failures` is incremented if it
  errors during a cycle. The same 4-strike halt applies. A halted
  supervisor is a real problem — the user should see a "Supervisor
  halted" Telegram message and re-run `/cos-bot:autopilot rearm` to
  reinstall.
- Cleanup is idempotent: running the supervisor cycle twice in a row
  produces the same registry state.
---END---
```

---

## Notes for the skill author

- The supervisor template is written **once** per user-machine, the
  first time any autopilot is armed. Subsequent autopilots don't
  rewrite it — they just add their own registry entries.
- The `SessionStart` hook in `plugin.json` calls
  `/cos-bot:autopilot rearm --silent`, which will:
  1. Re-arm any dead user sleepers (using their stored cadence).
  2. Re-arm a dead supervisor.
  3. Reinstall the supervisor if the registry has user entries but no
     supervisor.
- The supervisor's `_` prefix (`_autopilot-supervisor`) marks it as
  internal in `/cos-bot:autopilot list` output. `list` shows it with
  a `[supervisor]` tag for transparency but doesn't let the user `arm`
  or `stop` it directly — they manage user autopilots and the
  supervisor manages itself.
