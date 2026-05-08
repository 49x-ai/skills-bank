# cos-bot — Guided Telegram bot setup + Chief of Staff recipes

A plugin that compresses the Telegram bot bootstrap into a guided,
resumable skill. Hands off to the official `telegram` plugin's
`/telegram:configure` and `/telegram:access pair` for the parts they
already do well, and covers the parts they don't (BotFather drive,
metadata, channel-server backgrounding, pairing UX).

## Two ways in

Pick the one that matches your starting state:

- **Don't have a bot yet:** `/cos-bot:setup` — drives BotFather
  end-to-end (`/newbot`, metadata, the works), captures the token,
  configures, relaunches, pairs.
- **Already have a token from BotFather:** `/cos-bot:connect` — the
  fast path. Skips BotFather drive and metadata, goes straight to
  configure → relaunch → pair.

Both share state at `~/.claude/channels/telegram/.cos-bot-setup.json`,
so you can switch mid-flow if you picked the wrong one.

This plugin also ships `/cos-bot:install-recipes` — a guided installer
for five Chief-of-Staff recipe commands (`/prep`, `/inbox-triage`,
`/awaiting`, `/who`, `/catchup`). The installer reads
canonical recipe bodies bundled with the plugin, walks the user
through a small profile pass (VIPs, draft tone, stack,
internal/external mix) and per-recipe deltas, applies deterministic
transforms, writes personalized command files into
`<your-project>/.claude/commands/`, persists the durable answers as
typed memory so future sessions and recipes inherit them, and offers
to schedule the routines via `/schedule`. Pass `all` for stock
defaults (`/cos-bot:install-recipes all`), a single slug for one
recipe (`/cos-bot:install-recipes prep`), or run with no arguments
for the full interactive flow. State persists alongside the setup
skill's at `~/.claude/channels/telegram/.cos-bot-recipes.json` and
the install is idempotent and resumable.

## What `/cos-bot:setup` does

`/cos-bot:setup` walks you through six steps:

1. **intake** — 7 questions about the bot (display name, username,
   description, about text, commands menu, group privacy, allow-groups).
2. **create** — drives `@BotFather`'s `/newbot` to register the bot and
   capture the token.
3. **metadata** — drives `/setdescription`, `/setabouttext`, `/setcommands`,
   `/setprivacy`, `/setjoingroups` from your intake answers.
4. **configure** — invokes `/telegram:configure <token>` (the existing
   plugin) to write `~/.claude/channels/telegram/.env`.
5. **relaunch** — prints the exact `claude --channels …` invocation and
   waits for you to confirm.
6. **pair** — instructs you to DM your bot for a pairing code, run
   `/telegram:access pair <code>`, and offers to lock down with
   `/telegram:access policy allowlist`.

State persists at `~/.claude/channels/telegram/.cos-bot-setup.json` (mode
`0600`). Re-running `/cos-bot:setup` resumes at the last incomplete step.
`/cos-bot:setup reset` clears state. `/cos-bot:setup step <name>` jumps to
a specific step (debug only).

If you start `/cos-bot:setup` and it detects an existing token at
`~/.claude/channels/telegram/.env`, it offers to redirect you to
`/cos-bot:connect` (the faster path for that case). Decline if you want
to overwrite the existing token with a new bot.

## What `/cos-bot:connect` does

`/cos-bot:connect` is the fast path for users who already have a token
from BotFather. It runs three steps from the same shared state file:

1. **configure** — invokes `/telegram:configure <token>` to write
   `~/.claude/channels/telegram/.env`.
2. **relaunch** — backgrounds `claude --channels …` (tmux preferred,
   `script(1)` fallback) or asks you to `/exit` + relaunch.
3. **pair** — DM the bot, run `/telegram:access pair <code>`, optionally
   lock down with `/telegram:access policy allowlist`.

It detects an already-populated `.env` at startup and offers to skip
straight to relaunch + pairing — useful when re-pairing after a plugin
uninstall or token rotation done elsewhere.

The connect skill does **not** drive BotFather and does **not** set bot
metadata (description / about / commands / privacy). If you want to
update those on an existing bot, message `@BotFather` directly with
`/setdescription`, `/setabouttext`, `/setcommands`, `/setprivacy`, and
`/setjoingroups`.

## Two execution modes

The skill picks one at first run and persists the choice:

- **claude-for-chrome** (default when available) — the skill writes a
  fully-substituted prompt to
  `~/.claude/channels/telegram/.cos-bot-setup-prompt.md` and asks you to
  paste it into a [claude.ai](https://claude.ai) tab with the Claude for
  Chrome extension active. claude.ai then drives your existing
  `web.telegram.org` BotFather conversation and returns the token in a
  marked block. You paste the block back into your Claude Code session.
  Uses your existing Telegram login. Fastest path.
- **chrome-devtools-mcp** (fallback) — the skill drives a Chrome window
  directly via the `chrome-devtools` MCP server. Works without the Claude
  for Chrome extension. The MCP launches an **isolated Chromium** that
  doesn't share your everyday Chrome profile, so a one-time QR login is
  expected: the skill screenshots the QR code, you scan it from your
  phone (Telegram → Settings → Devices → Link Desktop Device), and the
  skill picks up once login completes.

The skill auto-detects which surfaces are available and offers the right
choice. You can also switch modes mid-flow if one stalls — your intake is
preserved.

## Install

The plugin lives in the public `49x-ai/skills-bank` marketplace. In any
Claude Code session:

```
/plugin marketplace add 49x-ai/skills-bank
/plugin install cos-bot@49x-skills
/reload-plugins
```

`/plugin list` should then show `cos-bot@49x-skills` as enabled, and
both `/cos-bot:setup` and `/cos-bot:connect` are available.

### What gets installed alongside

- **`chrome-devtools-mcp`** — bundled via this plugin's `.mcp.json`.
  Auto-registered when cos-bot is enabled; no manual MCP setup needed.
  This is the fallback browser-automation surface (see *Two execution
  modes* above).
- **`telegram@claude-plugins-official`** — **not** auto-installed. The
  skill detects whether it's enabled at startup and offers to install
  it for you (`/plugin install telegram@claude-plugins-official`).
  Required for steps 4 (configure) and 6 (pair).
- **Claude for Chrome** — the extension lives in your everyday browser.
  The skill detects it via filesystem markers and uses it as the
  default mode if available; you don't install it via this plugin.

## After setup — using the bot

Once `/cos-bot:setup` (or `/cos-bot:connect`) finishes, the bot is fully
wired. To use it in any future Claude Code session, launch with the
channels flag:

```bash
claude --channels plugin:telegram@claude-plugins-official
```

Without that flag, the Telegram MCP server isn't running and DMs to
your bot won't reach Claude. Token and allowlist persist in
`~/.claude/channels/telegram/`; the only thing you need to remember is
the launch flag.

The `cos-bot` plugin only exists to bootstrap and reconnect bots. You
can:

- **Leave it installed** — handy if you ever need to create another bot
  (`/cos-bot:setup`), wire a different existing token (`/cos-bot:connect`),
  or re-run pairing.
- **Uninstall it** — via `/plugin uninstall cos-bot@49x-skills`. The
  bot, token, and allowlist all remain functional; only the
  bootstrapping skill goes away.

## Troubleshooting

**`/cos-bot:setup` not found.** The plugin wasn't discovered. Run the
install commands above and `/reload-plugins`.

**`/telegram:configure` not found at step 4.** The official `telegram`
plugin isn't installed. Run `/plugin install telegram@claude-plugins-official`
in this session, then re-run `/cos-bot:setup` — it resumes at `configure`.

**The `--channels` flag must persist after relaunch.** Step 5 prints the
exact command. If you forget the flag, the channel server isn't running and
your bot won't reply to DMs in step 6. Re-launch with the flag.

**Mode stalls (claude.ai tab closed, session expired).** Tell the skill
"switch to MCP" — your intake answers are preserved; the skill re-drives
BotFather via `chrome-devtools-mcp`.

**Username collision.** BotFather rejects usernames already taken. The
skill re-prompts you for a new one — it never auto-derives a variant. Try
something more specific (e.g. `<yourcompany>_cos_bot`).

**Need to start over.** `/cos-bot:setup reset` deletes state. Note: this
does **not** delete the bot from Telegram — for that, message `@BotFather`
and run `/deletebot` manually (out of scope for v1).

## Manual fallback

If the guided skill stalls, message `@BotFather` directly — `/newbot`,
then paste the token into `/telegram:configure <token>`. Same end
state: a paired, locked-down bot with the token in
`~/.claude/channels/telegram/.env`.

## Out of scope (v1)

- `/setuserpic`, `/revoke`, `/deletebot`
- payment-provider configuration, business bots, mini apps
- multi-bot management (`telegram` plugin is one-token-per-state-dir)
- a teardown skill (revoke + delete + clear state) — TODO
