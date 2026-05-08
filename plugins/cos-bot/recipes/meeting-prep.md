# Recipe — `/prep <meeting?>` (30 min before each meeting, or on-demand)

> Canonical body for the `/prep` slash command. Scheduled to fire 30 min before
> each meeting on the calendar; can also be invoked by name on-demand.

## Routine metadata (for `/schedule`)

- **Name:** `prep` (matches the slash command — `/cos-bot:install-recipes`
  uses the slug as the routine name)
- **Trigger:** dynamic — agent reads today's calendar at 7:30am and schedules
  one-shot `/prep` calls 30 min before each meeting. (See "Scheduling" below.)
- **Agent to invoke:** `chief-of-staff`
- **Output target:** your Telegram chat-id

## Slash-command body

Paste into `.claude/commands/prep.md` (or run `/cos-bot:install-recipes prep`):

```markdown
---
description: Prep for a specific meeting — attendees, history, docs, suggested questions.
allowed-tools: Bash, Read, Grep
---

# /prep

Argument: the meeting — a name, a time ("3pm meeting"), or empty (= the next
meeting on my calendar).

1. **Identify the meeting.** Resolve the argument against today's calendar.
   If ambiguous, list the 2-3 candidates and stop.
2. **Pull attendee context.** For each external attendee:
   - Their company (from email domain or signature).
   - The last 3 email threads I've had with them (subjects + dates).
   - Any open Linear issue mentioning them.
3. **Pull meeting context.**
   - Calendar description, attached docs, agenda link.
   - The last meeting with the same attendees (date + my notes if any).
   - Any thread in the last 14 days mentioning the meeting subject.

Then output 4 sections — **Who's there**, **What it's about**, **What's
changed since last time**, **3 questions I should ask** — in that order. No
preamble. No emoji. ≤6 short paragraphs.

The "3 questions" line is your editorial — questions a sharp Chief of Staff
would write on a notecard before walking in. Tag them as suggestions, not
decisions.

Hard rule: do not draft messages to attendees. Do not move or modify the
meeting. Output is read-only prep for me.
```

## Scheduling

There's no built-in "fire 30 min before each calendar event" cron. Two
patterns work:

1. **Daily dispatcher (Q):** at 7:30am every weekday, the `chief-of-staff`
   agent reads today's calendar and queues a one-shot `/schedule` for each
   meeting at `meeting_start - 30m`. Simple, no in-room loop.
2. **`/loop` watcher (D):** a 15-min `/loop` checks the calendar; if a
   meeting starts in the next 30-45 min and hasn't been prepped today, it
   fires `/prep <meeting>`. Stateful (uses a `prepped-today.json` file to
   avoid duplicates).

Pick one. The Q dispatcher is simpler and recommended; the D loop is for
founders whose calendars churn during the day.

## Why this recipe matters

`/brief` tells you *that* you have a meeting at 3pm. `/prep` tells you
*what to walk in with*. The 30-min-ahead beat is when prep is actually
useful — too early and you forget; too late and you can't act. This is the
recipe that most reliably converts "I have an AI assistant" into "I showed
up to that meeting prepared."

## Customizing

- **Internal-only meetings?** Skip step 2's email lookups; pull recent Slack
  thread + Linear instead.
- **Recurring 1:1s?** Add a section: "since our last 1:1 on <date>" with
  threads mentioning the other person.
- **Editorial off?** Drop the "3 questions" section.
