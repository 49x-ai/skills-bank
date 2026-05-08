# Recipes — index

The canonical bodies for every Chief of Staff slash command. The
`chief-of-staff` sub-agent inherits them all.

## How to install

Run `/cos-bot:install-recipes` for a guided install of the five
expansion-pack recipes (`/prep`, `/inbox-triage`, `/awaiting`, `/who`,
`/catchup`) — it asks a small profile pass once, applies your choices
to the canonical bodies, writes them to `<your-project>/.claude/commands/`,
persists durable answers as typed memory, and offers to schedule the
routines. Pass `all` for stock defaults (`/cos-bot:install-recipes
all`) or a single slug for one recipe (`/cos-bot:install-recipes
prep`).

For the four spine recipes (`/brief`, `/shutdown`, `/weekly-review`,
`/tackle`) and anything not covered by the installer, paste each body
manually into `<your-project>/.claude/commands/<name>.md`.

## Voice/format rules

These apply to **recipe output** (the text the bot DMs you). They do
*not* govern terminal output from the install-recipes skill, which uses
ASCII checkmarks for write summaries.

- Plain text suitable for Telegram DM. No emoji. No preamble.
- Hard rule: never auto-send, never auto-decide.
- Always cite source IDs (event ID, thread ID, issue ID).
- Editorial bullets allowed and labeled as such.

## Cadence — scheduled

- **`/brief`** ([morning-brief.md](morning-brief.md)) — 8am weekdays. Today's
  calendar, top 3 emails, open issues, one thing I might miss.
- **`/shutdown`** ([end-of-day-shutdown.md](end-of-day-shutdown.md)) — 6pm
  weekdays. Wins, tomorrow's top 3, awaiting both directions.
- **`/weekly-review`** ([weekly-review.md](weekly-review.md)) — Friday 4pm.
  What landed, what slipped, next week's top 5, one question for the
  weekend.

## Inner machinery — scheduled or on-demand

- **`/prep <meeting?>`** ([meeting-prep.md](meeting-prep.md)) — 30 min before
  each meeting (or by name). Attendees, history, docs, 3 questions to ask.
- **`/inbox-triage`** ([inbox-triage.md](inbox-triage.md)) — on-demand or
  11am + 3pm weekdays. Reply now / FYI / Skip, with drafts.
- **`/awaiting`** ([awaiting.md](awaiting.md)) — on-demand or Tue + Thu 10am.
  Who owes me, who I owe, what's stale.

## Argument-driven — on-demand

- **`/tackle <topic>`** ([tackle.md](tackle.md)) — pull everything on a
  topic and draft a 1-page memo with options.
- **`/who <person-or-company>`** ([who.md](who.md)) — relationship 360
  dossier for a person or company.
- **`/catchup <duration?>`** ([catchup.md](catchup.md)) — "I've been off
  for X" reorientation.

## Coming next (catalog only — design later)

- **`/draft <thread>`** — Reply drafting in my voice for a specific thread.
  Three drafts at different temperatures (terse / friendly / formal).
  Pairs with `/awaiting` and `/inbox-triage`.
- **`/decide <topic>`** — Structured decision memo. Variant of `/tackle`
  framed as a binary or 3-way decision with "what would have to be true"
  for each option.
- **`/recap <thread-or-meeting>`** — TL;DR a long thread or pasted
  meeting transcript. Extract decisions, action items, owners.
- **`/calendar-sweep`** — Hygiene pass on the next 2 weeks: back-to-back
  blocks, no-prep meetings, conflicts, unprotected focus time.

## How they compose

- `/brief` flags meetings that need prep → `/prep` does the prep.
- `/brief` flags awaiting threads → `/awaiting` is the standalone surface.
- `/prep` surfaces unfamiliar attendees → `/who` is the dossier.
- `/shutdown` and `/awaiting` overlap by design — `/shutdown` is the
  end-of-day cadence, `/awaiting` is the mid-day pull.
- `/catchup` is the inverse of all of the above — re-entering the flow.
