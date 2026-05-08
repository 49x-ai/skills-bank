---
name: install-recipes
description: Guided installer for the five Chief of Staff recipes (/prep, /inbox-triage, /awaiting, /who, /catchup). Walks a small profile pass + per-recipe deltas, writes personalized slash-command files into .claude/commands/, persists durable answers as typed memory, and offers to schedule the routines. Use when the user asks to "install recipes," "add /prep to my bot," "customize my recipes," or "set up my chief of staff recipes."
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - AskUserQuestion
  - Bash(ls *)
  - Bash(mkdir *)
  - Bash(chmod *)
  - Bash(rm *)
  - Bash(cat *)
  - Bash(test *)
  - Bash(pwd)
  - Bash(date *)
  - Bash(claude --permission-mode bypassPermissions -p)
  - Bash(printf *)
---

# /cos-bot:install-recipes — Guided recipe installer

Stepped, resumable orchestration that picks among the five expansion-pack
recipes, asks a small profile pass once, asks per-recipe deltas, applies
deterministic transforms to the canonical recipe bodies, writes them to
`<project>/.claude/commands/`, persists durable answers as typed memory,
and offers to schedule the routines via `/schedule`.

State persists at `~/.claude/channels/telegram/.cos-bot-recipes.json`
(mode `0600`, sharing the cos-bot directory). No credentials live here —
the file is `0600` to match the cos-bot file posture and keep the dir
consistent.

Arguments passed: `$ARGUMENTS`

---

## Recipe catalog (source ↔ destination)

The five installable recipes. Source files ship with the plugin under
`${CLAUDE_PLUGIN_ROOT}/recipes/`; destinations under
`<project>/.claude/commands/`.

| Slug | Source file | Destination |
|---|---|---|
| `prep` | `${CLAUDE_PLUGIN_ROOT}/recipes/meeting-prep.md` | `.claude/commands/prep.md` |
| `inbox-triage` | `${CLAUDE_PLUGIN_ROOT}/recipes/inbox-triage.md` | `.claude/commands/inbox-triage.md` |
| `awaiting` | `${CLAUDE_PLUGIN_ROOT}/recipes/awaiting.md` | `.claude/commands/awaiting.md` |
| `who` | `${CLAUDE_PLUGIN_ROOT}/recipes/who.md` | `.claude/commands/who.md` |
| `catchup` | `${CLAUDE_PLUGIN_ROOT}/recipes/catchup.md` | `.claude/commands/catchup.md` |

Each source file has a `## Slash-command body` section containing one
fenced ```` ```markdown ... ``` ```` block — the **canonical body**. The
skill extracts that block, applies the deterministic transforms below
based on the user's answers, and writes the result to the destination.
Any text outside the fenced block (preamble, "Customizing" notes,
scheduling guidance) is for human readers and does **not** get written.

`<project>` = the directory the skill is invoked from. Capture it once
at start with `pwd` and reuse. Don't re-derive mid-run.

---

## Dispatch on arguments

Parse `$ARGUMENTS` (space-separated). Recognize:

- *(empty)* — interactive mode. Read state; resume at `state.step` (or
  start at `intake` if no state file).
- `all` / `defaults` — install all five recipes with stock bodies. **No
  Q&A**: skip the profile pass and per-recipe deltas, write all five
  destinations from the canonical bodies as-is, summarize, stop. Useful
  for "just give me the defaults" and CI smoke tests.
- `<name>` — one of `prep`, `inbox-triage`, `awaiting`, `who`, `catchup`.
  Run interactive mode but pre-select only that recipe. Profile pass
  still runs (those answers are reusable). Per-recipe deltas only ask
  that recipe's knobs.
- `reset` — delete the state file
  (`rm -f ~/.claude/channels/telegram/.cos-bot-recipes.json`). Confirm
  and stop. Does **not** delete already-installed command files or
  memory entries — those are durable.
- `step <name>` — jump to step `<name>` (one of `intake`, `profile`,
  `deltas`, `preview`, `write`, `schedule`). Used for debugging. Update
  `state.step` and run that step. Warn the user if state for prior
  steps is missing (e.g. jumping to `write` with no `selected`).
- *(unrecognized)* — show status (current step, selected recipes,
  what's already written) and stop.

---

## State file

Path: `~/.claude/channels/telegram/.cos-bot-recipes.json`. Schema:

```json
{
  "version": 1,
  "step": "intake",
  "projectDir": "/Users/.../my-project",
  "selected": ["prep", "inbox-triage", "awaiting", "who", "catchup"],
  "profile": {
    "vips": "Jane Doe (Acme), board@…, alex@bigco.com",
    "tone": "friendly",
    "stack": "Linear",
    "mix": "balanced"
  },
  "deltas": {
    "prep":         { "editorial": true,  "schedule": "Q-dispatcher" },
    "inbox-triage": { "drafts":    true,  "schedule": "11+3", "vipOnly": false },
    "awaiting":     { "schedule":  "Tue+Thu", "addSlack": false },
    "who":          { "editorial": true,  "biggerDossier": false },
    "catchup":      { "longAbsence": true, "skipAggressiveness": "default" }
  },
  "written":          ["prep", "inbox-triage"],
  "memoriesWritten":  ["reference_vips.md", "feedback_tone.md"],
  "scheduled":        ["inbox-triage"]
}
```

**Rules:**

- Always `mkdir -p ~/.claude/channels/telegram` before first write.
- Always `chmod 600` after creating the file.
- **Read-modify-write.** Do not clobber unrelated fields.
- Missing file = no state; start at `intake` and write a fresh object.
- Persist after every step that finishes; persist after every
  `AskUserQuestion` call returns. Resumability is the contract — a
  killed session loses at most the answers to the question currently in
  flight.
- Idempotent. Re-running with a recipe already in `state.written`
  re-renders it (in case the answer changed). Re-running with a memory
  already in `state.memoriesWritten` updates the file (in case the
  answer changed) but does not duplicate the `MEMORY.md` index entry.

---

## Step 0 — prerequisites (every run)

Before doing anything else, capture the project root and verify the
plugin's bundled recipes are reachable.

1. `pwd` → `state.projectDir`. The skill must be invoked from a project
   root with a writable `.claude/` (or one we can create) — that's where
   the personalized command files land. If `.claude/` doesn't exist yet
   and the parent directory isn't writable, abort with a pointer to run
   the skill from a project where you can write `.claude/commands/`.
2. `test -f "${CLAUDE_PLUGIN_ROOT}/recipes/meeting-prep.md"` (and the
   other four sources). If any are missing, list which ones and abort —
   the plugin install is corrupted; reinstall via `/plugin install
   cos-bot@49x-skills`.
3. Compute the memory directory:
   `~/.claude/projects/<slug>/memory/`, where `<slug>` is the absolute
   `projectDir` with `/` replaced by `-` (leading dash included). For
   example, a project at `/Users/jane/work/my-project` maps to
   `~/.claude/projects/-Users-jane-work-my-project/memory/`.
   `mkdir -p` it lazily — only when memory is about to be written.

---

## Step 1 — `intake` (recipe picker)

**Use `AskUserQuestion`, not chat turns.**

⚠ **`AskUserQuestion` enforces a 4-option-per-question ceiling.** The
intent is one multi-select with all 5 recipes + an "All five with
defaults" fast-path option = 6 options, which the tool rejects with
`InputValidationError: too_big`. Two acceptable workarounds, in
preference order:

1. **Two batched questions in one call** (recommended): Q1 = "Want
   all five with defaults?" (Yes / No, single-select). If Yes, set
   `state.selected = [all five]` and jump straight to `write`. If No,
   Q2 = the multi-select picker split into two questions of 3 + 2
   recipes (still inside the 4-option ceiling).
2. **Single Yes/No fast-path then a separate multi-select** (two
   round-trips, slower but more explicit).

Either way, the data shape afterwards is identical:

> Which recipes do you want to install? (Multi-select across both
> question groups.)
>
> - `/prep` — pre-meeting attendees, history, 3 questions
> - `/inbox-triage` — Reply now / FYI / Skip with drafts
> - `/awaiting` — who owes me, who I owe, what's stale
> - `/who` — relationship 360 dossier
> - `/catchup` — "I've been off for X" reorientation

Map answers to slugs (`prep`, `inbox-triage`, `awaiting`, `who`,
`catchup`). If the user picks the "all five with defaults" fast path,
set `state.selected` to all five and **jump straight to `write` step
with empty `state.profile` and empty `state.deltas`** — the transforms
layer treats missing answers as "use canonical body."

Persist `state.selected` and `state.step = "profile"`. Move on.

If the skill was invoked with `<name>` argument, **skip this step
entirely** — `state.selected` is already pre-set to `[<name>]`.

---

## Step 2 — `profile` (memory pre-read + 1 batched Q&A call)

The profile pass collects answers reusable across recipes (VIPs, tone,
stack, internal/external mix). These persist as typed memory and benefit
every future session — answer once, every recipe inherits.

### 2a. Memory pre-read

Before asking anything, scan the memory directory for existing answers:

| Memory file | Profile field |
|---|---|
| `reference_vips.md` | `vips` |
| `feedback_tone.md` | `tone` |
| `project_stack.md` | `stack` |
| `project_mix.md` | `mix` (internal/external) |

For each one that exists, read it and pre-fill `state.profile.<field>`.
**Skip the corresponding question** in step 2b unless the user explicitly
asked to revise (see "revise mode" below).

For each memory file that exists, surface a one-line summary at the top
of the AskUserQuestion preamble: *"Found existing memory for VIPs and
tone — I'll reuse them. Ask 'revise' to change."* If the user replies
"revise" (free-text in the harness chat) at any point in the flow, treat
it as a request to drop pre-fills and re-ask all four.

### 2b. Profile Q&A (one batched call, 4 questions max)

Ask only the fields not already in memory. Use **multi-select where the
shape allows** and free-text "Other" for VIPs.

| Field | Question | Options |
|---|---|---|
| `vips` | "Who counts as a VIP? Comma-separated names, emails, or domains. (e.g. `jane@acme.com, board@…, *@bigcustomer.com`)" | Free-text only — provide one example option, then Other for real input. |
| `tone` | "Tone for drafts:" | `terse` / `friendly` / `formal`. Single-select. |
| `stack` | "Issue tracker / docs stack:" | `Linear` / `Notion` / `Both` / `Neither`. Single-select. |
| `mix` | "Most of your communication is:" | `mostly external (customers/investors)` / `mostly internal (team)` / `balanced`. Single-select. |

Validation:
- `vips` — empty is fine (means "no VIP filter"). No length cap.
- `tone` / `stack` / `mix` — must be one of the listed values; if Other,
  fall back to `friendly` / `Both` / `balanced` respectively.

Persist `state.profile` after the call returns.

### 2c. Memory writes

For each non-empty field that **wasn't already in memory** (or that the
user revised), write a memory file using the standard frontmatter shape
described in *Memory writes* below. Append entries to `MEMORY.md`.

Persist `state.memoriesWritten` and `state.step = "deltas"`.

---

## Step 3 — `deltas` (per-recipe knobs)

For each recipe in `state.selected`, ask one batched `AskUserQuestion`
call covering only that recipe's specific knobs (the ones not covered by
profile). Persist `state.deltas[<slug>]` after each call.

If a recipe has only one knob and a clear default, you may pre-fill it
silently and skip the call — note the choice in the preview step.

### `prep`

| Knob | Question | Options |
|---|---|---|
| `editorial` | "Include the '3 questions I should ask' editorial section?" | `Yes (recommended)` / `No — skip the editorial line` |
| `schedule` | "When should `/prep` fire?" | `Q-dispatcher (7:30am reads calendar, schedules each meeting -30m)` / `D-loop (every 15 min, fires for upcoming meetings)` / `On-demand only (no schedule)` |

### `inbox-triage`

| Knob | Question | Options |
|---|---|---|
| `drafts` | "Include 2-3 sentence draft replies for the 'Reply now' bucket?" | `Yes (recommended)` / `No — pure triage list` |
| `schedule` | "When should `/inbox-triage` fire?" | `11am + 3pm weekdays` / `3pm only` / `On-demand only` |
| `vipOnly` | "VIP-only mode? Only triage threads where the sender matches your VIPs." | `No — triage everything (recommended)` / `Yes — VIP-only` |

### `awaiting`

| Knob | Question | Options |
|---|---|---|
| `schedule` | "When should `/awaiting` fire?" | `Tue + Thu 10am (recommended)` / `On-demand only` |
| `addSlack` | "Add a section pulling open Slack DMs where the latest message is from someone else?" | `No — email only` / `Yes — include Slack section` |

### `who`

| Knob | Question | Options |
|---|---|---|
| `editorial` | "Include the 'What I might be missing' editorial section?" | `Yes (recommended)` / `No — skip the editorial line` |
| `biggerDossier` | "Bigger dossier? Add a 'their open commitments to me' section pulled from `/awaiting`." | `No — standard dossier` / `Yes — include commitments` |

### `catchup`

| Knob | Question | Options |
|---|---|---|
| `longAbsence` | "Include a 'decisions made without me' section for long absences (>5 days)?" | `Yes (recommended)` / `No` |
| `skipAggressiveness` | "How aggressive should the 'Skip' bucket be?" | `default (skip automated/marketing/CC)` / `loose (only automated)` |

Persist `state.deltas` and `state.step = "preview"`.

---

## Step 4 — `preview`

Show a diff-style summary in chat (no `AskUserQuestion`, just a written
preview block), then a single confirm question.

Format the preview as three sections:

```
About to install:

Files to write:
  .claude/commands/prep.md          (editorial: on; schedule: Q-dispatcher)
  .claude/commands/inbox-triage.md  (drafts: on; schedule: 11+3; VIP-only: no)
  ...

Memories to update:
  ~/.claude/projects/<slug>/memory/reference_vips.md   (new)
  ~/.claude/projects/<slug>/memory/feedback_tone.md    (new)
  ~/.claude/projects/<slug>/memory/MEMORY.md           (append 2 entries)

Schedules to offer at the end:
  /inbox-triage  →  11am + 3pm weekdays
  /awaiting      →  Tue + Thu 10am
```

Mark already-written destinations as `(re-render)` instead of `(new)`.
Mark memory files that already exist as `(update)` not `(new)`.

Then one `AskUserQuestion`:

> Proceed?
>
> - **Yes — write everything**
> - **No — go back and revise** (jumps to `deltas` step)
> - **Cancel** (keeps state, exits)

On "Yes," persist `state.step = "write"` and proceed.

---

## Step 5 — `write`

Loop over `state.selected`. For each slug:

1. **Read** the source file (`${CLAUDE_PLUGIN_ROOT}/recipes/<source>.md`).
2. **Extract** the canonical body — the first fenced ```` ```markdown ... ``` ````
   block under the `## Slash-command body` heading. Keep the body
   verbatim, including its YAML frontmatter (the `---\ndescription:
   …\nallowed-tools: …\n---` header).
3. **Apply transforms** based on `state.profile` and
   `state.deltas[<slug>]`. See *Deterministic transforms* below.
4. **Write** the transformed body to
   `<projectDir>/.claude/commands/<slug>.md`. `mkdir -p
   <projectDir>/.claude/commands/` if needed. Use the `Write` tool, not
   `Bash` redirects.
5. Append `<slug>` to `state.written` (dedupe).

After the loop, persist state with `state.step = "schedule"`.

Print a one-line confirmation per recipe:

```
✓ wrote .claude/commands/prep.md
✓ wrote .claude/commands/inbox-triage.md
...
```

(No emoji elsewhere in the skill output — but ASCII checkmarks in this
summary are fine and match the project's other written-summary
patterns.)

---

## Step 6 — `schedule` (offer + nested handoff)

For each recipe in `state.selected` whose `state.deltas[<slug>].schedule`
is **not** `On-demand only`, collect the routine metadata. Map options
to the literal `/schedule` arguments these recipes' files document:

| Slug | Routine name (pin) | Schedule choice | Cron / form |
|---|---|---|---|
| `prep` | `prep` | Q-dispatcher | `30 7 * * 1-5` (a once-daily dispatcher routine that schedules per-meeting one-shots) |
| `prep` | `prep` | D-loop | a `/loop` watcher every 15 min — surface as `/loop 15m /prep` |
| `inbox-triage` | `inbox-triage` | 11+3 | `0 11,15 * * 1-5` |
| `inbox-triage` | `inbox-triage` | 3 only | `0 15 * * 1-5` |
| `awaiting` | `awaiting` | Tue+Thu | `0 10 * * 2,4` |

`/who` and `/catchup` are always on-demand (no schedule offer).

**Routine name = slug.** The canonical recipe files use longer
metadata names (`meeting-prep`, `morning-brief`, etc.) but the
slash command, the `state.selected` slug, and the `/schedule` routine
name are all the **slug** form (`prep`, `brief`, `inbox-triage`, …).
Always pass the slug as `<routine-name>` in the `/schedule` create
command — it matches the slash command name the user types and the
filename in `.claude/commands/`.

If the list is empty, skip this step and jump to `done`.

Otherwise, one `AskUserQuestion` (multi-select):

> Schedule any of these now? You can re-run `/schedule` later for any
> you skip.
>
> - `/prep` — `<chosen cron>`
> - `/inbox-triage` — `<chosen cron>`
> - `/awaiting` — Tue + Thu 10am
> - **None — I'll schedule manually later**

For each selected one, dispatch `/schedule` via a nested `claude -p`
call, **after explicit authorization** (mirrors cos-bot:setup step 4):

> To create the schedule, I need to spawn a nested `claude -p` with
> `--permission-mode bypassPermissions` so it can dispatch `/schedule`
> without an approval prompt for each routine. Authorize?
>
> - **Yes — use claude -p with bypassPermissions**
> - **No — I'll run /schedule myself** (I'll print the exact commands)

If yes, for each scheduled recipe, run:

```
printf '/schedule create "<routine-name>" --cron "<cron>" --agent chief-of-staff --command "/<slug>"\n' \
  | claude --permission-mode bypassPermissions -p
```

(The exact `/schedule` argument shape may vary by the user's installed
schedule skill — defer to whatever the running version of `/schedule`
documents. Confirm by reading
`<schedule-plugin-root>/SKILL.md` or by `/schedule --help` if unsure.
If the nested call returns text asking for more info, fall through to
the user-dispatched fallback.)

If no, print the exact commands the user can paste:

```
/schedule create "inbox-triage" --cron "0 11,15 * * 1-5" --agent chief-of-staff --command "/inbox-triage"
/schedule create "awaiting"     --cron "0 10 * * 2,4"   --agent chief-of-staff --command "/awaiting"
```

Append each successfully scheduled slug to `state.scheduled`. Persist.

---

## Step 7 — `done`

Set `state.step = "done"`, persist. Print a final summary:

```
Recipe install complete.

Installed:
  /prep            (.claude/commands/prep.md)
  /inbox-triage    (.claude/commands/inbox-triage.md)
  ...

Memories written:
  reference_vips.md
  feedback_tone.md
  ...

Scheduled:
  /inbox-triage  →  11am + 3pm weekdays
  /awaiting      →  Tue + Thu 10am
  (none — all on-demand)

Try one now from this directory:
  /prep
  /inbox-triage
  /who jane@acme.com

The chief-of-staff sub-agent inherits these automatically. Re-run
/cos-bot:install-recipes any time to revise — it's idempotent.
```

---

## Deterministic transforms

These are **string edits**, not LLM rewrites. Apply them in order to the
extracted canonical body. Each transform is a no-op if its trigger
condition is false — passing an empty `state.profile` and
`state.deltas[<slug>]` produces the canonical body verbatim, which is
the `defaults` fast-path contract.

### Profile-driven (apply to every recipe)

**Tone footer.** If `profile.tone` is set, append a footer block at the
end of the body, just before the closing of the markdown:

```
For drafts, follow the tone in `feedback_tone.md`.
```

**Stack swap.** If `profile.stack === "Notion"`, replace the literal
substring `Linear issue` with `Notion page` and `Linear issues` with
`Notion pages`. If `profile.stack === "Neither"`, drop the
issues-lookup section in each affected recipe by *contains*-match
(not starts-with) on these anchors:

- `prep` step 2: drop the sub-bullet whose text contains `open Linear
  issue mentioning them`.
- `who` step 5: drop the sentence/line whose text contains `Linear
  issues mentioning them`.
- `catchup` step 3 (the numbered `**Issues.**` heading + its body):
  drop the entire numbered item (heading + paragraph) up to the next
  numbered heading.

`Both` is a no-op (canonical body already mentions Linear; Notion is
additive in the user's own setup).

**Mix.** If `profile.mix === "mostly internal"`, in `prep` and `who`
swap the email-lookup wording per each recipe's own "Customizing"
section:

- `prep`: replace step 2's "last 3 email threads" wording with "recent
  Slack thread + Linear issue mentioning them" (drop the "company from
  email domain" sub-bullet).
- `who`: replace step 2's "most recent email" wording with "most recent
  Slack DM or Linear issue."

`mostly external` and `balanced` leave the email-lookup wording intact.

### Per-recipe (apply only to that slug)

**`prep`**:
- `editorial: false` → strip the paragraph that begins
  `The "3 questions" line is your editorial` and the words `, **3 questions
  I should ask**` from the four-sections list.

**`inbox-triage`**:
- `drafts: false` → strip the three lines under "For each **Reply now**
  thread" that mention `2-3 sentence draft reply` and `Tag it: \`DRAFT
  — not sent\``. Keep the 1-line summary and thread ID lines.
- `vipOnly: true` → prepend a line right after the `# /inbox-triage`
  heading: `Only include threads where the sender matches my VIPs (see
  \`reference_vips.md\`).` Drop nothing else; the existing "skip CC,
  skip newsletters, skip automated" filters still apply on top.

**`awaiting`**:
- `addSlack: true` → after section 2's body, insert a section 3:
  `**Awaiting Slack reply.** Open Slack DMs where the latest message is
  from someone else, in the last 14 days. Cap at 8.` Renumber the Stale
  section to 4.

**`who`**:
- `editorial: false` → strip the paragraph beginning `The "What I might
  be missing" line is your editorial` and the words `, **What I might
  be missing**` from the four-sections list.
- `biggerDossier: true` → after step 5's body, insert a step 6:
  `**Their open commitments to me.** Pull from \`/awaiting\` —
  threads where they owe me a reply or where I'm waiting on a deliverable
  from them. Cap at 5.`

**`catchup`**:
- `longAbsence: false` → no transform (the canonical body doesn't have
  a "decisions made without me" section yet; the Customizing note is
  aspirational. Treat `true` as the no-op default and `false` as also a
  no-op for now). Reserved for future extension.
- `skipAggressiveness: "loose"` → in `catchup`'s `**Skip**` definition
  (the line near the end that reads `For **Skip**: count + 1-line
  reason ("automated", "internal noise", "resolved while I was out").`),
  replace the parenthetical `("automated", "internal noise",
  "resolved while I was out")` with `("automated only")`. Match by
  *contains* on the literal `"automated", "internal noise"` to anchor
  the line (the full parenthetical is unique in the body).

### After all transforms

Validate the result:

- The opening `---\ndescription: …\nallowed-tools: …\n---` frontmatter
  is intact.
- The first `# /<slug>` heading is intact.
- The "Hard rule" line is intact. Match `^Hard rule[s]?:` (singular
  or plural — `inbox-triage.md` uses `Hard rules:` with a list,
  others use `Hard rule:` followed by a sentence). Require at least
  one match per recipe; never strip a Hard-rule line.
- No emoji introduced. No preamble inserted before the frontmatter.

If any check fails, abort the write for that slug, log the failed
recipe, continue with the rest, and surface the failure in the final
summary so the user can investigate.

---

## Memory writes

For each profile field that turns into memory, write a separate file
under the project's memory directory using the auto-memory frontmatter
shape from the user's global `CLAUDE.md`. Then append a one-line index
entry to `MEMORY.md` (create `MEMORY.md` if missing — no frontmatter on
the index file itself).

### File shapes

**`reference_vips.md`** — `type: reference`. Body: the user's
comma-separated VIP list, one entry per line. Reference memories
should be terse pointers per the global memory schema, so the body is
just the list. The "Used by …" footer below is **optional context** —
include it on first write to orient the user; skip it on re-writes
where the file already exists with a similar footer.

```
---
name: VIPs
description: People, emails, or domains the user marks as high-priority for triage and dossier recipes
type: reference
---

VIPs:

- Jane Doe (Acme)
- board@…
- *@bigcustomer.com
```

Optional footer (first write only):

```
Used by `/inbox-triage` (VIP-only mode), `/awaiting` (filter), and
`/who` (relationship lookup). Update freely — recipes re-read this on
every run.
```

**`feedback_tone.md`** — `type: feedback`. Body: the chosen tone, with
**Why:** and **How to apply:** lines per the global memory schema.

```
---
name: Draft tone
description: Tone the user prefers for assistant-drafted replies (terse / friendly / formal)
type: feedback
---

Draft tone: friendly.

**Why:** User answered the install-recipes profile question with this
choice. Friendly = warm, conversational, but concise — not effusive.
**How to apply:** When `/inbox-triage` (or any future `/draft`) emits
`DRAFT — not sent` blocks, match this register. Default to second-person
("you" not "ya'll"), no exclamations, no emoji.
```

(Substitute the body for `terse` / `formal` accordingly. Keep the
`**Why:**` / `**How to apply:**` structure consistent.)

**`project_stack.md`** — `type: project`. Body: the chosen stack with
**Why:** and **How to apply:**.

```
---
name: Issue tracker / docs stack
description: The user's primary issue tracker and docs system (Linear / Notion / Both / Neither)
type: project
---

Stack: Linear.

**Why:** User answered the install-recipes profile question. Recipes
that pull "open issues" or "recent docs" should target this system.
**How to apply:** When a recipe references issues, route to Linear.
When neither is chosen, recipes drop the issues-lookup section entirely.
```

**`project_mix.md`** — `type: project`. Body: the chosen
internal/external mix.

```
---
name: Communication mix
description: Whether the user's day-to-day comms skew external (customers/investors), internal (team), or balanced
type: project
---

Mix: balanced.

**Why:** User answered the install-recipes profile question. Recipes
that distinguish "external attendees" from "internal team members"
adjust their lookup logic based on this.
**How to apply:** `mostly internal` swaps email-lookup steps in `/prep`
and `/who` for Slack + Linear lookups. `balanced` and `mostly external`
keep the canonical email-first behavior.
```

### `MEMORY.md` index

`MEMORY.md` is an index, not a memory — no frontmatter, one line per
entry, under ~150 chars per line. Append entries for each new memory
file. Format:

```
- [VIPs](reference_vips.md) — high-priority senders for triage and dossier recipes
- [Draft tone](feedback_tone.md) — tone register for assistant-drafted replies
- [Issue tracker / docs stack](project_stack.md) — Linear / Notion / Both / Neither
- [Communication mix](project_mix.md) — external / internal / balanced
```

Before appending, **read `MEMORY.md`** and check whether the line
already exists (match on the link target, e.g. `(reference_vips.md)`).
If present, leave the index alone — the file content was updated, the
index entry is still correct.

### Update vs. create

- If the memory file does **not** exist: create it, append to
  `MEMORY.md`, add to `state.memoriesWritten`.
- If the memory file exists and the user **revised** their answer:
  overwrite the file with the new body, leave `MEMORY.md` untouched.
- If the memory file exists and the user did **not** revise (i.e. the
  pre-read filled the answer in step 2a): do nothing — neither file nor
  index changes.

---

## Implementation notes

- **No nested LLM rewrites.** All recipe-body transforms are
  deterministic string edits, listed above. If a knob's transform isn't
  documented, don't invent one — leave the canonical body untouched.
  This keeps the install reviewable and stable across runs.
- **The `defaults` fast path is the contract.** Empty `state.profile` +
  empty `state.deltas` must produce the canonical body verbatim for
  every recipe. If you find yourself adding a transform that fires on
  empty input, you've broken this contract — fix the trigger.
- **Memory writes are durable across sessions.** The state file is
  scratch — it gets reset by `/cos-bot:install-recipes reset`. The
  memory files do not. Treat `reset` as a "redo the install Q&A,"
  not as "wipe the user's preferences."
- **Don't write recipes the user didn't pick.** `state.selected` is the
  source of truth for the write loop. Don't pre-emptively write
  recipes "just in case" the user adds them later.
- **Preserve frontmatter and hard rules.** Every transform must keep
  the recipe's `---\n…\n---` frontmatter and its `Hard rule(s):` line(s)
  intact. The voice/format spec for these recipes is non-negotiable
  (Telegram-shape: no preamble, no emoji, hard rule line). If a
  transform would violate that, abort the write for that recipe.
- **Slash commands aren't tool calls.** A running model can't dispatch
  `/schedule` directly — same constraint as `cos-bot:setup` and
  `/telegram:configure`. Step 6 uses the same nested `claude -p
  --permission-mode bypassPermissions` pattern. Get authorization first
  (`AskUserQuestion`); fall through to user-dispatched commands if the
  nested call doesn't behave.
- **`bypassPermissions` on nested calls is gated.** The harness denies
  it on child agents unless explicitly authorized in the parent
  session. The authorization question in step 6 is on the record;
  don't assume it carries over from a prior `cos-bot:setup` run.
- **Resume safety.** Persist `state` after every `AskUserQuestion`
  call, not just at step boundaries. A killed session loses at most
  the answer to the question currently in flight.
- **Idempotent re-runs.** Running the skill twice in a row should be
  safe: the second run reads state, sees `step: "done"`, and offers to
  start fresh (`AskUserQuestion`: "Install is complete. Start over /
  install more recipes / cancel?"). Don't blindly re-execute.
- **Memory pre-read is cheap.** Always do it, even on `<name>`
  invocations. It's cheaper than asking the user a question they've
  already answered, and it lets the skill silently skip step 2 entirely
  when memory is fully populated.
- **Don't touch the bundled recipe sources.** The recipe bodies under
  `${CLAUDE_PLUGIN_ROOT}/recipes/*.md` ship with the plugin and are
  read-only canon — do not edit them in place inside
  `~/.claude/plugins/`. The destination for personalization is
  `.claude/commands/`. If a canonical body needs fixing, fork the
  plugin (`49x-ai/skills-bank`) and submit a PR; local edits will be
  blown away by the next plugin update.
- **Transforms use `contains`-semantics, not `starts-with`.** The
  `stack === "Neither"` and `skipAggressiveness === "loose"`
  transforms in *Deterministic transforms* anchor on substrings that
  appear mid-line in the canonical bodies (e.g. `Linear issues
  mentioning them`, `"automated", "internal noise"`). Match by
  *contains* on the documented anchor strings, then drop the
  containing line/sub-bullet/numbered item per the transform's
  intent. Don't switch to literal whole-line equality — the canonical
  bodies aren't formatted for it.
- **Restart any backgrounded `--channels` session after install.**
  A `claude --channels …` session running in tmux/script(1) loads the
  project's `.claude/commands/` directory at boot — so any recipe
  files written by this skill **after** that session started will be
  invisible to it. Symptom: DM `/inbox-triage` to the bot, Claude
  doesn't recognize the slash command and falls back to free-form
  reasoning. Recovery: `tmux kill-session -t cos-bot && tmux
  new-session -d -s cos-bot …` (or whatever the project's
  documented bot-launch ritual is). Mention this at the very end of
  Step 7's "done" summary so the user doesn't get a stale-session
  surprise on their first DM.
