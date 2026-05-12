# cos-bot test harness

End-to-end runner for the cos-bot plugin. Two tiers, both run in Docker
for hermetic state. Tier 1 is local-only (Anthropic API + sandbox `$HOME`);
Tier 2 adds a real Telegram bot for the inbound/outbound roundtrip.

```
test-harness/
├── docker/
│   ├── Dockerfile                 # node:22 + claude code + tmux + expect + curl + jq
│   └── run.sh                     # build + invoke a driver in the container
├── lib/
│   ├── sandbox.sh                 # mk_sandbox, run_claude, capture_session_jsonl, teardown
│   ├── assert.sh                  # file/jq/canonical-body assertions
│   ├── perf.py                    # JSONL → tokens/cost/latency report
│   ├── pty-drive.py               # drives interactive claude (AskUserQuestion answers)
│   └── bot-api.sh                 # Telegram Bot API helpers (Tier 2)
├── drivers/
│   ├── tier1/                     # hermetic — no Telegram
│   │   ├── install-recipes-defaults.sh
│   │   ├── install-recipes-customize.sh    # uses pty-drive.py
│   │   └── start-states.sh
│   └── tier2/                     # real Telegram round-trip
│       ├── connect-pair.sh
│       └── demo-roundtrip.sh
├── fixtures/
│   └── canned-answers/            # pty-drive.py inputs
├── reports/                       # gitignored — per-run artifacts land here
├── sandboxes/                     # gitignored (host mode only)
├── .env.example                   # checked-in template
└── .env                           # gitignored — fill in tokens
```

## One-time setup

### Anthropic auth

```bash
claude setup-token
```

This opens a browser; copy the long-lived OAuth token it prints into
`test-harness/.env`:

```
CLAUDE_CODE_OAUTH_TOKEN=oauth_...
```

The token is required for every harness run. Sandbox `$HOME` inside
the container has no keychain, so OAuth is the only auth path.

### Tier 2 — test bot creation (manual, ~5 min)

You need a **dedicated test bot** that is NOT your production cos-bot.
Harness runs send and receive real Telegram messages; running them
against your real bot would pollute your real chat history.

1. Open Telegram, DM `@BotFather`, send `/newbot`.
2. Name it something like `Cos-Bot Harness Test` and pick a username
   ending in `_test_bot`.
3. BotFather replies with a token like `8290…XOJU`. Paste it into
   `.env` as:

   ```
   TEST_BOT_TOKEN=8290…XOJU
   ```

4. Find a chat to use as the test target. Easiest: DM the new bot
   yourself (find it by username, send `/start`). It'll error
   ("Pairing required") — that's fine, we just need a chat to exist.
5. Capture your chat-id and your Telegram user-id by hitting:

   ```bash
   curl -s "https://api.telegram.org/bot$TEST_BOT_TOKEN/getUpdates" | jq
   ```

   Look for `result[0].message.chat.id` and `result[0].message.from.id`.
   Paste them into `.env`:

   ```
   TEST_CHAT_ID=<from result[0].message.chat.id>
   TEST_SENDER_ID=<from result[0].message.from.id>
   ```

6. Pair the test bot with your test chat. The cleanest path is one
   manual run on the host:

   ```bash
   # In a real Claude Code session:
   /cos-bot:connect
   # Paste TEST_BOT_TOKEN, follow the relaunch + pair flow.
   ```

   That mints `~/.claude/channels/telegram/access.json` with the test
   sender approved. Copy it into the harness fixture for replay:

   ```bash
   cp ~/.claude/channels/telegram/access.json \
      test-harness/fixtures/test-bot-access.json
   ```

   The `connect-pair.sh` Tier 2 driver reproduces this from scratch
   inside the container; the fixture is a fast-path for `demo-roundtrip.sh`.

## Run a driver

### Tier 1 (no Telegram needed)

```bash
test-harness/docker/run.sh drivers/tier1/install-recipes-defaults.sh
test-harness/docker/run.sh drivers/tier1/install-recipes-customize.sh
test-harness/docker/run.sh drivers/tier1/start-states.sh
```

Each driver:
- Spawns a fresh container with `--rm` (no leftover state).
- Mounts the repo read-only at `/repo`, mounts `reports/` writable.
- Installs the cos-bot plugin into the container `$HOME`.
- Runs the skill, captures `run.json`, `session.jsonl`, `pty.log`.
- Asserts the expected files / state / model.
- Writes `report.md` and `perf.json` via `lib/perf.py`.

Pass `--keep` to leave artifacts on the host:

```bash
test-harness/docker/run.sh drivers/tier1/install-recipes-defaults.sh --keep
ls test-harness/reports/<runid>/
```

### Tier 2 (real Telegram)

```bash
test-harness/docker/run.sh drivers/tier2/demo-roundtrip.sh
test-harness/docker/run.sh drivers/tier2/connect-pair.sh
```

Tier 2 needs `TEST_BOT_TOKEN`, `TEST_CHAT_ID`, `TEST_SENDER_ID` in `.env`.
The `demo-roundtrip` driver uses your prepared paired access.json so
it skips the BotFather flow and just exercises the inbound→reply loop.

### Host fast-iteration mode (no Docker)

For tight perf loops you can run drivers directly on the host. The
sandbox auto-detects: it'll use your real keychain (no OAuth token
needed) and stick artifacts in `test-harness/sandboxes/<runid>/`.
Caveat: this shares your real `~/.claude/` so the `start-states` and
`customize` drivers will refuse to run (would mutate your real config).

```bash
bash test-harness/drivers/tier1/install-recipes-defaults.sh --keep
```

## Interpreting reports

`reports/<runid>/`:

- `run.json` — Claude SDK output (`result`, `total_cost_usd`, `usage`,
  `permission_denials`, `modelUsage`).
- `session.jsonl` — per-turn timeline copied from
  `~/.claude/projects/<slug>/<sessionId>.jsonl`.
- `perf.json` — parsed per-turn breakdown.
- `report.md` — human-readable summary.
- `assertions.log` — pass/fail per assertion.
- `run.stderr` — claude's stderr (rare; mostly empty).
- `pty.log` — full pty transcript when the driver used pty-drive.py.

Compare two runs:

```bash
python3 test-harness/lib/perf.py compare \
  test-harness/reports/<runid-a> \
  test-harness/reports/<runid-b>
```

## Caveats

- **Anthropic API costs are real.** The defaults driver costs ~$0.10 per
  run on Haiku. Pin `--max-budget-usd` in drivers to cap.
- **`pty-drive.py` is heuristic.** It matches plain substrings against
  ANSI-stripped stdout. Skill prompt-text changes will break canned
  answers — refresh `fixtures/canned-answers/*.json` when prompts shift.
- **Tier 2 needs a working test bot.** Bot setup is a one-time manual
  step; failures during harness runs (silent-stop, etc.) require the
  recovery patterns in `BACKGROUNDING.md` (kill + respawn).
- **Token rotation.** If a token leaks (committed by accident, pasted
  in a chat), revoke immediately via `@BotFather → /revoke`.
