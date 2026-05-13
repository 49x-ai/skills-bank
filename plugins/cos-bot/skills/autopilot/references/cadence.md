# Cadence — shapes, parsing, backoff, drift

Owned by the cadence Q&A in `SKILL.md` § A4 and by the runner's
"compute next fire" block in `references/runner-template.md`.

---

## Cadence shapes

### Fixed interval

`shape: "fixed"`. `intervalOrTime` is a duration: `30s`, `5m`, `2h`,
`1d`. Stored in seconds: `interval: <int>`. Sub-`60s` is rejected at A4
(too tight to be useful).

`next_fire = anchor + n * interval`, where `anchor` is the first
`started_at` and `n` = smallest integer making `next_fire > now`.

### Time-of-day

`shape: "time"`. `intervalOrTime` is one or more local-TZ times:
`09:00`, `09:00,15:00`, `09:00 weekdays`, `09:00 Tue,Thu`. Parsing:

- Extract `HH:MM` tokens. Anchored to the user's `date` timezone (no
  attempt to resolve cross-TZ).
- Day filter: `weekdays` → `Mon-Fri`, `weekends` → `Sat,Sun`, or a
  comma-list of three-letter day names.
- `next_fire` = next matching `HH:MM` on a matching day, looking
  forward from `now`. Stored as ISO.

### Adaptive

`shape: "adaptive"`. The recipe decides the next interval on each fire
by writing to the registry's per-slug `cadence.next_delta_seconds`
field. The runner reads this field after the recipe runs; if absent,
falls back to the initial interval.

Stop conditions must be set explicitly here (the recipe can also emit
a stop signal — see *Stop conditions*).

The recipe's output protocol (parsed by the runner):

```
AUTOPILOT_NEXT_DELTA_SECONDS=<int>   # for next run, optional
AUTOPILOT_STOP=<reason>              # halt the autopilot, optional
```

The runner greps the recipe's stdout for these tokens. Anything else in
the output is forwarded to Telegram as the recipe's user-visible reply.

### One-shot

`shape: "once"`. `intervalOrTime` is a single ISO timestamp. After
firing once, the autopilot self-removes from the registry. Useful for
"remind me at 3pm tomorrow."

---

## Default cadence per recipe (used by `<task> defaults`)

Mirrors the cron table in
`/plugins/cos-bot/skills/install-recipes/references/schedule.md`:

| Recipe | Default cadence | Shape |
|---|---|---|
| `prep` | `09:00 weekdays` | time |
| `inbox-triage` | `11:00,15:00 weekdays` | time |
| `awaiting` | `10:00 Tue,Thu` | time |
| `catchup` | `every 4h` | fixed |
| `who` | (no default — needs an argument; refuse `defaults` for `who`) | — |

Default `stop_by` for `defaults`: `+30 days from now`. Default
`max_runs`: `null`. The user can always extend or stop early via
sub-verbs.

---

## Parsing free-text inputs (`AskUserQuestion` → registry)

Examples and their parses:

| Input | Shape | Parsed |
|---|---|---|
| `every 5m` | fixed | `interval: 300` |
| `every 2h` | fixed | `interval: 7200` |
| `daily 9am` | time | `times: ["09:00"], days: ["all"]` |
| `9am weekdays` | time | `times: ["09:00"], days: ["Mon","Tue","Wed","Thu","Fri"]` |
| `9am,3pm Mon,Wed,Fri` | time | `times: ["09:00","15:00"], days: ["Mon","Wed","Fri"]` |
| `adaptive` | adaptive | `interval: 600` (default 10m initial) |
| `at 2026-05-13T18:00` | once | `at: "2026-05-13T18:00:00-05:00"` |

Parsing failures → re-prompt with the table above. Don't silently
default — bad cadence is worse than bad UX.

---

## Stop conditions (mandatory; pick at least one)

The interview at A4 collects one or more of:

- `max_runs: <int>` — halt after N successful fires.
- `stop_by: <ISO>` — halt when `now > stop_by`.
- `stop_on_signal: true` — halt when the recipe emits `AUTOPILOT_STOP=<reason>`.

The runner evaluates all three in order on every fire; first match halts.

---

## Failure backoff

Stored in the registry as `consecutive_failures: <int>`. On each fire:

- If the recipe succeeds (exit 0, no `AUTOPILOT_STOP`), reset
  `consecutive_failures = 0`, advance `next_fire` per the cadence.
- If the recipe fails (non-zero exit, or known error signal in
  stdout), increment `consecutive_failures` and back off:
  - 1st fail: `next_fire = now + 1×interval`
  - 2nd fail: `next_fire = now + 2×interval`
  - 3rd fail: `next_fire = now + 4×interval`
  - After 4 consecutive fails (capped): halt the autopilot, post
    `Autopilot halted: <slug> — 4 consecutive failures, last error: <…>`
    to Telegram, set `last_status: "halted"`.

For `shape: "time"`, the backoff still applies but bounded by the next
scheduled time-of-day — never push past it.

---

## Absolute next-fire-time (anti-drift)

Always compute next-fire from the **anchor** + `n × interval`, not from
`now + interval`. Without this, a 10-minute cadence drifts ~1 fire per
hour due to recipe execution time + sleep wake jitter.

```
anchor_ts        = registry[slug].anchor            (ISO, frozen at arm-time)
interval_seconds = registry[slug].cadence.interval
elapsed          = now - anchor_ts
n                = ceil(elapsed / interval_seconds)
next_fire_ts     = anchor_ts + n * interval_seconds
N                = next_fire_ts - now
```

For time-of-day, the anchor is implicit (the time-of-day itself).
Compute `next_fire` as "the next occurrence of HH:MM on a matching day,
strictly after `now`." No drift possible.

---

## Edge cases

- **DST.** Time-of-day computation uses the local `date` command, which
  respects the system TZ database. A `09:00 weekdays` autopilot crossing
  a DST boundary will fire at 9 AM wall-clock both before and after the
  switch — which is what the user wants.
- **Sleep skew on laptop suspend.** A `sleep` call across a laptop
  suspend wakes when the laptop wakes, not at the original target. The
  supervisor's health-check catches this on its next cycle and notes
  it in the runs log. No code action — user-visible only.
- **Clock changes.** If the user manually sets the clock backward,
  next-fire times in the registry will be far in the future. The
  supervisor reads `now` on each cycle and won't re-arm anything until
  the clock advances. Document only.
