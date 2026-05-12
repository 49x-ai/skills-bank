#!/usr/bin/env bash
# Tier 1 / start state matrix
#
# /cos-bot:start is a read-only state inspector that dispatches the right
# next skill. Cover all 4 states by pre-seeding the sandbox HOME:
#   A. empty                    — no token, no access.json, no recipes
#   B. token-only               — token configured, not paired
#   C. paired-no-recipes        — token + access.json, project commands/ empty
#   D. paired+recipes           — full setup, all 5 commands present
#
# Assert via stdout substring that start picked the right downstream skill:
#   A → /cos-bot:setup or /cos-bot:connect (asks)
#   B → /cos-bot:connect
#   C → /cos-bot:install-recipes
#   D → /cos-bot:demo (or "add or tune recipes")
#
# Container mode only — host mode shares ~/.claude with the host's real
# config and we can't fake the empty / paired-no-recipes states there.

set -euo pipefail

DRIVER_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$DRIVER_DIR/../.." && pwd)"

# shellcheck source=../../lib/sandbox.sh
source "$HARNESS_ROOT/lib/sandbox.sh"
# shellcheck source=../../lib/assert.sh
source "$HARNESS_ROOT/lib/assert.sh"

if [[ "$IN_CONTAINER" = "0" ]]; then
  echo "[start-states] this driver only runs in container mode (uses HOME isolation)" >&2
  echo "               run via: test-harness/docker/run.sh drivers/tier1/start-states.sh" >&2
  exit 2
fi

parse_keep_flag "$@"

# Reusable per-state runner. We can't reuse a single sandbox because
# install_local_plugin / claude state would persist across cases.
# Inside Docker each `docker run` is fresh, but within ONE run we only
# get one `$HOME`. So we run each case as a separate sub-script invoked
# fresh in another container — but for simplicity here, mutate $HOME
# between cases and assert per-case.

run_case() {
  local label="$1" expect_substring="$2"
  local case_dir="$REPORT_DIR/state-$label"
  mkdir -p "$case_dir"
  echo
  echo "==================================================================="
  echo "[start-states] case=$label, expect substring: '$expect_substring'"
  echo "==================================================================="

  PROJECT_DIR="$(mktemp -d -t cos-bot-start-$label-XXXXXX)"
  case "$label" in
    A-empty)
      # Wipe channel + plugin scratch; keep plugin install.
      rm -rf "$HOME/.claude/channels"
      ;;
    B-token-only)
      rm -rf "$HOME/.claude/channels"
      mkdir -p "$HOME/.claude/channels/telegram"
      printf 'TELEGRAM_BOT_TOKEN=%s\n' \
        "${TEST_BOT_TOKEN:-1234567890:fixture-token-pretend-this-is-real-aaaaaaaa}" \
        > "$HOME/.claude/channels/telegram/.env"
      chmod 600 "$HOME/.claude/channels/telegram/.env"
      ;;
    C-paired-no-recipes)
      rm -rf "$HOME/.claude/channels"
      mkdir -p "$HOME/.claude/channels/telegram"
      printf 'TELEGRAM_BOT_TOKEN=%s\n' \
        "${TEST_BOT_TOKEN:-1234567890:fixture-token-pretend-this-is-real-aaaaaaaa}" \
        > "$HOME/.claude/channels/telegram/.env"
      chmod 600 "$HOME/.claude/channels/telegram/.env"
      seed_paired_access "${TEST_SENDER_ID:-1968884338}" "${TEST_CHAT_ID:-1968884338}"
      ;;
    D-paired-with-recipes)
      mkdir -p "$PROJECT_DIR/.claude/commands"
      for slug in prep inbox-triage awaiting who catchup; do
        case "$slug" in prep) src=meeting-prep ;; *) src="$slug" ;; esac
        awk '/^## Slash-command body/{f=1;next} f && /^```markdown/{b=1;next} b && /^```/{exit} b' \
          "/repo/plugins/cos-bot/recipes/${src}.md" > "$PROJECT_DIR/.claude/commands/${slug}.md"
      done
      ;;
  esac

  local out="$case_dir/run.json"
  (
    cd "$PROJECT_DIR"
    CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN" \
      claude --plugin-dir /repo/plugins/cos-bot \
             --permission-mode bypassPermissions \
             --max-budget-usd 0.20 \
             -p --output-format json \
             "/cos-bot:start" > "$out" 2> "$case_dir/run.stderr"
  )

  echo "[case $label] $(jq -c '{turns: .num_turns, dur_ms: .duration_ms, cost: .total_cost_usd, model: (.modelUsage | keys | .[0])}' "$out")"

  if jq -r .result "$out" | grep -qiF "$expect_substring"; then
    _assert_record PASS "case $label dispatch contains '$expect_substring'"
  else
    _assert_record FAIL "case $label expected '$expect_substring', got: $(jq -r .result "$out" | head -c 200)"
  fi
}

mk_sandbox
install_local_plugin

run_case A-empty            "/cos-bot:setup"       || true
run_case B-token-only       "/cos-bot:connect"     || true
run_case C-paired-no-recipes "/cos-bot:install-recipes" || true
run_case D-paired-with-recipes "/cos-bot:demo"     || true

assert_summary
status=$?
teardown
exit $status
