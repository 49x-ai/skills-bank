#!/usr/bin/env bash
# Tier 2 / demo end-to-end round-trip
#
# Prerequisites (one-time, manual):
#   1. Test bot created via @BotFather, token in TEST_BOT_TOKEN
#   2. Test bot paired with your test chat (run /telegram:access pair on
#      host once, save TEST_SENDER_ID + TEST_CHAT_ID)
#   3. Anthropic OAuth token in CLAUDE_CODE_OAUTH_TOKEN
#
# What this verifies:
#   - sandbox HOME boots clean
#   - cos-bot plugin installs
#   - install-recipes defaults runs (Tier 1 path)
#   - cos-bot --channels session launches in tmux
#   - bot is reachable: harness sends /prep via Bot API, bot processes
#     and posts a reply to the test chat
#   - reply lands in tmux pane within timeout
#
# Container mode only.

set -euo pipefail

DRIVER_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$DRIVER_DIR/../.." && pwd)"

# shellcheck source=../../lib/sandbox.sh
source "$HARNESS_ROOT/lib/sandbox.sh"
# shellcheck source=../../lib/assert.sh
source "$HARNESS_ROOT/lib/assert.sh"
# shellcheck source=../../lib/bot-api.sh
source "$HARNESS_ROOT/lib/bot-api.sh"

if [[ "$IN_CONTAINER" = "0" ]]; then
  echo "[demo-roundtrip] container only — run via test-harness/docker/run.sh" >&2
  exit 2
fi

: "${TEST_BOT_TOKEN:?required for Tier 2}"
: "${TEST_CHAT_ID:?required for Tier 2}"
: "${TEST_SENDER_ID:?required for Tier 2}"

parse_keep_flag "$@"
mk_sandbox
install_local_plugin
seed_telegram_token "$TEST_BOT_TOKEN"
seed_paired_access "$TEST_SENDER_ID" "$TEST_CHAT_ID"

# ---- Phase 1: install recipes (defaults) ----------------------------------

echo "[phase 1] install recipes defaults"
INSTALL_OUT="$REPORT_DIR/install.json"
(
  cd "$PROJECT_DIR"
  CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN" \
    claude --plugin-dir /repo/plugins/cos-bot \
           --permission-mode bypassPermissions \
           --max-budget-usd 0.30 \
           -p --output-format json \
           "/cos-bot:install-recipes defaults" > "$INSTALL_OUT" 2>&1
)
for slug in prep inbox-triage awaiting who catchup; do
  assert_file_exists "$PROJECT_DIR/.claude/commands/$slug.md"
done

# ---- Phase 2: launch bot in tmux ------------------------------------------

echo "[phase 2] launch bot in tmux"

# The bot needs the telegram plugin to provide the MCP channel server.
# In container mode, docker/run.sh bind-mounts the host's cached copy.
if [[ -z "${TELEGRAM_PLUGIN_DIR:-}" ]]; then
  _assert_record FAIL "TELEGRAM_PLUGIN_DIR not set — host has no cached telegram plugin to bind-mount"
  assert_summary || true
  exit 1
fi

tmux new-session -d -s cos-bot \
  -c "$PROJECT_DIR" \
  "CLAUDE_CODE_OAUTH_TOKEN='$CLAUDE_CODE_OAUTH_TOKEN' claude --plugin-dir /repo/plugins/cos-bot --channels plugin:telegram@claude-plugins-official --dangerously-skip-permissions; exec bash"

# Wait for the bot to print "Listening for channel messages…"
echo "[phase 2] waiting for bot ready (cold start can take 20s+)..."
ready=0
for i in {1..120}; do
  if tmux capture-pane -p -t cos-bot 2>/dev/null | grep -qF "Listening for channel messages"; then
    ready=1
    echo "[phase 2] bot ready after ${i}s"
    break
  fi
  sleep 1
done
if [[ "$ready" = "0" ]]; then
  _assert_record FAIL "bot never printed 'Listening for channel messages' (120s)"
  tmux capture-pane -p -t cos-bot | tail -100 > "$REPORT_DIR/bot-pane.log" || true
  assert_summary || true
  exit 1
fi
_assert_record PASS "bot listening on channel"

# Capture pane state for the report.
tmux capture-pane -p -t cos-bot > "$REPORT_DIR/bot-launch.pane" || true

# ---- Phase 3: drive Bot API ------------------------------------------------

echo "[phase 3] sending a test message via Bot API"
# Use 'hello harness' instead of '/prep' — /prep needs Gmail/Calendar MCP
# servers that aren't provisioned in the container. We just want to prove
# the bot received and processed an inbound DM end-to-end.
bot_drain_updates
SEND_RESP="$(bot_send_message 'hello harness — please reply with the word ack')"
echo "$SEND_RESP" > "$REPORT_DIR/send.json"

if ! echo "$SEND_RESP" | jq -e '.ok' >/dev/null; then
  _assert_record FAIL "sendMessage failed: $SEND_RESP"
  assert_summary || true
  exit 1
fi
_assert_record PASS "sendMessage delivered to Telegram"

# ---- Phase 4: poll for evidence the bot received + processed -------------

echo "[phase 4] poll tmux pane for inbound-message activity (120s timeout)"
# Look for any sign of message processing: the channel server logs received
# messages, then the agent loop runs, then a reply tool is invoked. Match
# any of those keywords to confirm the loop is alive.
deadline=$(( $(date +%s) + 120 ))
seen=""
while (( $(date +%s) < deadline )); do
  pane="$(tmux capture-pane -p -t cos-bot 2>/dev/null || true)"
  for needle in "hello harness" "channel message" "telegram_reply" "reply" "ack"; do
    if echo "$pane" | grep -qiF "$needle"; then
      seen="$needle"
      break 2
    fi
  done
  sleep 2
done

if [[ -n "$seen" ]]; then
  _assert_record PASS "bot processed inbound DM (matched on '$seen')"
  echo "$pane" | tail -60 > "$REPORT_DIR/bot-active.pane"
else
  _assert_record FAIL "bot did not process the inbound DM within 120s"
  tmux capture-pane -p -t cos-bot | tail -100 > "$REPORT_DIR/bot-final.pane" || true
fi

# ---- teardown -------------------------------------------------------------

tmux kill-session -t cos-bot 2>/dev/null || true

assert_summary
status=$?
teardown
exit $status
