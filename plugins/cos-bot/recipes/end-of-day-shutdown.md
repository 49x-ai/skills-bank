# Recipe — End-of-day shutdown (6pm, weekdays)

> Canonical body for the `/shutdown` slash command and the Stage 5 S routine. Paste from here; customize lightly.

## Routine metadata (for `/schedule`)

- **Name:** `end-of-day-shutdown`
- **Cron:** `0 18 * * 1-5` (every weekday at 6pm local time)
- **Agent to invoke:** `chief-of-staff`
- **Output target:** your Telegram chat-id

## Slash-command body

Paste into `chiefofstaff/.claude/commands/shutdown.md`:

```markdown
---
description: End-of-day shutdown — wins, tomorrow's top 3, who's waiting on whom.
allowed-tools: Bash, Read, Grep
---

# /shutdown

Output 4 sections — **Today's wins**, **Tomorrow's top 3**, **Awaiting my reply**, **Awaiting other people's reply** — in that order. No preamble. No emoji. Plain text suitable for a Telegram DM.

1. **Today's wins.** Three bullets max. Pull from:
   - Today's calendar (meetings that ended).
   - Linear issues moved to Done today.
   - Sent Gmail threads where I closed a loop.
2. **Tomorrow's top 3.** Three bullets max. Pull from:
   - Tomorrow's calendar (any meeting that needs prep).
   - Linear issues with tomorrow as a deadline.
   - Threads I drafted but didn't send.
3. **Awaiting my reply.** Threads where the latest message is from someone else, addressed to me, in the last 48h. Group by sender. Cap at 5.
4. **Awaiting other people's reply.** Threads I sent in the last 7 days where I'm waiting for a response. Flag any older than 5 days as "follow up."

Hard rule: do not draft replies. Do not auto-send anything. The output is a daily list, not a queue of actions.
```

## When the routine fires

6pm local time, every weekday. The agent:

1. Loads its `## Inheritance`.
2. Runs the `/shutdown` body against today's calendar, today's Linear, today's Gmail.
3. Sends the output to Telegram.

You're closing your laptop. The phone buzzes. You read it on the walk home — and now you know what tomorrow morning is, and who's waiting on you.

## Customizing

- **Different time?** Sharpen the cron. Some founders prefer 5pm, some 7pm, some "right before dinner."
- **Wins look padded?** Raise the bar in step 1 — *"a 'win' is a meeting that produced a decision, an issue closed by me personally, or a thread I closed."*
- **"Awaiting other people's reply" too noisy?** Filter by recipient role — only customers + investors + direct reports.

## Variants

The shutdown is the most personal recipe — adapt it to *your* end-of-day. Some founders also want a "what surprised me today" bullet; some want tomorrow's first meeting flagged with prep links; some want an exercise nudge if the calendar shows a sedentary day. Add or remove sections to taste.
