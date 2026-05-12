---
name: install-recipes
description: Guided installer for the five Chief of Staff recipes (/prep, /inbox-triage, /awaiting, /who, /catchup). Defaults-first — leads with "all five with sensible defaults, customize later" so most users finish in ~4 questions. Also owns persona writes via `/cos-bot:install-recipes persona [preset|tune|show|reset]`. Use when the user asks to "install recipes," "add /prep to my bot," "customize my recipes," "set up my chief of staff recipes," "change the bot's tone," or "tune my CoS persona."
user-invocable: true
model: haiku
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
  - Bash(awk *)
  - Bash(tmux *)
  - Bash(pgrep *)
---

# /cos-bot:install-recipes — Guided recipe installer + persona tuner

Stepped, resumable orchestration that picks among the five expansion-pack
recipes, asks a small profile pass once, asks per-recipe deltas, applies
deterministic transforms to the canonical recipe bodies, writes them to
`<project>/.claude/commands/`, persists durable answers as typed memory,
and offers to schedule the routines via `/schedule`.

This skill also owns persona writes for the `chief-of-staff` sub-agent
via the `persona` argument dispatch (preset picker + per-axis tuning).

After install, run `/cos-bot:demo` to fire one recipe right now and see
the bot reply in your Telegram DM end-to-end.

State persists at `~/.claude/channels/telegram/.cos-bot-recipes.json`
(mode `0600`, sharing the cos-bot directory).

Arguments passed: `$ARGUMENTS`

## Companion files

This SKILL.md is the main orchestrator. Deep material lives in
`references/`:

- `references/persona.md` — preset table, axes, body shape, `persona` dispatch logic.
- `references/deltas.md` — per-recipe knob Q&A tables for the `deltas` step.
- `references/transforms.md` — deterministic string-edit catalog applied during `write`.
- `references/memory-writes.md` — file shapes for `reference_vips.md` / `project_stack.md` / `project_mix.md` and the `MEMORY.md` index conventions.
- `references/schedule.md` — cron mapping + nested `claude -p` dispatch for the `schedule` step.

Read each lazily — pull the companion only when its step runs.

---

## Recipe catalog (source ↔ destination)

| Slug | Source file | Destination |
|---|---|---|
| `prep` | `${CLAUDE_PLUGIN_ROOT}/recipes/meeting-prep.md` | `.claude/commands/prep.md` |
| `inbox-triage` | `${CLAUDE_PLUGIN_ROOT}/recipes/inbox-triage.md` | `.claude/commands/inbox-triage.md` |
| `awaiting` | `${CLAUDE_PLUGIN_ROOT}/recipes/awaiting.md` | `.claude/commands/awaiting.md` |
| `who` | `${CLAUDE_PLUGIN_ROOT}/recipes/who.md` | `.claude/commands/who.md` |
| `catchup` | `${CLAUDE_PLUGIN_ROOT}/recipes/catchup.md` | `.claude/commands/catchup.md` |

Each source file has a `## Slash-command body` section containing one
fenced ```` ```markdown ... ``` ```` block — the **canonical body**. The
skill extracts that block, applies deterministic transforms (see
`references/transforms.md`) based on the user's answers, and writes the
result to the destination. Any text outside the fenced block (preamble,
"Customizing" notes, scheduling guidance) is for human readers and does
**not** get written.

`<project>` = the directory the skill is invoked from. Capture it once
at start with `pwd` and reuse. Don't re-derive mid-run.

---

## Dispatch on arguments

Parse `$ARGUMENTS` (space-separated). Recognize:

- *(empty)* — interactive mode. Read state; resume at `state.step` (or
  start at `intake` if no state file).
- `all` / `defaults` — install all five recipes with stock bodies. **No
  Q&A**: skip everything else and run the *fast install* path (see
  *Step F* below). One Bash call writes all five files; no state file,
  no bot-restart probes, no per-slug Read/Write turns. Useful for
  "just give me the defaults," CI smoke tests, and harness perf runs.
- `<name>` — one of `prep`, `inbox-triage`, `awaiting`, `who`, `catchup`.
  Run interactive mode but pre-select only that recipe. Profile pass
  still runs (those answers are reusable). Per-recipe deltas only ask
  that recipe's knobs.
- `persona` *(optional second arg: `mbb` / `warm` / `blunt` / `tune` /
  `show` / `reset`)* — jump directly to the persona dispatch. Bypasses
  the recipe install flow entirely. See *Persona dispatch* below and
  `references/persona.md`.
- `reset` — delete the state file
  (`rm -f ~/.claude/channels/telegram/.cos-bot-recipes.json`). Confirm
  and stop. Does **not** delete already-installed command files or
  memory entries — those are durable.
- `step <name>` — jump to step `<name>` (one of `intake`, `profile`,
  `deltas`, `preview`, `write`, `schedule`). Used for debugging.
- *(unrecognized)* — show status (current step, selected recipes,
  what's already written) and stop.

---

## State file

Path: `~/.claude/channels/telegram/.cos-bot-recipes.json` (mode `0600`).
Fields: `version`, `step`, `projectDir`, `customize` (bool — gates the
defaults-first flow), `selected` (array of slugs), `profile` (vips /
persona / stack / mix), `deltas` (per-recipe knobs keyed by slug),
`written`, `memoriesWritten`, `scheduled`.

**Rules:**

- Always `mkdir -p ~/.claude/channels/telegram` before first write,
  `chmod 600` after.
- **Read-modify-write.** Do not clobber unrelated fields.
- Missing file = no state; start at `intake`.
- Persist after every step that finishes and after every
  `AskUserQuestion` returns. Resumability is the contract.
- Idempotent. Re-running with an already-written recipe re-renders it
  (so updated answers take effect). Re-running with an already-written
  memory file updates the file but doesn't duplicate the `MEMORY.md`
  index entry.

---

## Step 0 — prerequisites (every run)

1. `pwd` → `state.projectDir`. The skill must be invoked from a project
   root with a writable `.claude/` (or one we can create). If `.claude/`
   doesn't exist yet and the parent directory isn't writable, abort
   with a pointer to run the skill from a project where you can write
   `.claude/commands/`.
2. `test -f "${CLAUDE_PLUGIN_ROOT}/recipes/meeting-prep.md"` (and the
   other four sources). If any are missing, list which ones and abort
   — the plugin install is corrupted; reinstall via `/plugin install
   cos-bot@49x-skills`.
3. Compute the memory directory:
   `~/.claude/projects/<slug>/memory/`, where `<slug>` is the absolute
   `projectDir` with `/` replaced by `-` (leading dash included).
   `mkdir -p` it lazily — only when memory is about to be written.

### 0a — tool-denial early abort (every run, including Step F)

If **any** Bash, Write, or Edit call returns a permission denial during
this skill, **abort immediately** with this exact message and stop:

```
Cannot install recipes — the harness denied a tool call.

Re-run with:
  claude --permission-mode bypassPermissions  (one-shot, sandbox use)
or accept the prompts when they appear (interactive Claude Code).

Files attempted: <list>
Files actually written: <list> (or "none")

Re-running with permissions granted is safe — the skill is idempotent.
```

Do **not** print "Recipe install complete" with any subset of writes
denied. A partial install is a corrupt install — the user should see
exactly what landed and what didn't, and a clear path to re-run. This
applies to **every** code path in this skill, not just Step F.

Background: a previous version of this skill printed the success
summary even when all 9 file writes had been denied, leaving the
user thinking the install worked. Detecting denial up-front and
hard-aborting prevents that failure mode.

---

## Step F — fast install (`defaults` / `all` arg only)

When `$ARGUMENTS` is `all` or `defaults`, run this branch and **stop**.
Skip Steps 0–7. No state file. No `AskUserQuestion`. No bot-restart
probes. No per-slug Read+Write loop.

The contract: empty profile + empty deltas produce the canonical body
verbatim, so a single shell loop that awk-extracts the fenced markdown
block from each source and redirects it to the destination produces
byte-equal output to the orchestrated path. The shell is the right
primitive here — five model-mediated `Write` calls regenerate the body
in tool input on every turn (~2k output tokens) for zero added value.

Run **one** Bash call:

```bash
PROJECT_DIR="$(pwd)"
DEST="$PROJECT_DIR/.claude/commands"
SRC="${CLAUDE_PLUGIN_ROOT}/recipes"
mkdir -p "$DEST"
for pair in "prep:meeting-prep" "inbox-triage:inbox-triage" "awaiting:awaiting" "who:who" "catchup:catchup"; do
  slug="${pair%%:*}"
  src="${pair#*:}"
  awk '/^## Slash-command body/{f=1;next} f && /^```markdown/{b=1;next} b && /^```/{exit} b' \
    "$SRC/$src.md" > "$DEST/$slug.md"
done
ls "$DEST"
```

Then print the summary directly (no Step 7a probes — see *Implementation
notes* on why):

```
Recipe install complete (defaults).

Installed:
  /prep            (.claude/commands/prep.md)
  /inbox-triage    (.claude/commands/inbox-triage.md)
  /awaiting        (.claude/commands/awaiting.md)
  /who             (.claude/commands/who.md)
  /catchup         (.claude/commands/catchup.md)

Try one now from this directory:
  /prep
  /inbox-triage
  /who jane@acme.com

Or fire one through your bot:
  /cos-bot:demo

Re-run /cos-bot:install-recipes (no args) any time to customize — the
defaults you just installed are a fine starting point.
```

If the Bash exits non-zero, abort with the captured stderr and a
pointer to reinstall the plugin (a missing `recipes/*.md` source is
the only realistic failure here).

If the user wants the `Step 7a` bot-restart behavior, they can re-run
the skill with no args (the customize path runs the probes) — but the
fresh-project case this fast path targets almost never has a
backgrounded `claude --channels …` session running yet, so the probes
are wasted work.

---

## Step 1 — `intake` (defaults-first, then recipe picker if customizing)

**Use `AskUserQuestion`, not chat turns.**

The defaults-first lead. One single-select:

> Quickest path is "all five with sensible defaults" — recipes go in,
> and you can tweak any later by re-running this skill. Customize now?
>
> - **Install all five with defaults** (recommended)
> - **Pick recipes & tweak**

If **"Install all five with defaults"**, set:

- `state.customize = false`
- `state.selected = ["prep", "inbox-triage", "awaiting", "who", "catchup"]`
- `state.profile = {}`, `state.deltas = {}`

Persist `state.step = "preview"` (skipping `profile` and `deltas`
entirely) and proceed. The `defaults` fast-path contract guarantees
canonical bodies render verbatim from empty profile + deltas.

If **"Pick recipes & tweak"**, set `state.customize = true` and ask
the recipe multi-select. ⚠ The 4-option-per-question ceiling makes a
single 5-option multi-select impossible; split into two batched
questions (3 + 2 recipes):

> Q1: Which of these recipes do you want? (Multi-select)
>
> - `/prep` — pre-meeting attendees, history, 3 questions
> - `/inbox-triage` — Reply now / FYI / Skip with drafts
> - `/awaiting` — who owes me, who I owe, what's stale
>
> Q2: And these? (Multi-select)
>
> - `/who` — relationship 360 dossier
> - `/catchup` — "I've been off for X" reorientation

Map answers to slugs (`prep`, `inbox-triage`, `awaiting`, `who`,
`catchup`). Persist `state.selected` and `state.step = "profile"`.

If the skill was invoked with `<name>` argument, **skip this step
entirely** — `state.customize = true`, `state.selected = [<name>]`,
proceed to `profile`. If invoked with `all` / `defaults`, **do not**
fall through to this step or to `write` — jump to *Step F — fast
install* and stop after it.

---

## Step 2 — `profile` (memory pre-read + 1 batched Q&A call)

If `state.customize === false`, skip this step entirely.

The profile pass collects answers reusable across recipes (VIPs,
persona, stack, internal/external mix). These persist as typed memory
and benefit every future session — answer once, every recipe inherits.

### 2a. Memory pre-read

See `references/memory-writes.md` § *Memory pre-read* for the file ↔
field map and the "found existing memory" preamble pattern. For each
file that exists, read it and pre-fill `state.profile.<field>`. Skip
the corresponding question unless the user types "revise" anywhere in
the flow.

### 2b. Profile Q&A (one batched call, 4 questions max)

Ask only the fields not already in memory. Use **multi-select where
the shape allows** and free-text "Other" for VIPs.

| Field | Question | Options |
|---|---|---|
| `vips` | "Who counts as a VIP? Comma-separated names, emails, or domains. (e.g. `jane@acme.com, board@…, *@bigcustomer.com`)" | Free-text only — provide one example option, then Other for real input. |
| `persona` | (See `references/persona.md` § *Profile-pass question*.) | 4 options including `Skip — neutral defaults`. |
| `stack` | "Issue tracker / docs stack:" | `Linear` / `Notion` / `Both` / `Neither`. Single-select. |
| `mix` | "Most of your communication is:" | `mostly external (customers/investors)` / `mostly internal (team)` / `balanced`. Single-select. |

Validation:

- `vips` — empty is fine (means "no VIP filter"). No length cap.
- `persona` — must be one of `mbb` / `warm` / `blunt` / `skip`; if
  Other, fall back to `skip`.
- `stack` / `mix` — must be one of the listed values; if Other, fall
  back to `Both` / `balanced` respectively.

Persist `state.profile` after the call returns.

### 2c. Memory writes

For each non-empty field that **wasn't already in memory** (or that
the user revised), write a memory file using the file shapes in
`references/memory-writes.md`. Append entries to `MEMORY.md` per the
index conventions documented there. The persona file specifically
follows `references/persona.md` § *`feedback_persona.md` body shape*.

Persist `state.memoriesWritten` and `state.step = "deltas"`.

---

## Step 3 — `deltas` (per-recipe knobs)

If `state.customize === false`, skip this step entirely.

For each recipe in `state.selected`, run the knob Q&A documented in
`references/deltas.md` (one batched `AskUserQuestion` per recipe).
Persist `state.deltas[<slug>]` after each call. After the loop,
persist `state.step = "preview"`.

---

## Step 4 — `preview`

Show a diff-style summary in chat (no `AskUserQuestion`, just a written
preview block), then a single confirm question.

```
About to install:

Files to write:
  .claude/commands/prep.md          (defaults — re-run to customize)
  .claude/commands/inbox-triage.md  (defaults — re-run to customize)
  ...

Memories to update:
  (none — defaults path skips memory writes)

Schedules to offer at the end:
  (none — defaults path is on-demand only)
```

When `state.customize === true`, render per-knob detail and memory/
schedule lines as before:

```
Files to write:
  .claude/commands/prep.md          (editorial: on; schedule: Q-dispatcher)
  .claude/commands/inbox-triage.md  (drafts: on; schedule: 11+3; VIP-only: no)
  ...

Memories to update:
  ~/.claude/projects/<slug>/memory/reference_vips.md   (new)
  ~/.claude/projects/<slug>/memory/feedback_persona.md (new)
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
> - **No — go back and revise** (jumps to `deltas` step if customizing,
>   or `intake` if defaults)
> - **Cancel** (keeps state, exits)

On "Yes," persist `state.step = "write"` and proceed.

---

## Step 5 — `write`

Loop over `state.selected`. For each slug:

1. **Read** the source file (`${CLAUDE_PLUGIN_ROOT}/recipes/<source>.md`).
2. **Extract** the canonical body — the first fenced ```` ```markdown ... ``` ````
   block under the `## Slash-command body` heading. Keep the body
   verbatim, including its YAML frontmatter.
3. **Apply transforms** based on `state.profile` and
   `state.deltas[<slug>]`. See `references/transforms.md`.
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

(ASCII checkmarks only in this summary — no emoji elsewhere.)

---

## Step 6 — `schedule` (offer + nested handoff)

If `state.customize === false`, skip this step (defaults path is
on-demand only). Persist `state.step = "done"` and proceed.

Otherwise, see `references/schedule.md` for the cron table, the
authorization prompt pattern, and the dispatch commands. The
orchestration shape:

1. Build the eligible list from `state.selected` filtered by
   `state.deltas[<slug>].schedule !== "On-demand only"`.
2. If empty, persist `state.step = "done"` and skip.
3. Otherwise, run the offer Q&A, the authorization Q&A, and the
   dispatch loop documented in `references/schedule.md`.
4. Append each successfully scheduled slug to `state.scheduled`.
   Persist `state.step = "done"`.

---

## Step 7a — restart background bot

Before printing the final summary, try to restart the user's
backgrounded `claude --channels …` session so it loads the
freshly-written `.claude/commands/` files. Keep this best-effort:
treat any tmux/script error as soft and fall through to the
`"skipped"` branch rather than failing the install.

1. **Detect tmux session.** `tmux has-session -t cos-bot 2>/dev/null`
   (exit 0 = exists).
   - Capture the running pane's working directory:
     `tmux display-message -p -F '#{pane_current_path}' -t cos-bot`
     (use `pane_current_path`, not `session_path` — the user may have
     `cd`'d after launch).
   - `tmux kill-session -t cos-bot`
   - `tmux new-session -d -s cos-bot -c "<captured-pane-path>" 'claude --channels plugin:telegram@claude-plugins-official --dangerously-skip-permissions; exec zsh'`
   - Poll for `Listening for channel messages…` with 250 ms × 60
     attempts (15 s ceiling, early exit on match):
     `tmux capture-pane -p -t cos-bot | grep -q "Listening for channel messages"`.
     Use session-level target `cos-bot` (not `cos-bot:0`) to dodge
     custom window names. Cold Claude startup with model download /
     plugin load can take 10–20 s.
   - On match → `state.botRestarted = "tmux"`. On 15 s timeout →
     `state.botRestarted = "tmux-pending"` (still better than nothing
     — backlog will drain when it does start).

2. **If tmux had no `cos-bot` session, try `script(1)` detection.**
   `pgrep -f "script.*claude --channels.*plugin:telegram@claude-plugins-official"`.
   - If a PID exists, `kill <pid>`, then re-launch the canonical
     block:
     `mkdir -p /tmp/cos-bot && nohup script -q /tmp/cos-bot/claude-channel.log claude --channels plugin:telegram@claude-plugins-official > /dev/null 2>&1 & disown`.
   - On success → `state.botRestarted = "script"`. Don't try to
     verify "Listening" via the script log — recovery is best-effort;
     tell the user to peek with
     `strings /tmp/cos-bot/claude-channel.log | tail -3` if they want.

3. **Neither method matched** → `state.botRestarted = "skipped"`. The
   user wasn't running the bot in the background; no action needed.

The summary in Step 7 reads `state.botRestarted` to render its
restart line — see the table below.

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
  feedback_persona.md
  ...
  (or "(none — defaults path)")

Scheduled:
  /inbox-triage  →  11am + 3pm weekdays
  /awaiting      →  Tue + Thu 10am
  (none — all on-demand)

Try one now from this directory:
  /prep
  /inbox-triage
  /who jane@acme.com

Or fire one through your bot:
  /cos-bot:demo

Brain-dump capture: long inbound Telegram messages (≥200 words) are
auto-saved to <project>/.claude/projects/<slug>/memory/brain-dumps/
before the agent processes them. To turn this off, run
/cos-bot:install-recipes persona tune and set "Brain-dump capture" to
off.

The chief-of-staff sub-agent inherits these automatically. To tune the
persona, run /cos-bot:install-recipes persona tune. Re-run
/cos-bot:install-recipes any time to revise — it's idempotent.

<restart-line>
```

The final line above is rendered conditionally on
`state.botRestarted` (set by Step 7a):

| `state.botRestarted` | `<restart-line>` body |
|---|---|
| `"tmux"` | `Bot restarted (tmux: cos-bot) — recipes are live; inbound DMs will recognize the new slash commands.` |
| `"tmux-pending"` | ``Restarted tmux:cos-bot but didn't see "Listening…" within 15s — give it another 30s, then peek with `tmux capture-pane -p -t cos-bot \| tail -10`.`` |
| `"script"` | ``Bot restarted (script(1) PID <new-pid>) — peek with `strings /tmp/cos-bot/claude-channel.log \| tail -3` to confirm.`` |
| `"skipped"` | ``No backgrounded `claude --channels …` session detected — when you start one later, it'll pick up the recipes automatically.`` |

Omit empty sections (no scheduled? no `Scheduled:` block at all).

---

## Persona dispatch

When invoked as `/cos-bot:install-recipes persona [<sub-arg>]`, jump
directly to the persona logic. Don't touch the recipe state file
(`.cos-bot-recipes.json`) — persona is short and re-runnable, no state
file needed.

Sub-args: `mbb` / `warm` / `blunt` / `tune` / `show` / `reset` /
*(empty)*. See `references/persona.md` for the full per-branch logic,
the `feedback_persona.md` body shape, the migration handling for the
legacy `feedback_tone.md`, and the `MEMORY.md` index entry.

Orchestration shape (apply for every non-`show` branch):

1. `pwd` → projectDir.
2. Compute the memory dir (`~/.claude/projects/<slug>/memory/`).
3. Read current persona (or migrate from `feedback_tone.md`, or fall
   back to neutral defaults).
4. Apply the dispatched branch's logic from `references/persona.md`.
5. For write paths: render the body per
   `references/persona.md` § *`feedback_persona.md` body shape*, write
   to `<memory-dir>/feedback_persona.md`, ensure `MEMORY.md` index
   entry exists.
6. Print the confirmation block from `references/persona.md` § *Step 4
   — confirm* (or the equivalent for `reset` / `show`).

`show` is read-only — print and stop.

---

## Implementation notes

- **The `defaults` fast path is the contract.** Empty `state.profile`
  + empty `state.deltas` must produce the canonical body verbatim for
  every recipe. The defaults-first lead in Step 1 makes this the
  default user path, not just an `all`/`defaults` escape hatch.
- **One source of truth for persona.** Both the profile pass and the
  `persona` argument dispatch render via `references/persona.md` §
  *body shape*. The chief-of-staff agent only reads.
- **Memory writes are durable across sessions.** The state file is
  scratch (`reset` wipes it); memory files are not. `reset` redoes
  the install Q&A — it does not wipe preferences.
- **Resume safety.** Persist `state` after every `AskUserQuestion`
  call, not just at step boundaries.
- **Idempotent re-runs.** Second run with `step: "done"` should ask
  "Start over / install more recipes / tune persona / cancel?" — don't
  blindly re-execute.
- **Activate moved to `/cos-bot:demo`.** Earlier versions bundled an
  "activate" step that fired one recipe to Telegram on completion.
  That now lives as `/cos-bot:demo`. The orchestrator
  (`/cos-bot:start`) chains it after install automatically.
