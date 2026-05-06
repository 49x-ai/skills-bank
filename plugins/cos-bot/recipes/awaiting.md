# Recipe — `/awaiting` (on-demand, or Tue + Thu 10am)

> Canonical body for the `/awaiting` slash command. Standalone follow-up
> tracker. The `/shutdown` recipe touches this; `/awaiting` makes it a
> first-class surface so you can ask "what's open right now?" mid-day.

## Routine metadata (for `/schedule`)

- **Name:** `awaiting`
- **Cron (optional):** `0 10 * * 2,4` (Tue + Thu at 10am)
- **Agent to invoke:** `chief-of-staff`
- **Output target:** your Telegram chat-id

## Slash-command body

Paste into `chiefofstaff/.claude/commands/awaiting.md`:

```markdown
---
description: Follow-up tracker — who's waiting on me, who I'm waiting on, what's stale.
allowed-tools: Bash, Read, Grep
---

# /awaiting

Output 3 sections — **Awaiting my reply**, **Awaiting their reply**,
**Stale (>5 days)** — in that order. No preamble. No emoji. Plain text
for Telegram.

1. **Awaiting my reply.** Threads where the latest message is from someone
   else, addressed to me, in the last 14 days. Group by sender. Cap at 8.
   For each: sender, subject, the ask in one phrase, days since their last
   message.
2. **Awaiting their reply.** Threads I sent in the last 14 days where I'm
   waiting for a response. Group by recipient. Cap at 8. For each:
   recipient, subject, what I asked them, days since I sent.
3. **Stale (>5 days).** A combined list of items from sections 1 and 2 that
   are older than 5 days. Flag each as `→ nudge` (their reply) or
   `→ apologize-and-respond` (my reply).

Hard rule: do not draft replies, do not draft nudges. This is a list, not
a queue of actions. If I want a draft, I'll ask.
```

## When the routine fires

- **On-demand:** the most-used path. DM "what am I waiting on?" mid-day.
- **Scheduled:** Tue + Thu at 10am. Twice a week is the right beat — daily
  is noise, weekly is too rare. Tue catches Monday's open loops; Thu
  catches the week's stragglers before Friday review.

## Why this recipe matters

The single biggest source of CEO embarrassment is "I owe you a reply"
arriving too late. `/awaiting` makes that surface continuous. It's also a
useful **anti-procrastination** tool: most people delay replies because
they don't have a list — once it's a 3-bullet "stale" section, replying
takes 10 minutes.

## Customizing

- **Too many threads?** Filter both lists by sender role (VIPs only).
- **Slack instead of email?** Add a section pulling open Slack DMs where
  the latest message is from someone else.
- **Want drafts?** Don't add them here — instead, see `/draft <thread>` in
  the additional-ideas section.
