#!/usr/bin/env bash
# Tier 1 / install-recipes customize path
#
# Drives the full interactive flow via pty-drive.py + canned answers.
# Asserts:
#   - 5 recipe files written
#   - state.step="done" in .cos-bot-recipes.json
#   - profile fields persisted (vips, persona, stack, mix)
#   - memory files exist (reference_vips.md, feedback_persona.md, project_stack.md, project_mix.md)
#   - At least one transform applied (e.g. inbox-triage shows persona-tuned tone or stack=Notion influence)
#
# Container mode strongly preferred — host mode will pollute your real
# ~/.claude/channels/telegram/.cos-bot-recipes.json.

set -euo pipefail

DRIVER_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$DRIVER_DIR/../.." && pwd)"
ANSWERS="${ANSWERS:-$HARNESS_ROOT/fixtures/canned-answers/customize-notion.json}"

# shellcheck source=../../lib/sandbox.sh
source "$HARNESS_ROOT/lib/sandbox.sh"
# shellcheck source=../../lib/assert.sh
source "$HARNESS_ROOT/lib/assert.sh"

if [[ "$IN_CONTAINER" = "0" ]]; then
  echo "[customize] WARNING: host mode will mutate your real ~/.claude state."
  echo "            Set CONFIRM_HOST=1 to proceed; otherwise re-run via Docker."
  if [[ "${CONFIRM_HOST:-0}" != "1" ]]; then
    exit 2
  fi
fi

parse_keep_flag "$@"
mk_sandbox
install_local_plugin

if [[ ! -f "$ANSWERS" ]]; then
  echo "error: canned-answers file not found: $ANSWERS" >&2
  exit 2
fi

# Build the claude argv. In host mode we need --plugin-dir.
CLAUDE_ARGS=()
if [[ "$IN_CONTAINER" = "0" ]]; then
  CLAUDE_ARGS+=(--plugin-dir "$REPO_ROOT/plugins/cos-bot")
fi
CLAUDE_ARGS+=(--permission-mode bypassPermissions)

(
  cd "$PROJECT_DIR"
  CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN" \
    python3 "$HARNESS_ROOT/lib/pty-drive.py" \
      --config "$ANSWERS" \
      --output "$REPORT_DIR/pty.log" \
      -- claude "${CLAUDE_ARGS[@]}"
) || _assert_record FAIL "pty-drive exited non-zero (see $REPORT_DIR/pty.log)"

# ---- assertions -----------------------------------------------------------

# 5 command files written
for slug in prep inbox-triage awaiting who catchup; do
  assert_file_exists "$PROJECT_DIR/.claude/commands/$slug.md"
done

# State file should exist with step=done and 5 written entries.
if [[ "$IN_CONTAINER" = "1" ]]; then
  STATE_FILE="$HOME/.claude/channels/telegram/.cos-bot-recipes.json"
else
  STATE_FILE="$HOME/.claude/channels/telegram/.cos-bot-recipes.json"
fi

assert_file_exists "$STATE_FILE"
assert_jq_eq "$STATE_FILE" '.step' 'done'
assert_jq_eq "$STATE_FILE" '.selected | length' '5'
assert_jq_eq "$STATE_FILE" '.written | length' '5'

# Profile fields persisted
assert_jq_eq "$STATE_FILE" '.profile.persona // empty' 'warm'
assert_jq_eq "$STATE_FILE" '.profile.stack // empty' 'Notion'

# Memory files written (in the project's memory dir).
# Memory dir slug: PROJECT_DIR with / -> -, leading dash included.
MEM_SLUG="$(echo "$PROJECT_DIR" | sed 's|/|-|g')"
MEM_DIR="$HOME/.claude/projects/$MEM_SLUG/memory"
assert_file_exists "$MEM_DIR/reference_vips.md"
assert_file_exists "$MEM_DIR/feedback_persona.md"
assert_file_exists "$MEM_DIR/project_stack.md"
assert_file_exists "$MEM_DIR/project_mix.md"

# At least one transform took effect somewhere (Notion mention)
if grep -qiE 'notion' "$PROJECT_DIR/.claude/commands/"*.md "$MEM_DIR"/*.md; then
  _assert_record PASS "Notion stack transform present in output"
else
  _assert_record FAIL "no Notion mention found in any output (transforms may not have applied)"
fi

assert_summary
status=$?
teardown
exit $status
