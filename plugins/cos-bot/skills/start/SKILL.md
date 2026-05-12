---
name: start
description: One-command entry point for "I want a Chief of Staff bot." Inspects current state (token configured? paired? recipes installed?) and chains the right next step (setup OR connect → install-recipes with defaults → demo). Run when the user says "set up cos-bot," "I want the chief of staff thing," "start cos-bot," or doesn't yet know which sub-skill to run.
user-invocable: true
model: haiku
allowed-tools:
  - Read
  - AskUserQuestion
  - Bash(ls *)
  - Bash(cat *)
  - Bash(test *)
  - Bash(pwd)
  - Bash(grep *)
---

# /cos-bot:start — Orchestrator entry point

A thin top-level skill that compresses the "decide what to run next"
decision into a single command. Inspects state and dispatches:

- No token configured → `/cos-bot:setup` (BotFather drive) or
  `/cos-bot:connect` (paste-your-token), user picks.
- Token configured, not paired → `/cos-bot:connect` resumes at
  relaunch / pair.
- Paired, no recipes installed → `/cos-bot:install-recipes` with the
  defaults-first lead.
- Paired and recipes installed → `/cos-bot:demo` to fire one and
  prove the loop.

Each downstream skill remains user-invocable for power users, re-runs,
and edge cases. This orchestrator is the headline path.

Arguments passed: `$ARGUMENTS` *(reserved — currently unused; the skill
is state-driven. Future: `/cos-bot:start force-setup`, etc.)*

---

## Step 0 — inspect state

Run these checks in order. Each populates a flag.

### Token configured?

Check `~/.claude/channels/telegram/.env` for a populated
`BOT_TOKEN` or `TELEGRAM_BOT_TOKEN` line matching
`(BOT_TOKEN|TELEGRAM_BOT_TOKEN)=\d+:[A-Za-z0-9_-]{30,}`.

- File missing or no token line → `state.tokenConfigured = false`.
- Token line present → `state.tokenConfigured = true`.

### Paired?

Read `~/.claude/channels/telegram/access.json` (mode 0600) if present.
Look for at least one entry under `allowFrom` (or whatever the
telegram plugin's "the user is paired" signal is — see
`/telegram:access` for the canonical schema).

- File missing or `allowFrom` empty → `state.paired = false`.
- At least one allowed sender → `state.paired = true`.

### Recipes installed?

`pwd` → projectDir. List `<projectDir>/.claude/commands/`. Match the
five recipe filenames: `prep.md`, `inbox-triage.md`, `awaiting.md`,
`who.md`, `catchup.md`.

- None present → `state.recipesInstalled = false`.
- At least one present → `state.recipesInstalled = true`. Capture the
  list in `state.installedRecipes` (used for the demo step's
  preference order).

### Channel session running?

Best-effort: `tmux has-session -t cos-bot 2>/dev/null` or check for a
`claude --channels` process via `pgrep -f 'claude .*channels'`. This
is informational only — surface it in the summary, don't gate on it.

- Detected → `state.channelSession = "tmux" | "process"`.
- Not detected → `state.channelSession = null`.

---

## Step 1 — print state summary

Before dispatching, give the user a one-screen view:

```
cos-bot state:
  Token configured: <yes | no>
  Paired:           <yes (sender <ID>) | no>
  Recipes installed: <count>/5  (<list> | none)
  Channel session:  <tmux | process | not running>

Next step: <picked-skill>
```

Keep it scannable — four lines plus the dispatch line.

---

## Step 2 — dispatch

Branch on the flags. The user will run the picked skill — this
orchestrator does **not** dispatch via nested `claude -p`. It just
tells the user the right next command.

### Case A: no token

`state.tokenConfigured === false`.

Ask:

> Do you already have a Telegram bot token from BotFather, or do you
> need to create a bot first?
>
> - **I have a token** → `/cos-bot:connect`
> - **Create a new bot** → `/cos-bot:setup`
> - **I'm not sure** → see the README's *Two ways in*

Print the picked command literally: *"Run `/cos-bot:connect` next."*
(or `/cos-bot:setup`). Stop. Don't auto-dispatch.

### Case B: token configured, not paired

`state.tokenConfigured === true && state.paired === false`.

Print: *"Token is configured but no Telegram pairing yet. Run
`/cos-bot:connect` — it'll detect the existing token and skip straight
to relaunch + pair."* Stop.

### Case C: paired, no recipes installed

`state.paired === true && state.recipesInstalled === false`.

Print: *"Bot is paired and ready. Next: install recipes. Run
`/cos-bot:install-recipes` — the lead question is "all five with
defaults" so most users finish in ~4 questions."* Stop.

### Case D: paired and recipes installed

`state.paired === true && state.recipesInstalled === true`.

Print: *"Bot is paired and `<count>` recipes are installed. To prove
the loop end-to-end, run `/cos-bot:demo` — fires one recipe right now
and DMs the result. Or run `/cos-bot:install-recipes` to add or tune
recipes."* Stop.

If `state.channelSession === null` and recipes are installed, append a
nudge: *"You'll need a `claude --channels …` session running for
inbound DMs to reach the bot. See the README's *After setup — using
the bot* section."*

### Case E: paired, no token (degenerate state)

This shouldn't happen — pairing requires the channel server, which
requires a token. If observed, surface it as a corruption hint:

> State looks inconsistent — `access.json` has a paired sender but
> `.env` has no token. Either the `.env` was deleted manually, or
> pairing was forced. Run `/cos-bot:connect` to reconfigure.

---

## Step 3 — finalize

After dispatching, persist nothing. The orchestrator is stateless —
each invocation re-inspects state and re-prints the dispatch.

If the user wants to re-run after completing a step, they can call
`/cos-bot:start` again and it'll advance to the next branch.

---

## Implementation notes

- **The orchestrator does not dispatch via nested `claude -p`.** It
  tells the user the right next command. Auto-dispatching the chain
  would multiply nested-permissions complexity (each downstream skill
  has its own auth prompts) and obscure what's happening. The user
  types one command per branch, sees the prompts, learns the flow.
- **State checks are read-only.** Don't `mkdir`, don't write anything.
  This skill is a read-only state-detector + dispatcher.
- **No assumptions about future state.** The skill always re-inspects
  on every invocation. Re-running after a downstream step succeeds is
  the supported way to advance.
- **Each downstream skill stays user-invocable.** Power users can skip
  the orchestrator entirely; they probably already know which command
  they want. The orchestrator is for "I just want a chief of staff
  bot" first-timers.
- **`/cos-bot:start` is not the only entry point.** The README still
  documents `/cos-bot:setup`, `/cos-bot:connect`,
  `/cos-bot:install-recipes`, `/cos-bot:demo` as standalone. The
  orchestrator just makes the headline path one command.
