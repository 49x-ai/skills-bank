# Recipe — `/inbox-triage` (on-demand or 11am + 3pm weekdays)

> Canonical body for the `/inbox-triage` slash command. Processes unread
> email into a triaged list with drafts for the routine stuff. Bigger than
> the 3-thread slice in `/brief`.

## Routine metadata (for `/schedule`)

- **Name:** `inbox-triage`
- **Cron (optional):** `0 11,15 * * 1-5` (11am and 3pm, weekdays)
- **Agent to invoke:** `chief-of-staff`
- **Output target:** your Telegram chat-id

## Slash-command body

Paste into `chiefofstaff/.claude/commands/inbox-triage.md`:

```markdown
---
description: Triage unread email — Reply now / FYI / Skip, with drafts for routine threads.
allowed-tools: Bash, Read, Grep
---

# /inbox-triage

Pull all unread threads where I'm in To: from the last 24h (skip CC, skip
newsletters, skip automated). For each thread, classify into one bucket:

- **Reply now** — sender is a customer, investor, direct report, or board
  member; OR the latest message contains a direct question for me; OR the
  thread is older than 48h and someone is waiting.
- **FYI** — informational, no question, no decision needed from me, but
  worth knowing.
- **Skip** — automated, marketing, internal CC noise, already resolved.

Output 3 sections — **Reply now**, **FYI**, **Skip (count only)** — in that
order. No preamble. No emoji.

For each **Reply now** thread:
- 1 line summarizing the thread (sender, subject, the actual ask).
- A 2-3 sentence draft reply in my voice. Tag it: `DRAFT — not sent`.
- The thread ID so I can find it.

For each **FYI** thread: 1 line, sender + subject + the takeaway. No draft.

For **Skip**: just the count. Don't list them.

Hard rules:
- Never auto-send. Never mark anything read. Drafts stay in the message,
  not in Gmail.
- If a thread is genuinely ambiguous (might be Reply now, might be FYI),
  put it in Reply now and note "ambiguous — your call."
```

## When the routine fires

- **On-demand:** DM "triage my inbox" or run `/inbox-triage` from terminal.
- **Scheduled (optional):** 11am + 3pm. Two beats line up with the natural
  email-checking moments — mid-morning settle and post-lunch reset. Many
  founders run only the 3pm one.

## Why this recipe matters

`/brief` gives you the 3 most important threads at 8am. By 11am there are
already 30 new ones. `/inbox-triage` is the recipe that prevents inbox
collapse during the day without you reading every thread. The drafts are
the leverage — most "reply now" threads need a 2-sentence acknowledgment,
not a 20-minute composition.

## Customizing

- **Heavy senders?** Add a "VIP only" mode — only thread the buckets when
  sender matches your VIP `reference` memory list.
- **Drafts feel off?** Pin a *tone exemplar* in your `feedback` memory ("when
  I reply to customers I open with X, close with Y") — drafts get sharper.
- **Don't want drafts?** Drop the draft line; output becomes a pure triage
  list.
