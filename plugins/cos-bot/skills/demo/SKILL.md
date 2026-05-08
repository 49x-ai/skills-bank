---
name: demo
description: Fire one installed Chief of Staff recipe right now and DM the result to your Telegram. Picks the most demo-friendly recipe automatically (catchup → awaiting → inbox-triage → prep). Converts "I configured a thing" into "the thing just worked." Use when the user finishes /cos-bot:install-recipes and wants to see the bot reply end-to-end, or asks to "test my bot," "see it work," or "fire a recipe through Telegram."
user-invocable: true
allowed-tools:
  - Read
  - AskUserQuestion
  - Bash(ls *)
  - Bash(cat *)
  - Bash(test *)
  - Bash(pwd)
  - Bash(claude --permission-mode bypassPermissions -p)
  - Bash(printf *)
---

# /cos-bot:demo — Fire one recipe end-to-end

A small skill that proves the loop. After `/cos-bot:install-recipes`,
this skill picks the most useful recipe to demo, asks once, fires it
via a nested `claude -p`, and lets the result land in your Telegram DM
a minute or two later.

This is intentionally a separate skill from the installer — the install
flow can run before pairing is complete (a valid path), and the demo is
gated on Telegram pairing existing. Splitting them keeps both flows
short.

Arguments passed: `$ARGUMENTS`

---

## Dispatch on arguments

Parse `$ARGUMENTS` (space-separated). Recognize:

- *(empty)* — auto-pick the most demo-friendly recipe in
  `<project>/.claude/commands/`. Run the offer + fire flow.
- `<name>` — one of `prep`, `inbox-triage`, `awaiting`, `who`,
  `catchup`. Skip the auto-pick and use this recipe instead. Still
  asks once before firing.
- *(unrecognized)* — show usage and stop:
  `/cos-bot:demo [prep|inbox-triage|awaiting|who|catchup]`.

---

## Step 0 — prerequisites

1. `pwd` → projectDir.
2. `test -d <projectDir>/.claude/commands/`. If absent, abort with a
   pointer to run `/cos-bot:install-recipes` (or `/cos-bot:start`)
   first.
3. **Check for a connected Telegram channel.** Read
   `~/.claude/channels/telegram/access.json` (mode 0600) and look for
   the user's chat-id. If the file is missing, has no chat-id, or no
   pairing has happened, abort with one line:

   ```
   Telegram isn't paired yet. Finish /cos-bot:setup (or /cos-bot:connect),
   pair via DM, then re-run /cos-bot:demo.
   ```

---

## Step 1 — pick the recipe

If `$ARGUMENTS` is non-empty, validate it points at an installed
recipe (`<projectDir>/.claude/commands/<name>.md` exists). If not,
abort with a pointer to install it first.

If empty, auto-pick. Inspect `<projectDir>/.claude/commands/` and
choose the first match in this preference order:

1. `catchup` — best first impression; answers "what did I miss?"
2. `awaiting` — short, scannable, doesn't depend on calendar/email
   coverage being perfect.
3. `inbox-triage` — solid demo if email is connected.
4. `prep` — only useful with a meeting in the next few hours; prefer
   the others.
5. `who` — needs an argument, skip for the auto-pick.

If none of `catchup` / `awaiting` / `inbox-triage` / `prep` is
installed, abort with:

```
None of the demo-friendly recipes are installed. Run
/cos-bot:install-recipes to install one of: catchup, awaiting,
inbox-triage, prep.
```

---

## Step 2 — offer

One `AskUserQuestion`:

> Want me to fire `/<chosen>` right now? It runs in the background and
> DMs the result to your Telegram in a minute or two — proves the loop
> end-to-end. (You can always run it manually later from this
> directory.)
>
> - **Yes — fire `/<chosen>` now**
> - **No — I'll trigger it myself later**

If **No**, print: *"Got it — when you're ready, DM `/<chosen>` to the
bot or run `/cos-bot:demo <chosen>` from this directory."* Stop.

---

## Step 3 — authorize + fire

If yes, ask for nested-`claude -p` authorization (mirrors
`/cos-bot:install-recipes` schedule step):

> To fire the recipe, I need to spawn a nested `claude -p` with
> `--permission-mode bypassPermissions` so it can run without an
> approval prompt. Authorize?
>
> - **Yes — use claude -p with bypassPermissions**
> - **No — print the command and I'll run it myself**

If yes, run (single one-shot, fire-and-forget):

```
printf 'Run /<chosen> and post the result to my Telegram chat-id <chat-id>.\n' \
  | claude --permission-mode bypassPermissions -p
```

Pull `<chat-id>` from `~/.claude/channels/telegram/access.json`. Don't
wait for the recipe to finish — the DM lands when the recipe completes.

If no, print the exact command:

```
echo 'Run /<chosen> and post the result to my Telegram chat-id <chat-id>.' \
  | claude --permission-mode bypassPermissions -p
```

Print: *"Fired `/<chosen>`. Result will land in your Telegram DM
shortly."*

---

## Step 4 — channel-server reminder (conditional)

If a `--channels` session is running (best-effort: check for `tmux
has-session -t cos-bot` or similar), append:

> Heads up: if you DM the bot a slash command (e.g. `/<chosen>`) and
> it doesn't recognize it, the channel session was launched before
> these recipe files were written. Restart the session to pick them
> up. The fire just now works regardless — it spawns its own
> `claude -p` that reads `.claude/commands/` at boot.

Otherwise omit this section.

---

## Implementation notes

- **One demo per invocation.** The skill fires exactly one recipe. If
  the user wants to try several, they can re-run `/cos-bot:demo
  <name>`.
- **Slash commands aren't tool calls.** Same caveat as the rest of the
  cos-bot suite — recipes in `.claude/commands/` are dispatched by
  the harness, not directly callable. The nested `claude -p` is the
  workaround.
- **No state file.** The skill is short and re-runnable. A killed run
  loses nothing durable.
- **Auto-pick is conservative.** `who` needs an argument; `prep` is
  meeting-specific; `catchup` works on any day at any time. The
  preference order optimizes for "user sees something useful right
  now," not for "showcase every feature."
- **Don't infer intent.** If the user passed an unrecognized argument,
  show the usage line and stop. Don't fall through to the auto-pick
  when an argument was given but wasn't valid.
