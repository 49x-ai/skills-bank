# Recipe — `/tackle <topic>` (on-demand)

> Canonical body for the `/tackle` slash command. Argument-driven: you give it a topic (a customer name, a deal, an initiative); it pulls everything related and drafts a 1-page memo with options. Not scheduled — fired on demand.

## Slash-command body

Paste into `chiefofstaff/.claude/commands/tackle.md`:

```markdown
---
description: Pull everything on a topic and draft a 1-page memo with options.
allowed-tools: Bash, Read, Grep, WebFetch
---

# /tackle

Argument: the topic — a customer name, a deal, a person, or an initiative.

Pull everything connected to the argument from my connected systems:

1. Calendar events involving the topic in the last 60 days and next 30.
2. Email threads mentioning the topic in the last 90 days, grouped by sender.
3. Linear issues / Notion docs tagged or titled with the topic.

Then draft a **1-page memo**:

- **Where we are** (3 bullets — facts only, each citing a source: event ID, thread ID, issue ID).
- **Options, ranked** (3 options. For each: cost, risk, and what would have to be true.).
- **My recommendation** (2 sentences, tagged as recommendation, not decision).
- **Open questions for me** (3 questions, max).

Hard rule: never make the decision in the memo. Never send the memo to anyone. Output is a draft for me.
```

## How it gets invoked

Three options:

1. **From your terminal:** `/tackle Acme Corp` in a `claude --channels …` session.
2. **From your phone:** DM your bot *"tackle Acme Corp"* — the `chief-of-staff` sub-agent maps that to `/tackle Acme Corp`.
3. **From `/schedule` one-shot:** *"Run /tackle Acme Corp at 4pm and post the memo to Telegram."* Useful when you know you'll need a memo before a 5pm meeting.

## Customizing

- **Different sources?** Add Slack to step 2 if your team's primary channel is Slack rather than email.
- **Memo too long?** Cap "Where we are" at 5 bullets and "Options" at 2.
- **Memo too short?** Add a *"Stakeholders"* section between **Options** and **My recommendation** — who will be affected by each option.

## Why this recipe matters

`/brief` and `/shutdown` are the cadence — they fire on a schedule. `/tackle` is the **think for me about <thing>** lever — it fires when you have a hard call to make and 30 minutes is too long to spend gathering context.
