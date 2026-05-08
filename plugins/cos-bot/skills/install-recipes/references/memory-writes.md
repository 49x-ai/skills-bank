# Memory writes

This file is the canonical reference for the four memory files
install-recipes writes (`reference_vips.md`, `feedback_persona.md`,
`project_stack.md`, `project_mix.md`) and the `MEMORY.md` index entry
for each.

The persona file shape lives in `references/persona.md` (it's owned by
the persona dispatch as well). This file documents the other three plus
the index conventions.

For each profile field that turns into memory, write a separate file
under the project's memory directory using the auto-memory frontmatter
shape from the user's global `CLAUDE.md`. Then append a one-line index
entry to `MEMORY.md` (create `MEMORY.md` if missing — no frontmatter on
the index file itself).

---

## Memory directory

`~/.claude/projects/<slug>/memory/`, where `<slug>` is the absolute
`projectDir` with `/` replaced by `-` (leading dash included). For
example, `/Users/jane/work/my-project` →
`~/.claude/projects/-Users-jane-work-my-project/memory/`.

`mkdir -p` it lazily — only when memory is about to be written.

---

## File shapes

### `reference_vips.md` — `type: reference`

Body: the user's comma-separated VIP list, one entry per line.
Reference memories should be terse pointers per the global memory
schema, so the body is just the list. The "Used by …" footer below is
**optional context** — include it on first write to orient the user;
skip it on re-writes where the file already exists with a similar
footer.

```markdown
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

### `feedback_persona.md` — `type: feedback`

See `references/persona.md` for the full body shape, preset table, and
`MEMORY.md` entry for this file. Both surfaces (profile pass +
`persona` argument dispatch) must produce byte-identical output for
the same axis values.

Skip writing this file entirely if the user picks `Skip — neutral
defaults` in the profile pass — the chief-of-staff agent falls back to
neutral defaults when the file is absent.

### `project_stack.md` — `type: project`

Body: the chosen stack with **Why:** and **How to apply:**.

```markdown
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

### `project_mix.md` — `type: project`

Body: the chosen internal/external mix.

```markdown
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

### Legacy `feedback_tone.md`

If it exists from a previous install, **don't delete it** here. The
agent prefers `feedback_persona.md` and falls back to the old file
only if persona is absent. `/cos-bot:install-recipes persona reset` is
the only path that removes the persona file; the legacy file stays
around as a safety net.

---

## `MEMORY.md` index

`MEMORY.md` is an index, not a memory — no frontmatter, one line per
entry, under ~150 chars per line. Append entries for each new memory
file. Format:

```
- [VIPs](reference_vips.md) — high-priority senders for triage and dossier recipes
- [Persona](feedback_persona.md) — Chief of Staff voice and posture
- [Issue tracker / docs stack](project_stack.md) — Linear / Notion / Both / Neither
- [Communication mix](project_mix.md) — external / internal / balanced
```

Before appending, **read `MEMORY.md`** and check whether the line
already exists (match on the link target, e.g. `(reference_vips.md)`).
If present, leave the index alone — the file content was updated, the
index entry is still correct.

---

## Memory pre-read (Step 2a)

Before asking anything in the profile pass, scan the memory directory
for existing answers:

| Memory file | Profile field |
|---|---|
| `reference_vips.md` | `vips` |
| `feedback_persona.md` | `persona` (full schema — preset + axes) |
| `feedback_tone.md` | `persona` (legacy fallback — used only if `feedback_persona.md` is absent; surface the existing tone in the preamble so the user can upgrade) |
| `project_stack.md` | `stack` |
| `project_mix.md` | `mix` (internal/external) |

For each one that exists, read it and pre-fill `state.profile.<field>`.
**Skip the corresponding question** in the batched profile call unless
the user explicitly asked to revise (free-text "revise" anywhere in
the flow → drop pre-fills, re-ask all four).

For each memory file that exists, surface a one-line summary at the
top of the AskUserQuestion preamble: *"Found existing memory for VIPs
and persona — I'll reuse them. Type 'revise' to change."*

---

## Update vs. create

- If the memory file does **not** exist: create it, append to
  `MEMORY.md`, add to `state.memoriesWritten`.
- If the memory file exists and the user **revised** their answer:
  overwrite the file with the new body, leave `MEMORY.md` untouched.
- If the memory file exists and the user did **not** revise (i.e. the
  pre-read filled the answer in step 2a): do nothing — neither file nor
  index changes.

---

## Implementation notes

- **Memory writes are durable across sessions.** The state file is
  scratch — it gets reset by `/cos-bot:install-recipes reset`. The
  memory files do not. Treat `reset` as a "redo the install Q&A,"
  not as "wipe the user's preferences."
- **Memory pre-read is cheap.** Always do it, even on `<name>`
  invocations. It's cheaper than asking the user a question they've
  already answered, and it lets the skill silently skip step 2 entirely
  when memory is fully populated.
