# Memory Index

The durable memory layer for this project. See `PROTOCOL.md` (project
root) for how to use it.

## Always read first

- `active.md` — current focus, open loops, recent changes
- `decisions.md` — important decisions and their rationale
- `workflows.md` — recurring ways of working

## Folder guide

<!-- cos-bot:folder-guide:start -->
- `projects/` — project-specific context, one file per project
- `people/` — people, collaborators, stakeholders
- `companies/` — companies, clients, partners
- `prompts/` — reusable prompts and prompt patterns
- `inbox/` — freeform capture; monthly `YYYY-MM.md` files, compact later
- `archive/` — stale or historical memory; excluded from search
<!-- cos-bot:folder-guide:end -->

## Memory principles

Memory should be short, durable, searchable, human-readable, and easy
to delete or correct. It is not a transcript dump.

## Search

Before answering anything that depends on prior context, search this
folder for project names, company names, people names, decisions,
workflows, and recurring terminology:

```bash
./scripts/memory-search.sh "<query>"
```
