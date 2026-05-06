# Recipe — `/catchup <duration?>` (on-demand)

> Canonical body for the `/catchup` slash command. The "I've been off for
> X, what did I miss?" recipe. Critical after travel, vacation, or a
> 3-hour deep-work block.

## Slash-command body

Paste into `chiefofstaff/.claude/commands/catchup.md`:

```markdown
---
description: What I missed — calendar, email, issues — triaged into Must-act / FYI / Skip.
allowed-tools: Bash, Read, Grep
---

# /catchup

Argument: how long I've been off. Accept "4h", "since friday", "yesterday",
"last week". Default = since the last time `/catchup` ran (or 24h if first
run).

Pull everything that changed in the window:

1. **Calendar.** Meetings I missed (declined-without-response, was-invited-
   but-didn't-attend, marked tentative). Plus any new invites for the next
   7 days that arrived during the window.
2. **Email.** New threads where I'm in To: (skip CC). Don't list them all
   yet — bucket them.
3. **Issues.** Linear issues that changed state, were assigned to me, or
   tagged me, during the window.

Then output 3 sections — **Must act today**, **FYI (catch up when you
can)**, **Skip** — in that order. No preamble. No emoji.

For each **Must act today** item:
- Source (email/calendar/issue) + ID.
- 1-line summary.
- Why it's "must act" — the specific signal (VIP sender, looming
  deadline, stuck blocker).

For **FYI**: 1 line each. Cap at 8.

For **Skip**: count + 1-line reason ("automated", "internal noise",
"resolved while I was out").

Hard rule: do not catch anyone up on my behalf. Do not auto-reply
explaining I was out. Output is for me only.
```

## How it gets invoked

Always on-demand. Common forms:

- `/catchup 4h` — "back from a deep-work block"
- `/catchup since friday` — "back from the weekend"
- `/catchup since 2025-04-15` — "back from a week of travel"
- `/catchup` — defaults to since-last-run

## Why this recipe matters

The two moments a Chief of Staff earns their keep are (a) before walking
into a meeting (`/prep`, `/who`) and (b) **after stepping back into the
flow** (`/catchup`). The triage — Must-act / FYI / Skip — is what makes
catchup *finite* instead of "scroll through 200 emails." This is the
recipe most CEOs ask for first when they try to take a real vacation.

## Customizing

- **Long absences (>5 days)?** Add a "decisions made without me" section
  pulled from Linear comments and email threads where someone said
  "going ahead with X."
- **Want a daily catchup?** Schedule `/catchup 24h` at 8am as an
  alternative to `/brief` for founders who already have their own morning
  ritual.
- **Skip bucket too aggressive?** Loosen the "skip" definition — by
  default it skips automated/marketing/CC; relax to only automated.
