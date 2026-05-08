# Deterministic transforms

These are **string edits**, not LLM rewrites. Apply them in order to the
extracted canonical body. Each transform is a no-op if its trigger
condition is false — passing an empty `state.profile` and
`state.deltas[<slug>]` produces the canonical body verbatim, which is
the `defaults` fast-path contract.

This file is referenced by the install-recipes SKILL.md `write` step.
The SKILL.md captures the orchestration; this file captures the
transforms catalog.

---

## Profile-driven (apply to every recipe)

### Persona footer

If `profile.persona` is set and not `skip`, append a footer block at
the end of the body, just before the closing of the markdown:

```
For drafts, follow the persona in `feedback_persona.md`.
```

If `profile.persona === "skip"` but legacy `feedback_tone.md` exists,
fall back to the old footer for compatibility:

```
For drafts, follow the tone in `feedback_tone.md`.
```

If neither file exists, omit the footer.

### Stack swap

If `profile.stack === "Notion"`, replace the literal substring `Linear
issue` with `Notion page` and `Linear issues` with `Notion pages`.

If `profile.stack === "Neither"`, drop the issues-lookup section in
each affected recipe by *contains*-match (not starts-with) on these
anchors:

- `prep` step 2: drop the sub-bullet whose text contains `open Linear
  issue mentioning them`.
- `who` step 5: drop the sentence/line whose text contains `Linear
  issues mentioning them`.
- `catchup` step 3 (the numbered `**Issues.**` heading + its body):
  drop the entire numbered item (heading + paragraph) up to the next
  numbered heading.

`Both` is a no-op (canonical body already mentions Linear; Notion is
additive in the user's own setup).

### Mix

If `profile.mix === "mostly internal"`, in `prep` and `who` swap the
email-lookup wording per each recipe's own "Customizing" section:

- `prep`: replace step 2's "last 3 email threads" wording with "recent
  Slack thread + Linear issue mentioning them" (drop the "company from
  email domain" sub-bullet).
- `who`: replace step 2's "most recent email" wording with "most recent
  Slack DM or Linear issue."

`mostly external` and `balanced` leave the email-lookup wording intact.

---

## Per-recipe (apply only to that slug)

### `prep`

- `editorial: false` → strip the paragraph that begins
  `The "3 questions" line is your editorial` and the words `, **3 questions
  I should ask**` from the four-sections list.

### `inbox-triage`

- `drafts: false` → strip the three lines under "For each **Reply now**
  thread" that mention `2-3 sentence draft reply` and `Tag it: \`DRAFT
  — not sent\``. Keep the 1-line summary and thread ID lines.
- `vipOnly: true` → prepend a line right after the `# /inbox-triage`
  heading: `Only include threads where the sender matches my VIPs (see
  \`reference_vips.md\`).` Drop nothing else; the existing "skip CC,
  skip newsletters, skip automated" filters still apply on top.

### `awaiting`

- `addSlack: true` → after section 2's body, insert a section 3:
  `**Awaiting Slack reply.** Open Slack DMs where the latest message is
  from someone else, in the last 14 days. Cap at 8.` Renumber the Stale
  section to 4.

### `who`

- `editorial: false` → strip the paragraph beginning `The "What I might
  be missing" line is your editorial` and the words `, **What I might
  be missing**` from the four-sections list.
- `biggerDossier: true` → after step 5's body, insert a step 6:
  `**Their open commitments to me.** Pull from \`/awaiting\` —
  threads where they owe me a reply or where I'm waiting on a deliverable
  from them. Cap at 5.`

### `catchup`

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

---

## After all transforms

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

## Implementation notes

- **No nested LLM rewrites.** All transforms are deterministic string
  edits. If a knob's transform isn't documented above, don't invent one
  — leave the canonical body untouched. This keeps the install
  reviewable and stable across runs.
- **The `defaults` fast path is the contract.** Empty `state.profile` +
  empty `state.deltas` must produce the canonical body verbatim for
  every recipe. If you find yourself adding a transform that fires on
  empty input, you've broken this contract — fix the trigger.
- **Preserve frontmatter and hard rules.** Every transform must keep
  the recipe's `---\n…\n---` frontmatter and its `Hard rule(s):` line(s)
  intact. The voice/format spec for these recipes is non-negotiable
  (Telegram-shape: no preamble, no emoji, hard rule line). If a
  transform would violate that, abort the write for that recipe.
- **Transforms use `contains`-semantics, not `starts-with`.** The
  `stack === "Neither"` and `skipAggressiveness === "loose"`
  transforms anchor on substrings that appear mid-line in the
  canonical bodies (e.g. `Linear issues mentioning them`,
  `"automated", "internal noise"`). Match by *contains* on the
  documented anchor strings, then drop the containing line/sub-bullet/
  numbered item per the transform's intent. Don't switch to literal
  whole-line equality — the canonical bodies aren't formatted for it.
- **Don't touch the bundled recipe sources.** The recipe bodies under
  `${CLAUDE_PLUGIN_ROOT}/recipes/*.md` ship with the plugin and are
  read-only canon — do not edit them in place inside
  `~/.claude/plugins/`. The destination for personalization is
  `<project>/.claude/commands/`. If a canonical body needs fixing, fork
  the plugin (`49x-ai/skills-bank`) and submit a PR; local edits will
  be blown away by the next plugin update.
