# Backgrounded `claude --channels` session

Step 5 (`relaunch`) of `setup/SKILL.md` (and `connect/SKILL.md`'s Step
5) can either prompt the user to `/exit` and relaunch, or spawn the
channel server as a background process so pairing — and day-to-day DM
round-trips — happen without leaving the current session. This file
covers the background path.

The channel server only needs to *exist* for pairing; for ongoing DM
round-trips it needs a stable PTY plus permission to call MCP tools
without a human approver. Two backgrounding paths apply:

- **tmux available** (recommended, validated 2026-05-04 with
  `--dangerously-skip-permissions`).
- **tmux not available** → `script(1)` PTY fallback. Works for pairing
  and short sessions, exposes the silent failure modes documented at
  the end of this file.

---

## Step A — detect tmux

```
command -v tmux >/dev/null 2>&1 && echo "tmux: yes" || echo "tmux: no"
```

`command -v` works in any POSIX shell; `which tmux` is fine on
mac/Linux but not portable. Either is acceptable here. Branch on the
result.

---

## Step B — get authorization

The dialogue depends on which path is available. **Don't offer to
install tmux** — that's a user-side choice, not a skill-side
prerequisite. If tmux isn't there, present `script(1)` and let the
user decide later if they want to install tmux.

### tmux available

> Instead of `/exit` + relaunch, I can spawn
> `claude --channels plugin:telegram@claude-plugins-official` inside
> a tmux session so it survives terminal close. The headless session
> has no human at the TTY to approve permission prompts, so it also
> needs `--dangerously-skip-permissions` — meaning any DM from your
> senderId can call any MCP tool without a prompt. The hard gate is
> `allowFrom` in `access.json` (only your senderId is in there), but
> inside that gate there are no further prompts.
>
> Authorize: tmux + skip-permissions (recommended) / tmux only / neither?

**Default to "tmux + skip-permissions"** — plain tmux without
skip-permissions reproduces the typing-but-not-sending failure mode
(see *Three silent failure modes* below).

### tmux NOT available

> Instead of `/exit` + relaunch, I can spawn
> `claude --channels plugin:telegram@claude-plugins-official` in the
> background using `script(1)` to provide a PTY. This works for
> pairing and short sessions, but has two known silent-failure modes
> for longer use (silent-stop after N turns, typing-but-not-sending).
> If you want a more robust setup later, install tmux and re-run
> this skill — I'll use it automatically.
>
> Authorize the `script(1)` background spawn?

---

## Step C — launch (tmux path)

```
tmux new-session -d -s cos-bot \
  -c <projectDir> \
  'claude --channels plugin:telegram@claude-plugins-official --dangerously-skip-permissions; exec zsh'
```

The `; exec zsh` keeps the pane alive after `claude` exits so the
user can re-launch from inside the same tmux session by hand later.

Wait ~6 seconds, then verify with `tmux capture-pane`:

```
tmux capture-pane -p -t cos-bot:0 | tail -25
```

Look for `Listening for channel messages from:
plugin:telegram@claude-plugins-official` and the footer `⏵⏵ bypass
permissions on`. The `1 MCP server needs auth · /mcp` line in the
same pane is **harmless** — that's the bundled `chrome-devtools-mcp`,
unrelated to the Telegram channel.

Tell the user how to interact:
- `tmux attach -t cos-bot` to peek (detach with `Ctrl-b d`)
- `tmux capture-pane -p -t cos-bot:0` for a one-shot snapshot
- `tmux kill-session -t cos-bot` to stop the bot cleanly

---

## Step C — launch (`script(1)` fallback path)

```
mkdir -p /tmp/cos-bot
nohup script -q /tmp/cos-bot/claude-channel.log \
  claude --channels plugin:telegram@claude-plugins-official \
  > /dev/null 2>&1 &
disown
```

Wait ~5 seconds, then verify by extracting `strings` from the log
(it's full of TUI escape sequences):

```
strings /tmp/cos-bot/claude-channel.log | grep -i "Listening" | tail -3
```

Same `1 MCP server needs auth · /mcp` caveat applies.

If running this path, **tell the user upfront** that the bot's
known failure modes for multi-turn use are (a) silent-stop after
~2 turns and (b) inability to call MCP tools without an interactive
approver, and that the recovery is `kill <pid> && rerun`. They
should consider `tmux` as a permanent upgrade.

---

## Step D — finalize (both paths)

1. Set `state.relaunchAcknowledged = true`, persist, proceed to step 6.
2. **After pairing completes, leave the backgrounded session running**
   if it's tmux (it's now the user's day-to-day bot). For `script(1)`,
   the trade-off is on the user: leave it for short use (knowing it'll
   wedge eventually), or kill it now and re-launch via tmux later
   when they install it.

---

## Three silent failure modes

Across multiple test runs, the backgrounded channel server has
degraded in three different ways. Each presents differently from
Telegram's side; the recovery is the same (kill + respawn) but the
diagnosis you'd write into the log is not.

1. **`1 MCP server failed · /mcp`** *(SESSION-LOG Phase 3,
   2026-04-30).* The backgrounded session boots, accepts an inbound
   DM, the bot replies "Pairing required …" — but the inbound MCP
   never polls `approved/`, the marker file persists past 30s, the
   user never sees "Paired!". The channel log shows the literal
   `1 MCP server failed` line. Outbound works, inbound doesn't.
2. **Silent-stop after N turns under `script(1)` PTY** *(Phase 11,
   2026-05-02).* The session starts healthy, processes inbound DMs,
   posts `mcp__plugin_telegram_telegram__reply` outputs, and emits
   a `stop` event. Then it goes quiet — the next inbound DM never
   produces a `prompt_submit` event, no `MCP server failed` line
   appears, no error of any kind. The process keeps running and
   accumulates CPU time but the channel-poll loop never wakes.
   Hypothesis: the runtime needs a TTY-side nudge (keystroke / TUI
   repaint) to schedule the next poll, and `script(1)`'s pipe-to-
   file pseudo-PTY doesn't supply one. tmux's full PTY appears to
   not have this problem (still under observation).
3. **Typing-but-not-sending under tmux without skip-permissions**
   *(Phase 11, 2026-05-03).* The session boots, accepts an inbound
   DM, emits `prompt_submit`, Claude tries to call
   `mcp__plugin_telegram_telegram__reply` and Gmail MCP tools — and
   the harness **denies** them because the freshly-spawned session
   has no inherited grants and no human at the TTY to approve. The
   `stop` event fires with response text like *"Both actions were
   blocked by the harness: Gmail search denied, Telegram reply
   denied"*. From Telegram's side: the bot shows the typing
   indicator briefly then nothing arrives. **Fix:**
   `--dangerously-skip-permissions` on the tmux command (Step C
   above).

**Recovery shortcut — kill + respawn.** For all three failure modes,
kill the wedged session and re-launch (preferably in tmux). Telegram
queues inbound DMs at the API level, so a fresh session picks up the
backlog on its first poll — you'll see delayed "Paired!" / delayed
reply messages arrive once it's healthy. If a respawn also wedges
immediately, the issue isn't the backgrounding harness — check
`.env`, `access.json`, and the channel plugin install state.
