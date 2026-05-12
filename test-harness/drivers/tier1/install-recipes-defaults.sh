#!/usr/bin/env bash
# Tier 1 / install-recipes defaults
#
# Runs `/cos-bot:install-recipes defaults` headless and asserts:
#   - exit success, no permission denials
#   - all 5 recipe files written
#   - each is byte-equal to its canonical body extracted from the source
#   - the model that ran was Haiku (proves the pin is honored)
#
# Works in both Docker and host modes (sandbox.sh auto-detects).

set -euo pipefail

DRIVER_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$(cd "$DRIVER_DIR/../.." && pwd)"

# shellcheck source=../../lib/sandbox.sh
source "$HARNESS_ROOT/lib/sandbox.sh"
# shellcheck source=../../lib/assert.sh
source "$HARNESS_ROOT/lib/assert.sh"

parse_keep_flag "$@"
mk_sandbox
install_local_plugin

run_claude \
  --permission-mode bypassPermissions \
  --max-budget-usd 0.30 \
  -p --output-format json \
  "/cos-bot:install-recipes defaults"

capture_session_jsonl

# ---- assertions -----------------------------------------------------------

assert_jq_eq "$REPORT_DIR/run.json" '.is_error' 'false'
assert_jq_eq "$REPORT_DIR/run.json" '.permission_denials | length' '0'

for slug in prep inbox-triage awaiting who catchup; do
  assert_file_exists "$PROJECT_DIR/.claude/commands/$slug.md"
done

# byte-equal vs canonical body
assert_canonical_body "$PROJECT_DIR/.claude/commands/prep.md" \
  "$REPO_ROOT/plugins/cos-bot/recipes/meeting-prep.md"
assert_canonical_body "$PROJECT_DIR/.claude/commands/inbox-triage.md" \
  "$REPO_ROOT/plugins/cos-bot/recipes/inbox-triage.md"
assert_canonical_body "$PROJECT_DIR/.claude/commands/awaiting.md" \
  "$REPO_ROOT/plugins/cos-bot/recipes/awaiting.md"
assert_canonical_body "$PROJECT_DIR/.claude/commands/who.md" \
  "$REPO_ROOT/plugins/cos-bot/recipes/who.md"
assert_canonical_body "$PROJECT_DIR/.claude/commands/catchup.md" \
  "$REPO_ROOT/plugins/cos-bot/recipes/catchup.md"

# model: should be Haiku — fail loudly if Sonnet/Opus crept in.
MODEL="$(jq -r '.modelUsage | keys | .[0]' "$REPORT_DIR/run.json")"
case "$MODEL" in
  claude-haiku-*)
    _assert_record PASS "ran on Haiku ($MODEL)"
    ;;
  *)
    _assert_record FAIL "expected Haiku, got $MODEL"
    ;;
esac

# Perf gates — soft, just for visibility. Tighten as we collect more data.
TURNS="$(jq -r '.num_turns' "$REPORT_DIR/run.json")"
DUR_MS="$(jq -r '.duration_ms' "$REPORT_DIR/run.json")"
COST="$(jq -r '.total_cost_usd' "$REPORT_DIR/run.json")"
echo
echo "[perf] turns=$TURNS dur=${DUR_MS}ms cost=\$$COST model=$MODEL"

# Run the perf parser too — useful for the comparison report later.
python3 "$HARNESS_ROOT/lib/perf.py" parse "$REPORT_DIR" || true

assert_summary
status=$?
teardown
exit $status
