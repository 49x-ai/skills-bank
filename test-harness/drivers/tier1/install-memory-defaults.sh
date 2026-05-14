#!/usr/bin/env bash
# Tier 1 / install-memory standard fast-install
#
# Runs `/cos-bot:install-memory standard` headless and asserts:
#   - exit success, no permission denials
#   - the Standard preset's files land under <project>/memory/
#   - MEMORY.md's folder guide is pruned to the installed folders
#     (lists projects/ + inbox/, NOT people/ / companies/ / prompts/)
#   - Full-only folders (people/, companies/) are absent
#   - PROTOCOL.md written + ./CLAUDE.md has the cos-bot:memory block
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

# Local helper — assert a path does NOT exist.
assert_path_absent() {
  local path="$1"
  if [[ -e "$path" ]]; then
    _assert_record FAIL "should not exist: $path"
  else
    _assert_record PASS "absent as expected: $path"
  fi
}

parse_keep_flag "$@"
mk_sandbox
install_local_plugin

run_claude \
  --permission-mode bypassPermissions \
  --max-budget-usd 0.30 \
  -p --output-format json \
  "/cos-bot:install-memory standard"

capture_session_jsonl

# ---- assertions -----------------------------------------------------------

assert_jq_eq "$REPORT_DIR/run.json" '.is_error' 'false'
assert_jq_eq "$REPORT_DIR/run.json" '.permission_denials | length' '0'

# Standard preset: core files + projects/ + inbox/ + protocol
assert_file_exists "$PROJECT_DIR/memory/MEMORY.md"
assert_file_exists "$PROJECT_DIR/memory/active.md"
assert_file_exists "$PROJECT_DIR/memory/decisions.md"
assert_file_exists "$PROJECT_DIR/memory/workflows.md"
assert_file_exists "$PROJECT_DIR/memory/projects/example-project.md"
assert_file_exists "$PROJECT_DIR/PROTOCOL.md"

# inbox/ ships in every preset — monthly seed file for the current month
MONTH="$(date +%Y-%m)"
assert_file_exists "$PROJECT_DIR/memory/inbox/$MONTH.md"

# Full-only folders must NOT be present in Standard
assert_path_absent "$PROJECT_DIR/memory/people"
assert_path_absent "$PROJECT_DIR/memory/companies"
assert_path_absent "$PROJECT_DIR/memory/prompts"
assert_path_absent "$PROJECT_DIR/memory/archive"

# MEMORY.md folder guide pruned to installed folders
assert_file_contains "$PROJECT_DIR/memory/MEMORY.md" '`projects/`'
if grep -qF '`people/`' "$PROJECT_DIR/memory/MEMORY.md"; then
  _assert_record FAIL "MEMORY.md folder guide still lists people/ (not pruned)"
else
  _assert_record PASS "MEMORY.md folder guide pruned (no people/)"
fi
# marker comments stripped after assembly
if grep -qF 'cos-bot:folder-guide' "$PROJECT_DIR/memory/MEMORY.md"; then
  _assert_record FAIL "MEMORY.md still has folder-guide marker comments"
else
  _assert_record PASS "MEMORY.md folder-guide markers stripped"
fi

# ./CLAUDE.md got the managed block
assert_file_exists "$PROJECT_DIR/CLAUDE.md"
assert_file_contains "$PROJECT_DIR/CLAUDE.md" '<!-- cos-bot:memory -->'

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

# Perf gates — soft, just for visibility.
TURNS="$(jq -r '.num_turns' "$REPORT_DIR/run.json")"
DUR_MS="$(jq -r '.duration_ms' "$REPORT_DIR/run.json")"
COST="$(jq -r '.total_cost_usd' "$REPORT_DIR/run.json")"
echo
echo "[perf] turns=$TURNS dur=${DUR_MS}ms cost=\$$COST model=$MODEL"

python3 "$HARNESS_ROOT/lib/perf.py" parse "$REPORT_DIR" || true

assert_summary
status=$?
teardown
exit $status
