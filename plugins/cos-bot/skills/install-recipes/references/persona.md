# Persona — preset table, axes, and write logic

The Chief of Staff persona lives in
`~/.claude/projects/<slug>/memory/feedback_persona.md` and is read by the
`chief-of-staff` sub-agent on every recipe run (see
`${CLAUDE_PLUGIN_ROOT}/agents/chief-of-staff.md`).

This file is the canonical reference for the persona schema, the three
named presets, the four axes, and the `feedback_persona.md` body shape.
The install-recipes SKILL.md routes to this file from:

- The **profile pass** (Step 2 — collects a preset on first install).
- The **`persona` argument dispatch** (`/cos-bot:install-recipes persona [preset|tune|show|reset]` — preset/per-axis tuner, anytime).

There is **one source of truth** for the `feedback_persona.md` body —
this file. The chief-of-staff agent only reads; it never writes.

---

## Persona axes

Four axes. Three presets pin all four; tune mode lets the user set each
independently.

| Axis | Values | Effect on output |
|---|---|---|
| `formality` | `terse` / `friendly` / `formal` | Draft tone register. terse = short bullets, no filler. friendly = warm, contractions allowed. formal = full sentences, no contractions. |
| `proactivity` | `proactive` / `reactive` | Whether the agent surfaces editorial bullets ("one thing I might miss") and unprompted observations. proactive = include them. reactive = answer the literal ask only. |
| `name` | free-text (or empty) | Self-reference. Empty = no sign-off. Default per preset; user can override. |
| `reasoning_hint` | `conclusion-first` / `chronological` / `none` | Structure on memo-style recipes (`/tackle`, `/catchup` long form, `/who` long form). conclusion-first = lead with the answer. none = whatever fits the recipe. |

A fifth optional flag lives alongside the axes:

| Flag | Values | Effect |
|---|---|---|
| `brain_dump_capture` | `on` / `off` (default: `on`) | Whether the chief-of-staff agent auto-captures long inbound Telegram messages (≥200 words) verbatim into `brain-dumps/`. See `${CLAUDE_PLUGIN_ROOT}/agents/chief-of-staff.md` § *Brain-dump capture*. |

---

## Presets

Three named starting points. Each pins all four axes.

| Slug | Display name | Formality | Proactivity | Name (default) | Reasoning hint |
|---|---|---|---|---|---|
| `mbb` | MBB Consultant | `formal` | `proactive` | `CoS` | `conclusion-first` |
| `warm` | Warm Exec Assistant | `friendly` | `reactive` | `Sam` | `none` |
| `blunt` | Blunt Chief of Staff | `terse` | `proactive` | `Chief` | `none` |

After a preset is picked, individual axes can be overridden without
leaving the named preset (the preset label stays for reference;
overrides are applied on top). If any axis differs from the preset's
default, render the preset label as
`Custom (started from <preset name>)`.

---

## Profile-pass question (used by `intake`'s "customize?" branch)

When install-recipes runs the profile pass and `feedback_persona.md`
isn't already in memory, ask one single-select inside the batched
profile call:

> Pick a Chief of Staff persona. (Tune individual axes later with
> `/cos-bot:install-recipes persona tune`.)
>
> - **MBB Consultant** — formal, proactive, conclusion-first
> - **Warm Exec Assistant** — friendly, reactive, plain prose
> - **Blunt Chief of Staff** — terse, proactive, sharp editorial
> - **Skip — neutral defaults**

Map the answer to a slug:

- `MBB Consultant …` → `mbb`
- `Warm Exec Assistant …` → `warm`
- `Blunt Chief of Staff …` → `blunt`
- `Skip — neutral defaults` → `skip`

If `skip`, **do not write** `feedback_persona.md` — the agent falls back
to neutral defaults (`friendly` / `reactive` / no name / no reasoning
hint) when the file is absent.

If a legacy `feedback_tone.md` exists but no `feedback_persona.md`, the
question still fires — surface the existing tone in the preamble so the
user knows they're upgrading: *"You currently have tone = `<formality>`.
Pick a persona to upgrade:"*. Don't migrate silently.

---

## `persona` argument dispatch (the tuner)

Invoked via `/cos-bot:install-recipes persona [preset|tune|show|reset]`.
Each branch is short — the heavy lifting is the body render below.

### `persona` *(no second arg)* — interactive

1. Read `feedback_persona.md` if present; build `state.current` (axes +
   preset label).
2. If absent, check `feedback_tone.md` → derive `formality` from the
   first match of `terse` / `friendly` / `formal` in the body; other
   axes default to neutral. Mark `state.current.source =
   "feedback_tone.md (migrated)"` so step 4's confirmation can mention
   the upgrade.
3. If neither, neutral defaults across the board.
4. Surface the current persona, then one `AskUserQuestion` (4 options):

   > - **MBB Consultant** — formal, proactive, conclusion-first
   > - **Warm Exec Assistant** — friendly, reactive, plain prose
   > - **Blunt Chief of Staff** — terse, proactive, sharp editorial
   > - **Tune from scratch** — set each axis individually

5. Map to `mbb` / `warm` / `blunt` / `tune` and proceed below.

### `persona <preset>` — `mbb` / `warm` / `blunt`

1. Apply the preset's defaults to `state.next` from the table above.
2. Offer overrides via one `AskUserQuestion` (multi-select, 4 axes):

   > Override any defaults? (Multi-select, or pick "None" to accept the preset.)
   >
   > - **Formality** — preset is `<formality>`.
   > - **Proactivity** — preset is `<proactivity>`.
   > - **Name** — preset is `<name>`.
   > - **None — accept the preset as-is**

3. For each override picked, ask a follow-up:
   - `formality` → terse / friendly / formal (single-select)
   - `proactivity` → proactive / reactive (single-select)
   - `name` → Keep `<preset-default>` / Empty (no name) / Other (free-text)
4. If any axis differs from the preset, set `state.next.preset =
   "Custom (started from <preset name>)"`. Otherwise keep the preset
   display name.

### `persona tune`

Skip the preset picker. One batched `AskUserQuestion` (4 axes — fits the
4-option ceiling exactly):

> 1. Formality: terse / friendly / formal
> 2. Proactivity: proactive / reactive
> 3. Name: free-text (or empty for no self-reference)
> 4. Reasoning hint: conclusion-first / chronological / none

Pre-fill defaults from `state.current` so the user can keep their
existing axes and only change the ones they care about. Set
`state.next.preset = "Custom"`.

### `persona show`

Read `feedback_persona.md`, print:

```
Current persona: <Preset name or "Custom">
  Formality:      <formality>
  Proactivity:    <proactivity>
  Name:           <name or "(none)">
  Reasoning hint: <reasoning_hint>

Brain-dump capture: <on | off>

Source: <feedback_persona.md | feedback_tone.md (migrated) | (no persona on file)>

To change: /cos-bot:install-recipes persona [mbb|warm|blunt|tune|reset]
```

Stop. Don't write anything.

### `persona reset`

One `AskUserQuestion`:

> Reset persona to neutral defaults? This deletes
> `feedback_persona.md` for this project. The chief-of-staff sub-agent
> will fall back to `friendly` / `reactive` / no name / no reasoning
> hint until you set a new persona.
>
> - **Yes — reset**
> - **No — keep current persona**

If yes:

1. `rm -f <memory-dir>/feedback_persona.md`.
2. Read `MEMORY.md`; remove the line matching `(feedback_persona.md)`
   if present. Don't touch other lines.
3. Print: `Persona reset. The chief-of-staff sub-agent will use neutral defaults.`

The legacy `feedback_tone.md` is **not** deleted — the agent falls back
to it if persona is absent. `reset` restores "no persona," not "no
tone."

---

## `feedback_persona.md` body shape

Both surfaces (profile pass + `persona` dispatch) **must produce
byte-identical output** for the same axis values. Render from this
template:

```markdown
---
name: persona
description: How the Chief of Staff should sound and act — formality, proactivity, name, reasoning hint.
type: feedback
---

- Preset: <preset display name>
- Formality: <formality>
- Proactivity: <proactivity> (<short gloss — see below>)
- Name: <name or "(none)">
- Reasoning hint: <reasoning_hint>
- Brain-dump capture: <on | off>

**Why:** User picked this persona via `/cos-bot:install-recipes`. The
chief-of-staff sub-agent reads this file on every recipe run and
modulates output accordingly.
**How to apply:** Apply formality to draft tone, proactivity to whether
to surface editorial bullets unprompted, name as the bot's
self-reference, reasoning hint to memo structure on `/tackle` /
`/catchup` / `/who` long form. `Brain-dump capture: off` disables the
agent's auto-capture of long inbound Telegram messages.
```

**Proactivity glosses** (one short clause each — render verbatim):

- `proactive` → "co-thinker who acts; surfaces editorial bullets unprompted"
- `reactive` → "waits for asks; no editorial unless explicitly requested"

**`Brain-dump capture` line is optional.** Omit it on first write
(profile pass) — the agent treats absence as `on` (the default). Only
emit the line when the user has explicitly toggled it off via the
`persona tune` flow's brain-dump question, or when re-rendering a file
that already has the line.

`name: ""` (empty) is valid — the default-no-name behavior is "agent
doesn't sign off." Render as `(none)` in printed summaries.

---

## `MEMORY.md` index entry

After writing `feedback_persona.md`, ensure `MEMORY.md` has a line
pointing at it. Read `MEMORY.md` first; if it does **not** already
contain `(feedback_persona.md)`, append:

```
- [Persona](feedback_persona.md) — Chief of Staff voice and posture
```

`MEMORY.md` is a flat index — no frontmatter, one line per entry,
under ~150 chars per line. Don't add per-axis entries; the persona
file itself is the index target.

---

## Legacy migration (`feedback_tone.md`)

Earlier versions of cos-bot wrote a single-axis tone file. The
chief-of-staff agent prefers `feedback_persona.md` and falls back to
the old file only when persona is absent.

- **Don't auto-migrate.** When the legacy file exists alone, surface
  the existing tone in the persona question's preamble and let the user
  pick a preset on the way through.
- **Don't delete the legacy file** when writing persona. It stays
  around as a safety net. `reset` does not touch it either — `reset`
  removes persona only, restoring "no persona," which means falling
  back to whatever `feedback_tone.md` says (if anything).
- The agent's read order is `feedback_persona.md` → `feedback_tone.md`
  → neutral defaults.

---

## Implementation notes

- **One source of truth.** `feedback_persona.md` is owned by
  `/cos-bot:install-recipes` (both profile pass and `persona` arg).
  The chief-of-staff agent only reads. Don't let other recipes or
  skills write the persona directly.
- **Idempotent re-rendering.** Picking the same preset with no
  overrides should be a no-op write, not a skip — the file gets
  re-rendered with the same contents. This makes "I want to re-confirm
  my persona" a one-command operation.
- **Don't validate too hard.** Free-text names, empty names, and
  unicode are all fine. The agent treats `Name:` as guidance, not a
  hard contract — it's not going to break anything.
- **AskUserQuestion ceiling.** 4 options per question. The interactive
  picker uses exactly 4 (3 presets + tune-from-scratch). The override
  batch uses 4 axes (formality / proactivity / name / "none").
- **No emoji in skill output.** ASCII-only summaries match the rest
  of cos-bot's terminal output style.
- **Brain-dump capture toggle lives here, not in a separate file.**
  Persona axes and the brain-dump flag share a memory file because
  both modulate the chief-of-staff agent's behavior. Adding a fifth
  axis or another agent flag should follow the same pattern.
