# skills-bank

**Public Claude Code plugins from [49x.ai](https://49x.ai) — an AI Studio shipping custom AI workflows.**

A [Claude Code marketplace](https://docs.claude.com/en/docs/claude-code/plugin-marketplaces)
that bundles the plugins we build for ourselves and our clients, then publish when
they're useful past one project.

## Add the marketplace

In any Claude Code session:

```
/plugin marketplace add 49x-ai/skills-bank
```

Then install individual plugins from the list below.

## What's inside

### cos-bot  ·  v0.1.0

**Compresses the 25-minute Telegram-bot bootstrap into a guided, resumable skill — and installs five Chief-of-Staff recipe commands on the way out.**

- **For:** anyone wiring a personal Telegram bot to Claude Code, or standing up a lightweight Chief-of-Staff workflow on top of it.
- **Key commands:**
  - `/cos-bot:setup` — drives BotFather end-to-end (Claude for Chrome or `chrome-devtools-mcp`), captures the token, hands it to `/telegram:configure`, walks you through pairing.
  - `/cos-bot:install-recipes` — installs `/prep`, `/inbox-triage`, `/awaiting`, `/who`, `/catchup` as personalized commands in your project, with a small profile pass so they fit your stack and tone.
- **Install:**
  ```
  /plugin install cos-bot@49x-skills
  ```
- **Details:** [plugins/cos-bot/](plugins/cos-bot/)

> Requires the `telegram@claude-plugins-official` plugin for the configure and pair steps. `cos-bot` detects it on startup and offers to install it if missing. The bundled `chrome-devtools-mcp` server registers automatically.

## Built by 49x.ai

[49x.ai](https://49x.ai) is an AI Studio. We design and ship custom AI workflows for
operators and teams — the skills in this marketplace are the reusable pieces that
fall out of that work.

If you want help applying AI to your own business — strategy, prototyping, or
shipping the production version of something like one of these skills —
[talk to us at 49x.ai](https://49x.ai).

## Roadmap

Driven by client work, so the queue shifts. If there's a skill you'd want us to
publish, [open an issue](https://github.com/49x-ai/skills-bank/issues).
