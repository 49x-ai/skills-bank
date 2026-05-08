# Recipe — Morning brief (8am, weekdays)

> Canonical body for the `/brief` slash command. Paste from here;
> customize lightly. The `chief-of-staff` sub-agent inherits this recipe.

## Routine metadata (for `/schedule`)

- **Name:** `brief` (matches the slash command)
- **Cron:** `0 8 * * 1-5` (every weekday at 8am local time)
- **Agent to invoke:** `chief-of-staff`
- **Output target:** your Telegram chat-id (from `~/.claude/channels/telegram/access.json`)

## Slash-command body

Paste this into `.claude/commands/brief.md`:

```markdown
---
description: Morning brief — today's calendar, top 3 emails, open issues assigned to me.
allowed-tools: Bash, Read, Grep
---

# /brief

Run these in parallel and summarize:

1. **Calendar:** today's events from the connected Calendar MCP. Note any meetings I'm leading vs. attending. Flag any meeting that needs prep I haven't done.
2. **Inbox:** the 3 most-important threads from the last 24h where I'm in To: (skip CC).
   Important = thread is from a customer, investor, or direct report, OR the latest message contains a question for me.
3. **Issues:** open Linear issues assigned to me (or open Notion docs in my "Active" view, depending on stack).

Output 4 sections — **Today's calendar**, **Awaiting my reply**, **My open work**, **One thing I might miss** — in that order. Five bullets each, max. No preamble. No emoji. Plain text suitable for a Telegram DM.

The "One thing I might miss" line is your editorial — a meeting I might not have prepped for, a thread that's gone quiet, an overdue issue. One bullet, one sentence.

Hard rule: never auto-reply to anything. If a thread looks urgent, surface it in **Awaiting my reply** — don't act on it.
```

## When the routine fires

The 8am routine invokes the `chief-of-staff` sub-agent with the prompt:

> *"Run /brief and post the result to Telegram chat-id `<your-id>`."*

The agent:

1. Loads its `## Inheritance` (CLAUDE.md sections, hard rules, connections).
2. Runs the `/brief` body above against today's calendar / inbox / issues.
3. Sends the output to your Telegram via the `reply` tool exposed by the channel plugin.

You wake up, check your phone, see the brief. **You did not ask.** That's the workshop.

## Customizing

- **Different time?** Change the cron — `0 7 * * 1-5` for 7am, `0 8 * * 1-7` for every day.
- **Different audience definition?** Sharpen "important" in step 2 — by domain, by sender, by named-VIP list maintained as a `reference` memory.
- **Editorial off?** Drop the *"One thing I might miss"* bullet. It's the spiciest part — some founders love it, some find it noisy.

## Variants

If your stack is different — replace **Linear** with **Notion** in step 3, or skip step 3 entirely if your business doesn't have an issue tracker. The recipe still ships; it just gets shorter.
