# Per-recipe deltas — knob Q&A tables

The deltas step (Step 3 of install-recipes' SKILL.md) asks one batched
`AskUserQuestion` per selected recipe covering only that recipe's
specific knobs. This file lists each recipe's knobs, their questions,
and the option strings.

Skip the deltas step entirely when `state.customize === false`. The
defaults-first lead in Step 1 sets `customize = false`; only the
explicit "Pick recipes & tweak" branch flips it to `true`.

If a recipe has only one knob and a clear default, you may pre-fill
it silently and skip the call — note the choice in the preview step.

Persist `state.deltas[<slug>]` after each call.

---

## `prep`

| Knob | Question | Options |
|---|---|---|
| `editorial` | "Include the '3 questions I should ask' editorial section?" | `Yes (recommended)` / `No — skip the editorial line` |
| `schedule` | "When should `/prep` fire?" | `Q-dispatcher (7:30am reads calendar, schedules each meeting -30m)` / `D-loop (every 15 min, fires for upcoming meetings)` / `On-demand only (no schedule)` |

## `inbox-triage`

| Knob | Question | Options |
|---|---|---|
| `drafts` | "Include 2-3 sentence draft replies for the 'Reply now' bucket?" | `Yes (recommended)` / `No — pure triage list` |
| `schedule` | "When should `/inbox-triage` fire?" | `11am + 3pm weekdays` / `3pm only` / `On-demand only` |
| `vipOnly` | "VIP-only mode? Only triage threads where the sender matches your VIPs." | `No — triage everything (recommended)` / `Yes — VIP-only` |

## `awaiting`

| Knob | Question | Options |
|---|---|---|
| `schedule` | "When should `/awaiting` fire?" | `Tue + Thu 10am (recommended)` / `On-demand only` |
| `addSlack` | "Add a section pulling open Slack DMs where the latest message is from someone else?" | `No — email only` / `Yes — include Slack section` |

## `who`

| Knob | Question | Options |
|---|---|---|
| `editorial` | "Include the 'What I might be missing' editorial section?" | `Yes (recommended)` / `No — skip the editorial line` |
| `biggerDossier` | "Bigger dossier? Add a 'their open commitments to me' section pulled from `/awaiting`." | `No — standard dossier` / `Yes — include commitments` |

## `catchup`

| Knob | Question | Options |
|---|---|---|
| `longAbsence` | "Include a 'decisions made without me' section for long absences (>5 days)?" | `Yes (recommended)` / `No` |
| `skipAggressiveness` | "How aggressive should the 'Skip' bucket be?" | `default (skip automated/marketing/CC)` / `loose (only automated)` |
