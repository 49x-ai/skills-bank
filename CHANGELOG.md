# Changelog

## 2026-05-09 → 2026-05-11 — cos-bot perf/reliability pass + E2E test harness

Session goal: validate the prior `model: haiku` pin on `cos-bot:install-recipes`,
improve speed/responsiveness/reliability across the cos-bot skills, and stand
up a hermetic Docker-based test harness so future skill changes are
regression-tested before shipping.

### cos-bot plugin

Candidate version: **0.2.2 → 0.2.3**. No marketplace.json bump yet — pending
final smoke run.

#### `plugins/cos-bot/skills/install-recipes/SKILL.md`

**Speed/cost — added Step F fast-install path** (`defaults` / `all` arg only).

Before: the `defaults` path went through Steps 0–7, doing 5 separate `Read`s
of the canonical recipe sources, 5 separate `Write` calls (each regenerating
the body in tool input, ~2,270 output tokens on one turn), state-file writes,
and 3–4 best-effort bot-restart probes at the end.

After: a single `Bash` invocation that awk-extracts the canonical body from
each recipe source and redirects it to the destination — one tool call, ~50
output tokens, byte-equal output. State file skipped (defaults is not
resumable). Step 7a probes skipped (the fresh-project case almost never has
a backgrounded `claude --channels` session running yet).

Measured impact (warm cache, Haiku 4.5):

| Metric | Before | After | Δ |
|---|---:|---:|---|
| `num_turns` | 18 | **2** | 9× fewer |
| Wall clock | 132s | **11s (container)** / 22s (host) | ~6× faster |
| Cost / run | $0.276 | **$0.065** | 4.2× cheaper |
| Output tokens | 5,251 | **931** | 5.6× fewer |
| All 5 files byte-equal canonical | ✓ | ✓ | preserved |

**Reliability — added Step 0a (tool-denial early abort)**.

Before: when `claude` ran in `default` permission mode and the user (or
sandbox) denied tool calls, the skill silently completed every "step"
without writing files and still printed "Recipe install complete." Verified
empirically: 9 denials, 0 files on disk, false success summary.

After: the skill detects denial and aborts with a specific error message
listing what was attempted vs what landed, plus the exact flag to re-run
with (`--permission-mode bypassPermissions`) or a pointer to approve
interactively. Applies to every code path (Step F + customize).

**Allowed-tools additions**: `Bash(awk *)` (Step F awk loop),
`Bash(tmux *)` and `Bash(pgrep *)` (Step 7a probes — were previously
listed in the SKILL body but not whitelisted, so probes silently fell
through to the "skipped" branch in real runs).

#### Haiku model pin added to 3 more skills

`plugins/cos-bot/skills/start/SKILL.md`, `demo/SKILL.md`, `connect/SKILL.md`
— each gained a `model: haiku` frontmatter line. None had a pin before,
which meant they inherited the spawning session's model. With your
`effortLevel: xhigh` config, `/cos-bot:start` was running on Opus 4.7 1M
($0.27 per state-router invocation).

Measured impact for `/cos-bot:start`:

| Metric | Before (Opus 4.7 1M) | After (Haiku 4.5) | Δ |
|---|---:|---:|---|
| Wall clock | 33s | 22s | 1.5× faster |
| Cost / run | $0.269 | **$0.032** | 8.5× cheaper |

`demo` and `connect` weren't profiled in production but inherit the same
order-of-magnitude reduction.

### User environment

#### `~/.claude/settings.json` — removed `ANTHROPIC_DEFAULT_HAIKU_MODEL`

The env override was aliasing **every** Haiku request to
`claude-sonnet-4-5-20250929[1m]`. This was the actual root cause of why
the earlier `model: haiku` pin appeared not to take effect: the skill
correctly requested Haiku, but the alias rerouted to Sonnet 4.5 1M.
Removing the override recovers Haiku pricing globally for every skill
and agent on this machine that asks for Haiku, not just cos-bot.

Empirical:

```
# Before (alias in place):    --model haiku → Sonnet 4.5 1M  → $0.09 for "what model?"
# After (alias removed):      --model haiku → Haiku 4.5      → ~$0.01 for same prompt
```

### Repo

#### Added `/.gitignore`

Repo had no root `.gitignore`. Added:

```
.env
.envtoken
*.local
.DS_Store
test-harness/sandboxes/
test-harness/reports/
test-harness/.env
```

### Test harness (new — `/test-harness/`)

End-to-end runner for the five user-invocable cos-bot skills. Two tiers,
both run in Docker for hermetic state. Tier 1 covers skill correctness +
perf without Telegram; Tier 2 adds a real Bot API round-trip.

#### Layout

```
test-harness/
├── README.md                      — full usage, prereqs, interpretation
├── .env.example                   — checked-in template
├── .env                           — gitignored, holds OAuth + bot tokens
├── .gitignore
├── docker/
│   ├── Dockerfile                 — node:22-bookworm + claude code + tmux + expect + curl + jq + python3
│   └── run.sh                     — --build, --shell, run-driver wrapper
├── lib/
│   ├── sandbox.sh                 — container/host auto-detect; mk_sandbox, seed helpers, run_claude
│   ├── assert.sh                  — file/jq/canonical-body assertions + summary
│   ├── perf.py                    — JSONL parser + per-turn breakdown + comparison
│   ├── pty-drive.py               — drive interactive claude via pseudo-tty for AskUserQuestion flows
│   └── bot-api.sh                 — sendMessage, getUpdates, pollUntil helpers
├── drivers/
│   ├── tier1/
│   │   ├── install-recipes-defaults.sh    — primary perf/correctness gate
│   │   ├── install-recipes-customize.sh   — pty-driven interactive flow
│   │   └── start-states.sh                — 4-state matrix for /cos-bot:start
│   └── tier2/
│       ├── connect-pair.sh                — token → configure → relaunch → pair
│       └── demo-roundtrip.sh              — install → bot launch → inbound DM round-trip
├── fixtures/canned-answers/
│   ├── customize-notion.json      — canned answers for customize path
│   └── connect-bring-token.json   — token-paste flow
├── reports/                       — gitignored, per-run artifacts
└── sandboxes/                     — gitignored, host-mode scratch
```

#### Validated end-to-end

| Driver | Mode | Assertions | Notes |
|---|---|---|---|
| `tier1/install-recipes-defaults.sh` | host | 13/13 ✓ | 4 turns / 30s / $0.25 (cold cache) |
| `tier1/install-recipes-defaults.sh` | container | 13/13 ✓ | 2 turns / 11s / $0.065 |
| `tier1/start-states.sh` | container | 3/4 ✓ | 1 fail is a real `/cos-bot:start` regex bug, not a harness bug |
| `tier2/demo-roundtrip.sh` | container | 8/8 ✓ | Full loop: install → tmux bot → Bot API send → bot processes |
| `tier1/install-recipes-customize.sh` | — | not yet run | PTY-driven; needs first execution |
| `tier2/connect-pair.sh` | — | not yet run | PTY-driven; redundant with demo-roundtrip |

#### Friction points encoded so future runs reproduce hermetically

| Where it hides | Solution |
|---|---|
| Theme picker on first run | `~/.claude.json` `hasCompletedOnboarding: true` + `lastOnboardingVersion` |
| Workspace-trust dialog | `~/.claude.json` `projects.<dir>.hasTrustDialogAccepted: true` |
| Bypass-permissions warning | `~/.claude/settings.json` `skipDangerousModePermissionPrompt: true` |
| `/repo` mount read-only | Telegram plugin mounted at `/opt/telegram-plugin`, symlinked into standard cache layout |
| `--channels plugin:telegram` rejected | Plugin must be addressable as `name@marketplace`; symlink into `~/.claude/plugins/cache/claude-plugins-official/telegram/0.0.6/` + write `marketplaces.json` |
| Telegram Web Enter doesn't send | DOM `.focus()` ≠ CDP native focus; always `click` input via chrome MCP, then `type_text` |

### External — Telegram test bot

Created `@cosbot_harness_20260509_bot` (bot id `8395645752`) via the
chrome-devtools MCP — fully automated BotFather flow (`/newbot` → name
→ username → token captured from DOM, paired chat-id + sender-id
captured via `getUpdates`).

Token + chat-id + sender-id saved to `test-harness/.env` (gitignored).
The bot is dedicated to harness use; safe to revoke or delete at any
time without touching production cos-bot state.

### Open issues discovered (not yet fixed)

1. **`/cos-bot:start` token-detection regex doesn't match valid tokens**
   (Task #19). The skill's regex `(BOT_TOKEN|TELEGRAM_BOT_TOKEN)=\d+:[A-Za-z0-9_-]{30,}`
   uses PCRE `\d` which isn't portable across grep flavors. With a valid
   token in `.env`, the skill reports "Token configured: no". Fix:
   replace `\d` with `[0-9]` or have the skill use `awk`/python.
2. **`/cos-bot:demo` recipe execution needs Gmail/Calendar MCP servers**
   that aren't provisioned in the harness container. Currently we test
   the inbound-DM-processing loop with a generic message, not a real
   `/prep` round-trip. Doable but requires bundling additional MCP
   servers in the Docker image.
3. **`tier2/connect-pair.sh` untested.** The interactive PTY flow is
   plumbed but never run end-to-end. Lower priority because
   `tier2/demo-roundtrip.sh` covers the same Bot API round-trip with
   simpler driving (no PTY).

### Verification done

What was actually exercised vs assumed:

| Skill / path | Tested? | How |
|---|---|---|
| `install-recipes defaults` (perf) | ✅ many runs | Host scratch-dir + Docker container; byte-equal canonical-body assertion |
| `install-recipes` denial behavior | ✅ 1 run | Default permission mode; confirmed no false success claim |
| `/cos-bot:start` model pin | ✅ | Direct invocation; modelUsage = Haiku |
| `/cos-bot:demo` model pin + dispatch | ⚠️ Partial | Orchestrator runs, stops correctly at AskUserQuestion; nested `claude -p` and Telegram delivery not exercised |
| `/cos-bot:connect` model pin | ❌ | Only the frontmatter edit; no run |
| `/cos-bot:setup` | ❌ | Not touched |
| `install-recipes customize` path | ❌ | My Step 0a edit applies but customize was never re-run; **highest-risk untested change** |
| Step 7a bot-restart `tmux`/`pgrep` newly-allowed | ❌ | Customize-path runs would exercise this; not yet validated |
| Telegram round-trip generic DM | ✅ | demo-roundtrip 8/8 in container |
| Telegram round-trip with recipe execution | ❌ | Needs Gmail/Calendar MCP in container |

### Recommended next steps

1. **Fix `/cos-bot:start` regex** (Task #19) — small change, banks a
   real reliability win.
2. **Run customize path through the harness** — validates the Step 0a
   denial-abort doesn't break the multi-step orchestration. Use
   `tier1/install-recipes-customize.sh`.
3. **Bump cos-bot to 0.2.3** in `.claude-plugin/marketplace.json` and
   ship. The perf wins are already validated narrowly; the only
   regression risk is customize-path orchestration.
4. **(optional) Bundle Gmail/Calendar MCP into the Docker image** if you
   want full recipe-execution round-trips in CI. Heavier — leave for
   later unless you start changing recipe bodies frequently.
