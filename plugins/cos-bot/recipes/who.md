# Recipe — `/who <person-or-company>` (on-demand)

> Canonical body for the `/who` slash command. Argument-driven dossier.
> The "before I walk into this room, who am I about to meet?" recipe.

## Slash-command body

Paste into `.claude/commands/who.md` (or run `/cos-bot:install-recipes who`):

```markdown
---
description: Dossier on a person or company — who they are, our history, what's open.
allowed-tools: Bash, Read, Grep, WebFetch
---

# /who

Argument: a person's name, an email address, or a company.

Pull everything connected to the argument from my connected systems:

1. **Identity.** If person: full name, title, company (from email signature
   or LinkedIn snippet via WebFetch if needed). If company: 1-line
   description, sector, my known relationship.
2. **Last touch.** The most recent email, calendar event, or Linear issue
   involving them. Date, subject/title, one-line summary.
3. **Active threads.** Open email threads in the last 60 days. Cap at 5.
4. **Calendar history.** Meetings with them in the last 90 days and any on
   the next 30. Count + the most-recent + the next.
5. **Internal context.** Linear issues mentioning them. Notes in my
   memories tagged with their name.

Then output 4 sections — **Who they are**, **Our history**, **What's
open**, **What I might be missing** — in that order. No preamble. No
emoji. ≤6 short paragraphs.

The "What I might be missing" line is your editorial — a thread I haven't
replied to, a meeting I rescheduled twice, a commitment they're tracking.
One bullet, one sentence.

Hard rule: do not message the person. Do not add them to anything. Output
is read-only context for me.
```

## How it gets invoked

Three options:

1. **Pre-meeting:** `/who acme-ceo@acme.com` 5 min before a call.
2. **From your phone:** DM "who is jane@acme.com" — the `chief-of-staff`
   sub-agent maps that to `/who`.
3. **Chained from `/prep`:** `/prep` can suggest `/who <attendee>` for any
   attendee you don't recognize.

## Why this recipe matters

`/tackle` is for *topics* (a deal, an initiative). `/who` is for *people
and companies*. CEOs meet 10-30 new-ish people a week; the difference
between walking in cold and walking in informed is one well-cited
2-paragraph dossier. Always on-demand, never scheduled.

## Customizing

- **Internal-only mode?** For your own team members, skip WebFetch and
  pull from your team-roster `reference` memory + recent 1:1 notes.
- **Bigger dossier?** Add a "their open commitments to me" section drawn
  from `/awaiting`.
- **Editorial off?** Drop the "What I might be missing" line.

## A note on WebFetch

This recipe pulls LinkedIn snippets via `WebFetch` when an external
attendee isn't already in your inbox. Two things to know:

- **Identity.** WebFetch hits public pages from your machine — the
  request is logged like any other web traffic. Don't use this recipe
  on anyone whose lookup you wouldn't want logged.
- **Availability.** LinkedIn often serves a login-walled page to
  unauthenticated fetches. When that happens, the dossier degrades
  gracefully — the **Identity** section just notes "LinkedIn page not
  reachable" and falls back to email-signature data. Don't retry
  aggressively; the page won't unlock.
