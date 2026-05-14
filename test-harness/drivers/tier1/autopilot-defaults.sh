#!/usr/bin/env bash
# Tier 1 / autopilot smoke install + sub-verbs
#
# Drives `/cos-bot:autopilot /prep defaults` in a sandbox with a short
# interval so we see a fire + the sub-verbs without waiting hours.
# Asserts:
#   - runner file written at ~/.claude/commands/prep-autopilot.md
#   - registry file written + has prep-autopilot entry with last_status=active
#   - lockfile present, sleeper PID alive
#   - list sub-verb shows the entry
#   - stop sub-verb kills the sleeper, removes the lockfile, marks last_status=stopped
#
# Container mode strongly preferred — host mode will write to your
# real ~/.claude/commands/ and ~/.claude/channels/telegram/.
#
# To keep this test fast, we use a 60-second interval (defaults-fast),
# install + list + stop without actually waiting for a fire.

set -euo pipefail

DRIVER_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$DRIVER_DIR/../.." && pwd)"

# shellcheck source=../../lib/sandbox.sh
source "$HARNESS_ROOT/lib/sandbox.sh"
# shellcheck source=../../lib/assert.sh
source "$HARNESS_ROOT/lib/assert.sh"

if [[ "$IN_CONTAINER" = "0" ]]; then
  echo "[autopilot] WARNING: host mode will mutate your real ~/.claude state."
  echo "            Set CONFIRM_HOST=1 to proceed; otherwise re-run via Docker."
  if [[ "${CONFIRM_HOST:-0}" != "1" ]]; then
    exit 2
  fi
fi

parse_keep_flag "$@"
mk_sandbox
install_local_plugin

# Pre-seed a fake paired access.json so the autopilot's Step A2 (chat-id
# read) passes. The runner posts will fail in the sandbox (no real bot),
# but the arming flow completes regardless — Telegram is best-effort.
seed_paired_access "${TEST_SENDER_ID:-1234567}" "${TEST_CHAT_ID:-7654321}"

# Pre-install /prep into the project so autopilot's A1 (recipe-exists
# check) passes. Use the canonical body extraction the same way
# install-recipes Step F does it.
mkdir -p "$PROJECT_DIR/.claude/commands"
awk '/^## Slash-command body/{f=1;next} f && /^```markdown/{b=1;next} b && /^```/{exit} b' \
  "$REPO_ROOT/plugins/cos-bot/recipes/meeting-prep.md" > "$PROJECT_DIR/.claude/commands/prep.md"
assert_file_exists "$PROJECT_DIR/.claude/commands/prep.md"

# ---- arm ------------------------------------------------------------------

run_claude \
  --permission-mode bypassPermissions \
  --max-budget-usd 0.30 \
  -p --output-format json \
  "/cos-bot:autopilot /prep defaults"

capture_session_jsonl

assert_jq_eq "$REPORT_DIR/run.json" '.is_error' 'false'
assert_jq_eq "$REPORT_DIR/run.json" '.permission_denials | length' '0'

REGISTRY="$HOME/.claude/channels/telegram/.cos-bot-autopilot.json"
RUNNER="$HOME/.claude/commands/prep-autopilot.md"
LOCKFILE="$HOME/.claude/channels/telegram/.cos-bot-autopilot-prep-autopilot.pid"

assert_file_exists "$REGISTRY"
assert_file_exists "$RUNNER"
assert_file_exists "$LOCKFILE"

# Registry shape
assert_jq_eq "$REGISTRY" '.version' '1'
assert_jq_eq "$REGISTRY" '.entries["prep-autopilot"].slug' 'prep-autopilot'
assert_jq_eq "$REGISTRY" '.entries["prep-autopilot"].task' 'prep'
assert_jq_eq "$REGISTRY" '.entries["prep-autopilot"].last_status' 'active'

# Sleeper PID alive
SLEEPER_PID="$(cat "$LOCKFILE" 2>/dev/null || echo 0)"
if [[ "$SLEEPER_PID" -gt 0 ]] && kill -0 "$SLEEPER_PID" 2>/dev/null; then
  _assert_record PASS "sleeper PID $SLEEPER_PID is alive"
else
  _assert_record FAIL "sleeper PID $SLEEPER_PID is dead or unreadable"
fi

# Supervisor was bootstrapped on first arm
SUP_RUNNER="$HOME/.claude/commands/_autopilot-supervisor.md"
assert_file_exists "$SUP_RUNNER"
assert_jq_eq "$REGISTRY" '.entries["_autopilot-supervisor"].role' 'supervisor'

# ---- list ----------------------------------------------------------------

run_claude \
  --permission-mode bypassPermissions \
  -p --output-format json \
  "/cos-bot:autopilot list" \
  || _assert_record FAIL "list sub-verb errored"

# list output is in .result on the run.json — it should mention prep-autopilot
assert_stdout_contains "$REPORT_DIR/run.json" 'prep-autopilot'
assert_stdout_contains "$REPORT_DIR/run.json" 'supervisor'

# ---- stop ----------------------------------------------------------------

run_claude \
  --permission-mode bypassPermissions \
  -p --output-format json \
  "/cos-bot:autopilot stop prep-autopilot" \
  || _assert_record FAIL "stop sub-verb errored"

# Sleeper PID should now be dead
if [[ "$SLEEPER_PID" -gt 0 ]] && kill -0 "$SLEEPER_PID" 2>/dev/null; then
  _assert_record FAIL "sleeper PID $SLEEPER_PID still alive after stop"
else
  _assert_record PASS "sleeper PID $SLEEPER_PID killed by stop"
fi

# Lockfile removed
if [[ -f "$LOCKFILE" ]]; then
  _assert_record FAIL "lockfile $LOCKFILE still exists after stop"
else
  _assert_record PASS "lockfile $LOCKFILE removed after stop"
fi

# Registry entry marked stopped
assert_jq_eq "$REGISTRY" '.entries["prep-autopilot"].last_status' 'stopped'

# Perf gates — visibility only
TURNS="$(jq -r '.num_turns' "$REPORT_DIR/run.json")"
DUR_MS="$(jq -r '.duration_ms' "$REPORT_DIR/run.json")"
COST="$(jq -r '.total_cost_usd' "$REPORT_DIR/run.json")"
echo
echo "[perf] turns=$TURNS dur=${DUR_MS}ms cost=\$$COST"

assert_summary
status=$?
teardown
exit $status
