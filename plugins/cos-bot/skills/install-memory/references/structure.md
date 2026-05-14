# Structure — presets, components, assembly rules

The SKILL.md owns orchestration (dispatch, state, step sequencing).
This file owns the static maps: what each preset contains, how the
`MEMORY.md` folder guide is assembled, and the `./CLAUDE.md` marker
convention.

---

## Bundled source layout

Canonical content ships inside the plugin at
`${CLAUDE_PLUGIN_ROOT}/memory-kit/`:

```
memory-kit/
├── PROTOCOL.md
├── memory/
│   ├── MEMORY.md
│   ├── active.md
│   ├── decisions.md
│   ├── workflows.md
│   ├── projects/example-project.md
│   ├── people/example-person.md
│   ├── companies/example-company.md
│   └── prompts/reusable.md
└── scripts/
    └── memory-search.sh
```

`inbox/` and `archive/` have **no bundled template** — they are created
empty at install time (`inbox/` gets a monthly `YYYY-MM.md` seed file;
`archive/` is just an empty directory with a `.gitkeep`).

Everything installs into `<project>/memory/`, `<project>/scripts/`, and
`<project>/PROTOCOL.md` — a self-contained folder at the project root,
**not** the `~/.claude/projects/<slug>/memory/` location that
`install-recipes` uses.

---

## Components

The atomic units the skill installs. `state.components` is the resolved
set of these keys.

| Key | What it installs |
|---|---|
| `core` | `memory/MEMORY.md`, `memory/active.md`, `memory/decisions.md`, `memory/workflows.md` |
| `core-slim` | `memory/MEMORY.md` (slim variant), `memory/active.md` only |
| `projects` | `memory/projects/example-project.md` |
| `people` | `memory/people/example-person.md` |
| `companies` | `memory/companies/example-company.md` |
| `prompts` | `memory/prompts/reusable.md` |
| `inbox` | `memory/inbox/<current YYYY-MM>.md` (seeded empty) |
| `archive` | `memory/archive/.gitkeep` (empty dir) |
| `search` | `scripts/memory-search.sh` (+ `chmod +x`) |
| `protocol` | `PROTOCOL.md` + the `<!-- cos-bot:memory -->` block in `./CLAUDE.md` |

`core` and `core-slim` are mutually exclusive — Minimal uses `core-slim`,
Standard and Full use `core`.

---

## Presets

| Preset | Components |
|---|---|
| **Minimal** | `core-slim`, `inbox` |
| **Standard** (default) | `core`, `projects`, `inbox`, `protocol` |
| **Full** | `core`, `projects`, `people`, `companies`, `prompts`, `inbox`, `archive`, `search`, `protocol` |

`inbox/` ships in **every preset** — it is the single freeform-capture
mechanism (`active.md` is structured current-state, not a dump). The
compaction routine in `references/schedule.md` therefore always applies.

### Intake multi-select baseline

After the preset single-select, Step 1 shows a multi-select of the
**optional** components, pre-checked to the chosen preset's baseline.
Optional components (the togglable set): `projects`, `people`,
`companies`, `prompts`, `archive`, `search`, `protocol`. `core` /
`core-slim` and `inbox` are not togglable — they always install.

Pre-check state by preset:

| Component | Minimal | Standard | Full |
|---|:--:|:--:|:--:|
| `projects` | ☐ | ☑ | ☑ |
| `people` | ☐ | ☐ | ☑ |
| `companies` | ☐ | ☐ | ☑ |
| `prompts` | ☐ | ☐ | ☑ |
| `archive` | ☐ | ☐ | ☑ |
| `search` | ☐ | ☐ | ☑ |
| `protocol` | ☐ | ☑ | ☑ |

The 4-option-per-question ceiling means the 7-option multi-select must
split into two batched questions (4 + 3).

---

## `MEMORY.md` folder-guide assembly

The bundled `memory/MEMORY.md` contains a marked block:

```
<!-- cos-bot:folder-guide:start -->
- `projects/` — ...
- `people/` — ...
- `companies/` — ...
- `prompts/` — ...
- `inbox/` — ...
- `archive/` — ...
<!-- cos-bot:folder-guide:end -->
```

At write time, **prune** the lines between the markers to only the
folders actually installed (deterministic — keyed off `state.components`).
Then strip the marker comments themselves. A folder line maps to its
component key: `projects`→`projects/`, `people`→`people/`, etc. `inbox/`
is always kept (always installed).

### Slim variant (`core-slim`, Minimal preset)

When installing `core-slim`, also trim the "Always read first" section
down to just `active.md` (drop the `decisions.md` and `workflows.md`
lines — those files aren't installed in Minimal). The folder guide for
Minimal ends up listing only `inbox/`.

The `decisions.md` / `workflows.md` write themselves are simply skipped
in `core-slim` — only `MEMORY.md` and `active.md` are written.

---

## File shapes

All `memory/` templates are copied **verbatim** from
`${CLAUDE_PLUGIN_ROOT}/memory-kit/memory/` — the skill applies no
per-user transforms. The only assembled file is `MEMORY.md` (folder-guide
prune, above).

The `inbox/` seed file is generated, not copied. Shape:

```markdown
# Memory Inbox — <YYYY-MM>

Freeform capture. Compact durable items into the right memory file later.

## <YYYY-MM-DD>

-
```

Use `date +%Y-%m` and `date +%Y-%m-%d` for the values.

---

## `./CLAUDE.md` managed-block convention

When `protocol` is in the component set, append a marker-guarded block
to `<project>/CLAUDE.md` (create the file if absent). The block:

```
<!-- cos-bot:memory -->
## Memory

This project uses a Markdown memory system under `memory/`. Read
`PROTOCOL.md` and `memory/MEMORY.md` before meaningful work; search
`memory/` for prior context with `./scripts/memory-search.sh "<query>"`.
<!-- cos-bot:memory -->
```

**Idempotency:** before appending, check whether a
`<!-- cos-bot:memory -->` marker already exists in `./CLAUDE.md`. If it
does, replace the existing block in place (between the two identical
markers) rather than appending a second one. A re-run must leave exactly
one block.

The block intentionally does not mention `./scripts/memory-search.sh`
when `search` was not installed — when assembling the block, drop the
trailing search sentence if `search ∉ state.components`.

---

## Safety invariants

- **Never overwrite an existing memory file.** Every write is
  skip-if-exists. Re-runs only fill in missing components. Memory is
  durable user content; the skill must never clobber it.
- The `./CLAUDE.md` block is the **only** exception to "never overwrite"
  — and only the marked block, replaced in place, never the rest of the
  file.
- `reset` wipes the state file only, never `./memory/`.
