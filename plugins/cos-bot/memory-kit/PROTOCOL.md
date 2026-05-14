# Memory Protocol

This project uses a Markdown-first memory system under `memory/`. It is
durable, human-curated context — not a transcript store. Keep it short,
searchable, and easy to delete or correct.

## Before meaningful work

1. Read `memory/MEMORY.md` — the index and folder guide.
2. Read `memory/active.md` — current focus and open loops.
3. If the task mentions a project, person, company, decision, or prior
   context, search `memory/` before answering (see *Search* below).
4. Prefer targeted reads over loading many files.

## Save

- Project decisions and their rationale
- Architecture and tooling choices
- User preferences and recurring constraints
- Repeatable workflows / operating procedures
- People and company context relevant to future work
- Lessons likely to matter again

## Do not save

- Secrets, tokens, credentials
- Raw chat transcripts
- Temporary todos
- Large pasted documents
- Speculation, unless clearly marked as such
- Personal details that don't affect future work

## Where things go

- `active.md` — structured current state (focus, open loops, constraints).
  Not a freeform dump.
- `inbox/YYYY-MM.md` — the freeform capture file. Jot anything here when
  the right home isn't obvious; compact it later.
- `decisions.md` — durable decisions, newest first.
- `workflows.md` — reusable ways of working.
- `projects/`, `people/`, `companies/` — one file per entity.
- `prompts/` — reusable prompt patterns.
- `archive/` — stale or superseded memory; kept for history, skipped by search.

## When asked to "update memory"

1. Review the relevant memory files.
2. Identify only durable facts, decisions, constraints, or learnings.
3. Write compact Markdown to the most relevant file.
4. Prefer updating an existing file over creating a new one.
5. Use `inbox/` only when the right destination is unclear.

When unsure whether something belongs in memory, ask before saving it.

## When asked to "compact memory"

1. Read the current monthly `inbox/` file.
2. Move durable items to their proper file.
3. Delete or archive temporary items.
4. Update `active.md` if priorities or open loops changed.
5. Keep the final memory short.

## Search

```bash
./scripts/memory-search.sh "<query>"
```

Searches every `memory/**/*.md` except `archive/`. Run it before
answering anything that depends on prior context.
