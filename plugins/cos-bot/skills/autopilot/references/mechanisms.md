# Mechanisms — decision tree + canonical snippets

Two **local** mechanisms. `/schedule` is intentionally excluded — its
routines run as remote agents on Anthropic infrastructure and can't
reach the user's local Telegram bot or local `claude -p`.

The choice is **"watch live in this session" vs "fire-and-forget."** The
default is fire-and-forget.

| Cadence shape | Mechanism | Why |
|---|---|---|
| Fixed interval <1h, user wants to watch it run live in this session | `ScheduleWakeup` inside `/loop` dynamic mode | Native in-session primitive. Cache-friendly. Dies cleanly when the session closes — which is the point of a watch-it-work demo. |
| **Default — anything else** (long intervals, time-of-day, adaptive, stop-on-condition, fire-and-forget, survives terminal exit) | Nested local `claude -p` re-fire via `nohup sh -c 'sleep N && claude -p "/<slug>"' &` | Pure local. Survives session/terminal exit. Each run computes its own next-fire-time from registry state, so adaptive policies and stop conditions work naturally. Reboot kills pending sleeps — the registry + `SessionStart` hook re-arm. |

---

## Canonical snippet: nested `claude -p` (the default)

This is the snippet baked into the generated runner. It computes
seconds-until-next-fire **before** sleeping (so adaptive policies that
change the cadence on each run take effect immediately).

```bash
N="<seconds_until_next_fire>"   # absolute next-fire-time minus now
nohup sh -c "sleep $N && claude --permission-mode bypassPermissions -p '/<slug>-autopilot' >/dev/null 2>&1" >/dev/null 2>&1 &
SLEEPER_PID=$!
```

Notes:

- `nohup` detaches from the controlling terminal so closing the session
  doesn't SIGHUP the sleeper. `>/dev/null 2>&1` on both layers means no
  `nohup.out` or stderr files accumulate.
- `$!` captures the `sh -c` PID. Killing that PID propagates to the
  `sleep` child (and to the `claude` child if it's already spawned),
  which is what `/cos-bot:autopilot stop` relies on.
- Use **absolute** next-fire-time computation:
  `next_fire_ts = anchor_ts + n * interval_seconds`, where `n` is the
  smallest integer such that `next_fire_ts > now`. Then
  `N = next_fire_ts - now`. This prevents drift over many cycles.
- For time-of-day: `next_fire_ts` is the next occurrence of `HH:MM` in
  the user's local timezone (today if not yet past, otherwise tomorrow).
  `N = next_fire_ts - now`.

---

## Canonical snippet: `ScheduleWakeup` (live-session demo)

`ScheduleWakeup` is only callable from within an active `/loop` dynamic
mode invocation. The runner template embeds this snippet inside its
"Schedule next run" block when `mechanism === "schedule-wakeup"`:

```
After running /<task> and posting the result, schedule the next firing
via ScheduleWakeup with:
  delaySeconds: <seconds_until_next_fire>   (clamped to 60..3600)
  prompt: <verbatim /loop input that re-fires this runner>
  reason: <short telemetry note>
```

This only works while the `/loop` session is alive — closing the
terminal terminates the wake chain. That's the design intent of the
"live" flavor.

---

## Why not `/schedule`?

The plan's hard constraint. `/schedule` routines execute as remote
agents and:

1. Have no access to `~/.claude/channels/telegram/` (it lives on the
   user's filesystem).
2. Can't run a local `claude -p` (that's how cos-bot recipes dispatch).
3. Can't read project-installed `.claude/commands/<recipe>.md` files.

For fully-cloud-resident routines that don't need the local bot,
`/schedule` is still the right tool — the install-recipes
`references/schedule.md` covers that path. Autopilot is specifically for
the local/Telegram-bound recipes.

---

## Why not naked `cron`?

System cron is a fine mechanism but requires editing the user's
`crontab` (a system-wide config), survives plugin uninstall (zombie
jobs), and has no notion of adaptive cadence. The nested-`claude -p`
approach keeps all state inside the plugin's channel directory; a single
`rm` cleans up.

---

## Why not a daemon?

A long-lived daemon process (Node/Python supervisor) would solve
reboot-survival and unify health checks. It's also a much bigger change:
new bin to install, ports to manage, log rotation, restart policy. The
`SessionStart` hook + supervisor approach gets ~95% of the value with
zero new processes between firings.

If users start armed-autopilot counts above ~20 we should reconsider
this trade-off.
