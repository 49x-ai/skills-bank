# Recipe — Weekly review (Friday 4pm)

> Canonical body for the Friday weekly review and the Stage 5 D routine. The D variant pairs this with a live `/loop` demo for the closing — see `stage-5-schedule.md`.

## Routine metadata (for `/schedule`)

- **Name:** `weekly-review`
- **Cron:** `0 16 * * 5` (every Friday at 4pm local time)
- **Agent to invoke:** `chief-of-staff`
- **Output target:** your Telegram chat-id

## Slash-command body

Paste into `chiefofstaff/.claude/commands/weekly-review.md`:

```markdown
---
description: Friday weekly review — what landed, what slipped, what's next week.
allowed-tools: Bash, Read, Grep
---

# /weekly-review

Output 5 sections — **This week's wins**, **What slipped**, **Next week's top 5**, **People to thank**, **One question I should sit with this weekend** — in that order. No preamble. No emoji. Plain text suitable for a Telegram DM, but it's longer than `/brief` — up to ~12 short paragraphs.

1. **This week's wins.** Five bullets max. Pull from the last 7 days:
   - Linear issues closed (group by project).
   - Sent Gmail threads where I closed a loop with a customer/investor/direct report.
   - Calendar meetings that produced a decision (you'll have to infer — flag uncertainty).

2. **What slipped.** Three bullets max:
   - Linear issues with deadlines this week that didn't move.
   - Threads in **Awaiting my reply** that aged past 5 days.
   - Meetings that got moved twice or canceled.

3. **Next week's top 5.** Five bullets max. Pull from:
   - Next week's calendar (meetings that need prep — list the prep).
   - Linear issues with deadlines next week.
   - Threads I drafted this week but haven't sent.

4. **People to thank.** Up to 3 names. People who unblocked me this week. Not a draft of the thank-you — just the name + the thing.

5. **One question I should sit with this weekend.** One bullet, one paragraph. Your editorial. Pull from patterns: did the same problem show up in 3 customer threads? did 4 of my meetings this week cover the same topic? what does the calendar say about my time vs. what I said I'd protect this week?

Hard rule: do not draft replies, do not draft thank-yous, do not auto-send anything. This is reflection, not action.
```

## When the routine fires

Friday at 4pm. You're winding down. The phone buzzes. You read the review on the way out — and now you have a question to sit with over the weekend.

## D-variant — paired with a live `/loop` demo

In Stage 5 D, you also fire `/loop 2m /brief` from your terminal during the closing window. The `/loop` is the **see-it-fire-now** demo; the weekly review is the **lands-on-Friday** routine. Together they show:

- Scheduled = unprompted, future cadence (workshop's payoff).
- Loop = ad-hoc, immediate cadence (workshop's climax — phone-buzz in the room).

## Customizing

- **Different day?** Some founders prefer Sunday afternoon. Cron: `0 16 * * 0`.
- **Don't want the "One question" bullet?** Drop it. It's the spiciest part — some founders find it indispensable, others find it pseudo-deep.
- **More than 5 wins/top-5?** The cap is opinionated — five is plenty. If you want more, ask yourself what's actually a top-five.

## Variants

The weekly review is the recipe most worth iterating on. Founders' weeks are different shapes. Some want a board-meeting-ready summary on Mondays (move the cron, add a "metrics" section pulling MRR/runway from a Notion doc). Some want a Friday review *and* a Monday plan (two routines, two recipes). Start with one — make it earn its keep — then add.
