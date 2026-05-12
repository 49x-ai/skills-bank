#!/usr/bin/env bash
# bot-api.sh — small helpers for driving the Telegram Bot API in tests.
#
# All helpers read TEST_BOT_TOKEN and TEST_CHAT_ID from env. Source this
# after sandbox.sh.

# Send a text message to the test chat as the bot.
# Usage: bot_send_message "/prep"
bot_send_message() {
  local text="$1"
  : "${TEST_BOT_TOKEN:?required}"
  : "${TEST_CHAT_ID:?required}"
  curl -sS --max-time 15 \
    -F "chat_id=$TEST_CHAT_ID" \
    -F "text=$text" \
    "https://api.telegram.org/bot$TEST_BOT_TOKEN/sendMessage"
}

# Drain pending updates so subsequent polls don't see stale messages.
# Bot API getUpdates is read-once-and-confirm; pass `offset=last+1` to ack.
bot_drain_updates() {
  : "${TEST_BOT_TOKEN:?required}"
  local resp last
  resp="$(curl -sS --max-time 10 "https://api.telegram.org/bot$TEST_BOT_TOKEN/getUpdates?timeout=0&limit=100")"
  last="$(echo "$resp" | jq '[.result[].update_id] | max // 0')"
  if [[ "$last" -gt 0 ]]; then
    curl -sS --max-time 10 \
      "https://api.telegram.org/bot$TEST_BOT_TOKEN/getUpdates?offset=$((last + 1))&timeout=0&limit=1" \
      >/dev/null
  fi
}

# Poll getUpdates for an outbound message from the bot to the test chat
# whose text contains the given substring. Times out after `seconds`.
# Echoes the matching update JSON on success, returns 1 on timeout.
#
# Usage:
#   bot_drain_updates
#   bot_send_message "/prep"
#   bot_wait_for_reply "Who's there" 60
bot_wait_for_reply() {
  local needle="$1" timeout="${2:-60}"
  : "${TEST_BOT_TOKEN:?required}"
  local deadline=$(( $(date +%s) + timeout ))
  local offset=0
  while (( $(date +%s) < deadline )); do
    local resp
    resp="$(curl -sS --max-time 30 \
      "https://api.telegram.org/bot$TEST_BOT_TOKEN/getUpdates?timeout=10&offset=$offset")"
    local updates
    updates="$(echo "$resp" | jq '.result // []')"
    local len
    len="$(echo "$updates" | jq 'length')"
    if [[ "$len" -gt 0 ]]; then
      offset="$(echo "$updates" | jq '[.[].update_id] | max + 1')"
      # Bot replies arrive as the bot's own messages — getUpdates only
      # surfaces inbound messages from users. To detect bot replies we
      # use sendMessage's response chain or read from the channel side.
      # For a reliable test we instead look for ECHOED user messages
      # from the bot (the cos-bot replies to the test user).
      local match
      match="$(echo "$updates" | jq -c --arg n "$needle" \
        '.[] | select(.message.text? | test($n; "i"))' | head -1)"
      if [[ -n "$match" ]]; then
        echo "$match"
        return 0
      fi
    fi
    sleep 2
  done
  return 1
}

# Variant that polls *outbound* via the Bot API's getUpdates from the
# user side. Telegram's getUpdates only returns inbound messages to the
# bot. To detect the bot's reply, we either:
#   (a) use a second user-bot pair where bot A relays to bot B (overkill)
#   (b) ssh into the cos-bot tmux session and `tmux capture-pane` for the
#       reply (best for hermetic harness use)
#
# This helper implements (b): polls the local tmux session for the
# bot's last reply line.
bot_wait_for_tmux_reply() {
  local session="${1:-cos-bot}"
  local needle="$2"
  local timeout="${3:-60}"
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    if ! tmux has-session -t "$session" 2>/dev/null; then
      echo "[bot-api] tmux session '$session' missing" >&2
      return 1
    fi
    if tmux capture-pane -p -t "$session" | grep -qiF "$needle"; then
      tmux capture-pane -p -t "$session" | grep -iF "$needle" | head -1
      return 0
    fi
    sleep 1
  done
  return 1
}
