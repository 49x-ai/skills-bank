# cos-bot

A Telegram bot that's also a Chief of Staff.

DM it `/catchup` after a long weekend and it tells you what you missed.
Schedule `/brief` for 8am and it pings your phone with the day's
calendar, top emails, and one thing you might miss. Tell it
`/who jane@acme.com` before a meeting and it builds the dossier. It
drafts in your voice. It never auto-sends.

About five minutes from install to a paired bot DMing you back.

## Quickstart

In any Claude Code session:

```
/plugin marketplace add 49x-ai/skills-bank
/plugin install cos-bot@49x-skills
/reload-plugins
```

Then run:

```
/cos-bot:start
```

That's it. `/cos-bot:start` looks at where you are — no token? token
but not paired? recipes not installed yet? — and tells you the next
command. Most paths: paste your BotFather token → install five recipes
with defaults → fire a demo. Four-ish question moments and you're
done.

If you don't have a Telegram bot yet, `/cos-bot:start` routes you to
`/cos-bot:setup`, which drives `@BotFather` end-to-end so you don't
have to.

## What the bot can do

Five recipes the installer drops into your project. Schedule them or
fire on demand.

| Command | Does this |
|---|---|
| `/prep <meeting?>` | Pre-meeting brief — attendees, history, three questions to ask |
| `/inbox-triage` | Reply now / FYI / Skip — with optional 2-3 sentence drafts |
| `/awaiting` | Who owes me, who I owe, what's stale |
| `/who <person>` | Relationship 360 dossier |
| `/catchup <duration?>` | "I've been off for X days — what did I miss?" |

Plus four spine recipes (`/brief`, `/shutdown`, `/weekly-review`,
`/tackle`) you can paste in manually from `recipes/`.

Every reply is Telegram-shaped: plain text, no markdown headers, no
emoji, scannable on a phone. Drafts are labeled `DRAFT — not sent`
and the agent never decides for you.

## Make it sound like you

Four knobs — formality, proactivity, name, reasoning hint — and three
presets that pin all four:

- **MBB Consultant** — formal, proactive, conclusion-first
- **Warm Exec Assistant** — friendly, reactive, plain prose
- **Blunt Chief of Staff** — terse, proactive, sharp editorial

```
/cos-bot:install-recipes persona mbb       # pick a preset
/cos-bot:install-recipes persona tune      # tune each axis yourself
/cos-bot:install-recipes persona show      # what's set right now
```

The chief-of-staff sub-agent reads your persona on every reply, so
changes apply on the next inbound message — no restart.

## Brain dumps, captured

DM the bot a long message — voice-memo transcript, late-night strategy
thinking, anything ≥200 words — and it's saved verbatim to
`<project>/.claude/projects/<slug>/memory/brain-dumps/` *before* it
gets processed. The reply leads with `captured to
brain-dumps/<filename>`, then carries on with whatever you actually
asked.

On by default. To turn it off:
`/cos-bot:install-recipes persona tune` → set "Brain-dump capture" to
off. Short messages and slash commands aren't captured.

## A memory system, not just a transcript

Brain-dump capture saves raw inbound messages. A *memory system* is the
curated, durable layer on top — a `memory/` folder at your project root
the bot reads before meaningful work and writes back to over time.

```
/cos-bot:install-memory             # guided — pick a preset, toggle folders
/cos-bot:install-memory standard    # fast install, no questions
/cos-bot:install-memory minimal     # just MEMORY.md, active.md, inbox/
/cos-bot:install-memory full        # people, companies, prompts, archive, search
```

It installs a self-contained tree at your project root:

```
memory/
  MEMORY.md       index + folder guide
  active.md       current focus, open loops
  decisions.md    durable decisions + rationale
  workflows.md    recurring ways of working
  projects/  people/  companies/  prompts/
  inbox/          freeform capture — monthly YYYY-MM.md files
  archive/        stale memory, excluded from search
PROTOCOL.md       how the bot should use memory
scripts/memory-search.sh   ripgrep over memory/
```

Three presets — **Minimal**, **Standard** (default), **Full** — then a
multi-select to toggle individual folders. The installer **never
overwrites an existing memory file**: re-run it any time to add
components, and your curated content is safe. It also offers a recurring
`/compact-memory` routine (via `/cos-bot:autopilot`) that folds your
inbox into durable files on a weekly cadence.

Standalone — run it whenever; it isn't part of the `/cos-bot:start`
chain.

## Running the bot

For DMs to actually reach Claude, launch with the channels flag:

```bash
claude --channels plugin:telegram@claude-plugins-official
```

`/cos-bot:setup` and `/cos-bot:connect` will background this in tmux
for you if it's available. Without the flag, the Telegram MCP server
isn't running and your bot stays silent.

## The skills

`/cos-bot:start` is the only one most users need. The rest are also
user-invocable for re-runs and edge cases.

| Skill | When to run it |
|---|---|
| `/cos-bot:start` | You don't know which to pick — let it decide |
| `/cos-bot:setup` | You don't have a bot yet (drives BotFather end-to-end) |
| `/cos-bot:connect` | You have a BotFather token already (fast path) |
| `/cos-bot:install-recipes` | Drop the recipe slash-commands into your project |
| `/cos-bot:install-memory` | Install a Markdown memory system at your project root |
| `/cos-bot:demo` | Fire one recipe right now and DM the result |
| `/cos-bot:autopilot` | Put a recipe on a local self-rescheduling loop (`daily 9am`, `every 2h`, adaptive, etc.) — survives terminal exit |

All resumable. All idempotent. State lives in
`~/.claude/channels/telegram/`.

## Troubleshooting

**`/cos-bot:start` not found.** Run the quickstart block above and
`/reload-plugins`.

**`/telegram:configure` not found.** The official `telegram` plugin
isn't installed. Run `/plugin install
telegram@claude-plugins-official`, then re-run cos-bot — it resumes
where it left off.

**Bot doesn't reply to DMs.** Channel server probably isn't running.
Restart Claude Code with `claude --channels
plugin:telegram@claude-plugins-official` from the project directory.

**Bot replies but doesn't recognize my slash commands.** The channel
session was launched before the recipes were written. Restart the
session.

**Need to start over.** `/cos-bot:setup reset` clears state. The bot
itself stays on Telegram — `@BotFather` and `/deletebot` removes it
for real.

## Recurring tasks (local, not cloud)

cos-bot recipes are inherently local — they post through your local
Telegram bot and shell out to `claude -p` on your machine. That rules
out `/schedule` (its routines run as remote agents on Anthropic infra
with no access to your local bot directory).

Use `/cos-bot:autopilot` instead. It scaffolds a self-rescheduling
slash command that runs locally, posts results to your Telegram, and
survives terminal exit:

```
/cos-bot:autopilot /prep daily 9am
/cos-bot:autopilot /inbox-triage at 11:00,15:00 weekdays stop_by 2026-12-31
/cos-bot:autopilot /awaiting adaptive max_runs 50
/cos-bot:autopilot list
/cos-bot:autopilot stop prep-autopilot
```

A supervisor auto-installs on first arm and health-checks every 30
minutes. After a reboot, a `SessionStart` hook re-arms everything when
you next open Claude Code.

## Under the hood

If you want to know what's happening:

- **`/cos-bot:setup`** drives `@BotFather` (`/newbot`, name, username,
  description, about text, commands menu, privacy), captures the
  token, hands it to `/telegram:configure`, backgrounds the channel
  server (tmux preferred, `script(1)` fallback), walks pairing. Six
  steps, resumable. Two execution modes: **claude-for-chrome** (uses
  your existing extension and Telegram login — fastest) or
  **chrome-devtools-mcp** (drives an isolated Chromium via the bundled
  MCP — one-time QR login).
- **`/cos-bot:connect`** is the same flow minus BotFather and
  metadata. For users who already have a token.
- **`/cos-bot:install-recipes`** reads canonical recipe bodies bundled
  with the plugin, optionally walks a profile pass (VIPs, persona,
  stack, internal/external mix), applies deterministic string-edit
  transforms, writes personalized command files into
  `<your-project>/.claude/commands/`, persists answers as typed memory
  so future sessions inherit them, and offers to schedule the routines
  via `/schedule`. Pass `all` for stock defaults, a single slug for one
  recipe, or no arguments for the full interactive flow.

## What's bundled

- `chrome-devtools-mcp` — auto-registered with this plugin.
- `telegram@claude-plugins-official` — *not* auto-installed; the
  skills offer to install it on first run.
- Claude for Chrome — uses your existing extension if installed; never
  installed by this plugin.

## Uninstall

```
/plugin uninstall cos-bot@49x-skills
```

The bot, token, and allowlist all stay functional — only the
bootstrapping skills go away. Re-install any time to create another
bot or re-pair an existing one.

## Out of scope (v1)

- `/setuserpic`, `/revoke`, `/deletebot`
- payment providers, business bots, mini apps
- multi-bot management (`telegram` is one-token-per-state-dir)
- a teardown skill (revoke + delete + clear state) — on the roadmap
