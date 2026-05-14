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

### cos-bot · v0.3

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
- **Local autopilot scheduler** — `/cos-bot:autopilot` puts any recipe
  on a self-rescheduling local loop that survives terminal exit and DMs
  you the result. No cron, no remote agent.
- **Three voice presets** — MBB Consultant, Warm Exec Assistant, Blunt
  Chief of Staff. Tunable down to four axes (formality, proactivity,
  name, reasoning hint).
- **Brain-dump capture** — DM the bot a voice-memo transcript or
  late-night strategy thinking, it's saved verbatim before it gets
  processed.
- **Markdown memory system** — `/cos-bot:install-memory` installs a
  self-contained `memory/` folder at your project root the bot reads
  and writes across sessions. Presets, never overwrites your curated
  files.
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

### gws-proxy · v0.1

**Shared Google Workspace CLI access — no GCP project of your own.**

Get Gmail, Calendar, and Drive on the command line through the
[Google Workspace CLI (gws)](https://github.com/googleworkspace/cli)
without setting up a GCP project, OAuth consent screen, or OAuth client.
All profiles share one OAuth client published by 49x; your refresh
tokens stay encrypted on your machine and the plugin owner never sees
your data.

```
/plugin install gws-proxy@49x-skills
/gws-proxy:add-account personal you@gmail.com
```

`/gws-proxy:add-account` installs the gws CLI if needed, places the
bundled OAuth client, opens a browser for consent, and wires up a
per-account slash command. Each alias (`personal`, `work`, …) gets its
own config dir, wrapper, and `/<alias>` command:

```
/personal gmail users messages list --params '{"userId":"me","maxResults":3}'
/personal calendar events list --params '{"calendarId":"primary"}'
```

[Read the gws-proxy README →](plugins/gws-proxy/)

> Requires your email to be granted `serviceUsageConsumer` on the
> `gws-proxy-49x` GCP project — the plugin owner handles that
> out-of-band. `gcloud` is **not** required; the OAuth flow runs
> entirely in the browser.

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
