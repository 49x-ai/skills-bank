# skills-bank

**Plugins for Claude Code, from [49x.ai](https://49x.ai).**

A small [Claude Code marketplace](https://docs.claude.com/en/docs/claude-code/plugin-marketplaces)
of workflow plugins — the reusable bits that fall out of building custom
AI for our clients. The kind of thing that's annoying enough to wire up
by hand that we'd rather hand you the install command.

## Add the marketplace

In any Claude Code session:

```
/plugin marketplace add 49x-ai/skills-bank
```

Then install whichever plugins you want from the list below.

## Plugins

### cos-bot · v0.2

**A Telegram bot that's also a Chief of Staff.**

DM `/catchup` after a long weekend → it tells you what you missed.
Schedule `/brief` for 8am → it pings your phone with today's calendar,
top emails, and one thing you might miss. Tell it `/who jane@acme.com`
before a meeting → it builds the dossier. Drafts in your voice. Never
auto-sends.

About five minutes from install to a paired bot DMing you back.

```
/plugin install cos-bot@49x-skills
/cos-bot:start
```

`/cos-bot:start` inspects your current state — no token? token but no
pairing? recipes not installed? — and tells you the next command. Most
users finish in ~4 question moments and a demo DM lands on their
phone.

**What's in the box:**

- **Five Chief-of-Staff recipes** — `/prep`, `/inbox-triage`,
  `/awaiting`, `/who`, `/catchup`. Schedule them or fire on demand.
- **Three voice presets** — MBB Consultant, Warm Exec Assistant, Blunt
  Chief of Staff. Tunable down to four axes (formality, proactivity,
  name, reasoning hint).
- **Brain-dump capture** — DM the bot a voice-memo transcript or
  late-night strategy thinking, it's saved verbatim before it gets
  processed.
- **Guided BotFather drive** — `/cos-bot:setup` walks `@BotFather`
  end-to-end via Claude for Chrome (or an isolated MCP-driven Chromium
  fallback). Already have a token? `/cos-bot:connect` skips that step.

Output is Telegram-shaped — plain text, scannable on a phone, no
markdown headers, no emoji. Drafts get labeled `DRAFT — not sent` and
the bot never decides for you.

[Read the cos-bot README →](plugins/cos-bot/)

> Requires `telegram@claude-plugins-official` for the configure + pair
> steps. `cos-bot` detects it on startup and offers to install it if
> missing. The bundled `chrome-devtools-mcp` server registers
> automatically.

## Why we publish these

We're an AI studio — we design and ship custom AI workflows for
operators and teams. When something we build for one client is useful
past that project, we strip it down, harden the UX, and publish it
here.

If you'd want help applying AI to your own business — strategy,
prototyping, or shipping the production version of something like one
of these — [talk to us at 49x.ai](https://49x.ai).

## Roadmap

Driven by client work, so the queue shifts. If there's a workflow
you'd want us to publish, [open an
issue](https://github.com/49x-ai/skills-bank/issues).
