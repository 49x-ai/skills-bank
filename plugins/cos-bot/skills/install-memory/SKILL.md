---
name: install-memory
description: Guided installer for a Markdown-first memory system — a self-contained `memory/` folder at your project root with a protocol doc, search script, and optional recurring compaction routine. Defaults-first — leads with three presets (Minimal / Standard / Full) so most users finish in ~3 questions, then a multi-select to toggle individual folders. Never overwrites existing memory files. Use when the user asks to "install memory," "set up a memory system," "give the bot durable memory," "add a memory folder," or "make my assistant remember things across sessions."
user-invocable: true
model: haiku
allowed-tools:
  - Read
  - Write
  - Edit
  - AskUserQuestion
  - Bash(pwd)
  - Bash(ls *)
  - Bash(mkdir *)
  - Bash(cp *)
  - Bash(chmod *)
  - Bash(test *)
  - Bash(rm *)
  - Bash(date *)
  - Bash(printf *)
  - Bash(claude --permission-mode bypassPermissions -p)
---

# /cos-bot:install-memory — Guided memory-system installer

Stepped, resumable orchestration that installs a Markdown-first memory
system into the project: a self-contained `memory/` folder at the
**project root**, a `PROTOCOL.md` doc, an optional `scripts/memory-search.sh`,
and an optional recurring compaction routine. The user picks a preset
(Minimal / Standard / Full) then toggles individual components; the
skill copies the resolved set from canonical content bundled with the
plugin.

This is **standalone** — not chained into `/cos-bot:start`. It mirrors
`/cos-bot:install-recipes`'s stepped/resumable/defaults-first shape but
writes durable user content, so its overriding rule is **never overwrite
an existing memory file**.

State persists at `~/.claude/channels/telegram/.cos-bot-memory.json`
(mode `0600`, sharing the cos-bot channel directory).

Arguments passed: `$ARGUMENTS`

## Companion files

This SKILL.md is the orchestrator. Deep material lives in `references/`:

- `references/structure.md` — preset → component map, the `MEMORY.md`
  folder-guide assembly rule, file shapes, the `./CLAUDE.md`
  managed-block marker convention, safety invariants.
- `references/schedule.md` — the compaction-routine command body,
  cadence table, and `/cos-bot:autopilot` nested-dispatch pattern.

Read each lazily — pull the companion only when its step runs.

---

## Bundled canonical content

Source of truth is `${CLAUDE_PLUGIN_ROOT}/memory-kit/` (precedent:
`${CLAUDE_PLUGIN_ROOT}/recipes/`). Layout and the component → file map
are in `references/structure.md`. Everything installs into a
self-contained tree at `<project>/`:

```
<project>/
├── PROTOCOL.md           (if `protocol` installed)
├── CLAUDE.md             (marker block appended, if `protocol` installed)
├── memory/               (always)
└── scripts/memory-search.sh   (if `search` installed)
```

`<project>` = the directory the skill is invoked from. Capture it once
at start with `pwd` and reuse. Don't re-derive mid-run.

---

## Dispatch on arguments

Parse `$ARGUMENTS` (space-separated). Recognize:

- *(empty)* — interactive mode. Read state; resume at `state.step` (or
  start at `intake` if no state file).
- `minimal` / `standard` / `full` — **fast install** that preset, no
  Q&A. Run *Step F* and stop.
- `defaults` — alias for `standard` fast install.
- `reset` — delete the state file
  (`rm -f ~/.claude/channels/telegram/.cos-bot-memory.json`). Confirm
  and stop. **Never touches `./memory/`** — installed memory is durable.
- `step <name>` — jump to step `<name>` (one of `intake`, `preview`,
  `write`, `schedule`, `done`). Used for debugging.
- *(unrecognized)* — show status (current step, chosen preset, what's
  already written) and stop.

---

## State file

Path: `~/.claude/channels/telegram/.cos-bot-memory.json` (mode `0600`).
Fields:

- `version` — schema version (`1`).
- `step` — one of `intake | preview | write | schedule | done`.
- `projectDir` — captured `pwd`.
- `preset` — `minimal | standard | full` (the picked preset, before toggles).
- `components` — resolved array of component keys (see
  `references/structure.md` § *Components*).
- `written` — array of paths actually written this install.
- `scheduled` — bool — whether the compaction routine offer was completed.

**Rules:**

- `mkdir -p ~/.claude/channels/telegram` before first write, `chmod 600`
  the file after.
- **Read-modify-write.** Don't clobber unrelated fields.
- Missing file = no state; start at `intake`.
- Persist after every step that finishes **and after every
  `AskUserQuestion` returns**. Resumability is the contract.
- Idempotent. Re-running only adds missing components — it never
  overwrites an existing memory file (see *Safety* below).

---

## Step 0 — prerequisites (every run)

1. `pwd` → `state.projectDir`. The skill writes a `memory/` folder, a
   `PROTOCOL.md`, and optionally `scripts/` and `CLAUDE.md` here. If the
   directory isn't writable, abort with a pointer to run the skill from
   a project root you can write to.
2. `test -d "${CLAUDE_PLUGIN_ROOT}/memory-kit"` and
   `test -f "${CLAUDE_PLUGIN_ROOT}/memory-kit/memory/MEMORY.md"`. If
   missing, abort — the plugin install is corrupted; reinstall via
   `/plugin install cos-bot@49x-skills`.

### 0a — tool-denial early abort (every run, including Step F)

If **any** Bash, Write, or Edit call returns a permission denial during
this skill, **abort immediately** with this exact message and stop:

```
Cannot install memory — the harness denied a tool call.

Re-run with:
  claude --permission-mode bypassPermissions  (one-shot, sandbox use)
or accept the prompts when they appear (interactive Claude Code).

Files attempted: <list>
Files actually written: <list> (or "none")

Re-running with permissions granted is safe — the skill is idempotent
and never overwrites existing memory files.
```

Do **not** print "Memory install complete" with any subset of writes
denied. A partial install should show the user exactly what landed and
what didn't, plus a clear path to re-run. This applies to **every** code
path in this skill, not just Step F.

---

## Step F — fast install (`minimal` / `standard` / `full` / `defaults`)

When `$ARGUMENTS` is `minimal`, `standard`, `full`, or `defaults`, run
this branch and **stop**. No state file. No `AskUserQuestion`.

`defaults` → `standard`. Resolve the preset's component set from
`references/structure.md` § *Presets*.

Run **one** Bash call that copies the preset's files into `./memory/`
(and `./scripts/`, `./PROTOCOL.md` as the preset dictates) with
**`cp -n`** — never overwrite an existing user file:

```bash
PROJECT_DIR="$(pwd)"
SRC="${CLAUDE_PLUGIN_ROOT}/memory-kit"
MONTH="$(date +%Y-%m)"
TODAY="$(date +%Y-%m-%d)"

mkdir -p "$PROJECT_DIR/memory/inbox"
# --- core / core-slim ---
cp -n "$SRC/memory/MEMORY.md"   "$PROJECT_DIR/memory/MEMORY.md"
cp -n "$SRC/memory/active.md"   "$PROJECT_DIR/memory/active.md"
# (standard|full only:)
cp -n "$SRC/memory/decisions.md" "$PROJECT_DIR/memory/decisions.md"
cp -n "$SRC/memory/workflows.md" "$PROJECT_DIR/memory/workflows.md"
# --- optional folders, per preset ---
mkdir -p "$PROJECT_DIR/memory/projects"
cp -n "$SRC/memory/projects/example-project.md" "$PROJECT_DIR/memory/projects/example-project.md"
# (full only: people/ companies/ prompts/ archive/ scripts/)
# --- inbox seed (always) ---
test -f "$PROJECT_DIR/memory/inbox/$MONTH.md" || \
  printf '# Memory Inbox — %s\n\nFreeform capture. Compact durable items into the right memory file later.\n\n## %s\n\n-\n' \
  "$MONTH" "$TODAY" > "$PROJECT_DIR/memory/inbox/$MONTH.md"
ls -R "$PROJECT_DIR/memory"
```

Tailor the copied set to the preset (the commented lines above show the
Standard additions; Full adds `people/`, `companies/`, `prompts/`,
`archive/.gitkeep`, `scripts/memory-search.sh` + `chmod +x`, and
`PROTOCOL.md`). For `protocol` (Standard + Full), also `cp -n` the
`PROTOCOL.md` and append the `<!-- cos-bot:memory -->` block to
`./CLAUDE.md` per `references/structure.md`.

Even in fast install, the `MEMORY.md` folder-guide block must be pruned
to the installed folders (`references/structure.md` § *folder-guide
assembly*) — do that prune with an `Edit` after the copy, since `cp`
brings the full template. For Minimal, also apply the slim variant.

Then print the summary directly:

```
Memory install complete (<preset>).

Installed at <project>/memory/:
  <tree of what landed>

Skipped (already existed):
  <list, or "none">

Search your memory:
  ./scripts/memory-search.sh "<query>"      (if `search` installed)

Re-run /cos-bot:install-memory (no args) any time to add components or
customize — it never overwrites your existing memory files.
```

If the Bash exits non-zero, abort with the captured stderr and a pointer
to reinstall the plugin (a missing `memory-kit/*` source is the only
realistic failure).

---

## Step 1 — `intake`

**Use `AskUserQuestion`, not chat turns.**

### 1a. Preset single-select

> A memory system is a `memory/` folder at your project root your
> assistant reads and writes across sessions. Pick a starting shape —
> you can toggle individual folders next, and re-run any time to add
> more.
>
> - **Standard** (recommended) — core files + `projects/` + `inbox/` + protocol doc
> - **Minimal** — just `MEMORY.md`, `active.md`, and `inbox/`
> - **Full** — everything: people, companies, prompts, archive, search script

Set `state.preset` to the choice. Persist.

### 1b. Component toggle multi-select

Show a multi-select of the **optional** components, **pre-checked to the
chosen preset's baseline** (see `references/structure.md` § *Intake
multi-select baseline*). The 4-option ceiling means splitting into two
batched questions (4 + 3):

> Q1: Which folders/extras do you want? (Multi-select — pre-checked to
> your preset)
>
> - `projects/` — one file per project
> - `people/` — collaborators, stakeholders
> - `companies/` — clients, partners
> - `prompts/` — reusable prompt patterns
>
> Q2: And these?
>
> - `archive/` — stale memory, excluded from search
> - `scripts/memory-search.sh` — ripgrep search over `memory/`
> - protocol doc — `PROTOCOL.md` + a block in `./CLAUDE.md`

Resolve `state.components`: always include the preset's core component
(`core` for Standard/Full, `core-slim` for Minimal) and `inbox`; add
each toggled-on optional component. Persist `state.components` and
`state.step = "preview"`.

---

## Step 2 — `preview`

Show a diff-style summary in chat (no `AskUserQuestion` yet — just a
written preview block):

```
About to install into <project>/:

Files to write:
  memory/MEMORY.md              (new)
  memory/active.md              (new)
  memory/decisions.md           (new)
  memory/workflows.md           (new)
  memory/projects/example-project.md   (new)
  memory/inbox/2026-05.md       (new — seeded)
  PROTOCOL.md                   (new)

Files skipped (already exist — memory is durable, never overwritten):
  memory/active.md              (skip — exists)

./CLAUDE.md:
  append one <!-- cos-bot:memory --> block   (or "replace existing block")

Schedule offer at the end:
  recurring memory-inbox compaction via /cos-bot:autopilot
```

Mark each path `(new)` or `(skip — exists)` — `test -f` each target
first so the preview is accurate. Mark the `./CLAUDE.md` line `append`
or `replace existing block` depending on whether a `<!-- cos-bot:memory -->`
marker is already present.

Then one `AskUserQuestion`:

> Proceed?
>
> - **Yes — write everything**
> - **No — go back and revise** (jumps to `intake`)
> - **Cancel** (keeps state, exits)

On "Yes," persist `state.step = "write"` and proceed. On "No," persist
`state.step = "intake"` and re-run Step 1.

---

## Step 3 — `write`

Copy the resolved `state.components` from
`${CLAUDE_PLUGIN_ROOT}/memory-kit/` into `<project>/` using the `Write`
tool (Read the source, Write the destination). **For every file: `test -f`
the destination first — if it exists, skip it and record it as skipped.
Never overwrite.** Memory is durable.

Order:

1. **`memory/` templates.** Per `state.components`: `core` writes
   `MEMORY.md` + `active.md` + `decisions.md` + `workflows.md`;
   `core-slim` writes only `MEMORY.md` + `active.md`. `projects` /
   `people` / `companies` / `prompts` write their `example-*.md`
   template. Copy verbatim — no per-user transforms.
2. **Assemble `MEMORY.md`.** After writing `MEMORY.md`, prune its
   folder-guide block to the installed folder set and strip the marker
   comments (`references/structure.md` § *folder-guide assembly*). For
   `core-slim`, also apply the slim variant (trim "Always read first").
   This is a deterministic `Edit` — skip it if `MEMORY.md` was skipped
   (already existed).
3. **`inbox/`** (always). Create `memory/inbox/` and, if it doesn't
   exist, the monthly seed file `memory/inbox/<YYYY-MM>.md` with the
   shape in `references/structure.md` § *File shapes*. Use `date +%Y-%m`
   / `date +%Y-%m-%d`.
4. **`archive/`** (if in components). `mkdir -p memory/archive` and
   write an empty `memory/archive/.gitkeep`.
5. **`scripts/memory-search.sh`** (if `search` in components). Copy from
   `memory-kit/scripts/`, then `chmod +x`.
6. **`PROTOCOL.md` + `./CLAUDE.md`** (if `protocol` in components). Copy
   `PROTOCOL.md` (skip-if-exists). Append the marker-guarded
   `<!-- cos-bot:memory -->` block to `./CLAUDE.md`, creating the file
   if absent; if a marker block already exists, replace it in place
   (idempotent — exactly one block after any number of runs). See
   `references/structure.md` § *managed-block convention*.

Append every path actually written to `state.written` (dedupe). Persist
`state.step = "schedule"`.

Print a one-line confirmation per file:

```
✓ wrote memory/MEMORY.md
- skipped memory/active.md (already exists)
✓ wrote PROTOCOL.md
✓ appended <!-- cos-bot:memory --> block to ./CLAUDE.md
```

(ASCII markers only — no emoji.)

---

## Step 4 — `schedule`

`inbox/` ships in every preset, so the compaction-routine offer always
applies. See `references/schedule.md` for the command body, cadence
table, offer Q&A, authorization Q&A, and dispatch logic. The shape:

1. Write `<project>/.claude/commands/compact-memory.md` (the compaction
   command body from `references/schedule.md`, skip-if-exists).
2. Run the offer Q&A (Weekly / Monthly / Not now).
3. If a cadence was picked, run the authorization Q&A and dispatch
   `/cos-bot:autopilot /compact-memory <cadence>` via nested `claude -p`
   (or print the paste-able command on "No").
4. Persist `state.scheduled = true` and `state.step = "done"`.

---

## Step 5 — `done`

Set `state.step = "done"`, persist. Print a final summary:

```
Memory install complete.

Installed at <project>/memory/:
  <tree of what landed — folders + files>

PROTOCOL.md:      written  (or "not installed")
./CLAUDE.md:      block appended  (or "not touched")
Search script:    ./scripts/memory-search.sh  (or "not installed")
Compaction:       armed weekly via /cos-bot:autopilot
                  (or "command written — arm later with the printed line"
                   or "skipped")

How to use it:
  - Your assistant reads memory/MEMORY.md and memory/active.md before
    meaningful work, and searches memory/ for prior context.
  - Jot loose notes into memory/inbox/<this-month>.md; compact them
    later (/compact-memory).
  - Read PROTOCOL.md for the full convention.

Re-run /cos-bot:install-memory any time to add components — it's
idempotent and never overwrites your existing memory files.
```

Omit lines that don't apply (no `search` installed → drop that line).

Second run with `step: "done"` should ask "Add more components / start
over / cancel?" — don't blindly re-execute.

---

## Safety / idempotency

- **Never overwrite an existing memory file.** Every write in Step 3 and
  every `cp` in Step F is skip-if-exists (`test -f` / `cp -n`). Re-runs
  only fill in missing components. This is the skill's overriding
  invariant — memory is durable, human-curated user content.
- The `./CLAUDE.md` `<!-- cos-bot:memory -->` block is the **only**
  managed write — and only the marked block, replaced in place, never
  the rest of the file.
- `reset` wipes the state file only, **never `./memory/`**.
- All Bash `allowed-tools` entries are patterns, never literal user
  data.
- Step 0a hard-aborts on any tool denial — no false "complete" summary
  with a partial install.
