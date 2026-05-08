# Recipes — index

The canonical bodies for every Chief of Staff slash command. The
`chief-of-staff` sub-agent (shipped at
`${CLAUDE_PLUGIN_ROOT}/agents/chief-of-staff.md`) inherits them all and
modulates output via the persona stored in `feedback_persona.md`. See
*Persona layer* below.

## How to install

The headline path is `/cos-bot:start` — it inspects your current
state and dispatches the right next command. For direct installs:

Run `/cos-bot:install-recipes` for a guided install of the five
expansion-pack recipes (`/prep`, `/inbox-triage`, `/awaiting`, `/who`,
`/catchup`). The installer leads with one question — *"all five with
sensible defaults, or pick & tweak?"* — so most users finish in ~4
question moments. Pass `all` for stock defaults
(`/cos-bot:install-recipes all`) or a single slug for one recipe
(`/cos-bot:install-recipes prep`).

After install, run `/cos-bot:demo` to fire one recipe right now and
DM the result to your Telegram in a minute or two — proves the loop
end-to-end.

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

## Persona layer

The above rules are non-negotiable. The persona layer sits underneath
them — it modulates *how* the agent speaks within those constraints.

Persona axes live in `feedback_persona.md` under the project's memory
directory:

- **Formality** (`terse` / `friendly` / `formal`) — draft tone register.
- **Proactivity** (`proactive` / `reactive`) — whether to surface
  editorial bullets ("one thing I might miss") unprompted, or stick to
  the literal ask.
- **Name** — the bot's self-reference. Empty = no sign-off.
- **Reasoning hint** (`conclusion-first` / `chronological` / `none`) —
  structure on memo-style recipes (`/tackle`, `/catchup` long form).

Set this file via `/cos-bot:install-recipes` (asks for a preset on
the way through) or `/cos-bot:install-recipes persona [preset|tune|show|reset]`
(preset + per-axis tuning anytime). The chief-of-staff sub-agent
reads the file fresh on every recipe run.

**Legacy `feedback_tone.md`** — earlier versions of cos-bot wrote a
single-axis tone file. The agent still reads it as a fallback when
`feedback_persona.md` is absent, but new installs go straight to the
persona file. Run `/cos-bot:install-recipes persona tune` to upgrade.

## Brain-dump capture

When you DM the bot a long message — voice-memo transcription, late-night
strategy thinking, anything ≥200 words — the chief-of-staff sub-agent
captures it verbatim to `<project>/.claude/projects/<slug>/memory/brain-dumps/YYYY-MM-DD-HH-MM-<slug>.md`
*before* processing it. Short messages and slash commands aren't
captured. The agent's reply leads with one line confirming the capture
("captured to brain-dumps/2026-05-08-1142-q3-roadmap-thoughts.md") and
then continues normal processing.

This is **on by default**. To turn it off, run
`/cos-bot:install-recipes persona tune` and set "Brain-dump capture"
to off — the agent reads the flag from `feedback_persona.md` on every
inbound message.

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
