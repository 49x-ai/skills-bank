#!/usr/bin/env bash
# assert.sh — tiny assertion helpers used by drivers.
# Source after sandbox.sh.

set -euo pipefail

ASSERT_PASSES=0
ASSERT_FAILS=0
ASSERT_LOG=""

_assert_record() {
  local status="$1" msg="$2"
  if [[ "$status" = "PASS" ]]; then
    ASSERT_PASSES=$((ASSERT_PASSES + 1))
  else
    ASSERT_FAILS=$((ASSERT_FAILS + 1))
  fi
  ASSERT_LOG+="[$status] $msg"$'\n'
  echo "[$status] $msg"
}

assert_file_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    _assert_record PASS "file exists: $path"
  else
    _assert_record FAIL "file missing: $path"
  fi
}

assert_file_byte_equal() {
  local actual="$1" expected="$2"
  if [[ ! -f "$actual" ]]; then
    _assert_record FAIL "byte-equal: $actual missing"
    return
  fi
  if [[ ! -f "$expected" ]]; then
    _assert_record FAIL "byte-equal: expected $expected missing"
    return
  fi
  if cmp -s "$actual" "$expected"; then
    _assert_record PASS "byte-equal: $actual ↔ $expected"
  else
    _assert_record FAIL "byte-equal mismatch: $actual ↔ $expected"
  fi
}

assert_file_contains() {
  local path="$1" needle="$2"
  if [[ ! -f "$path" ]]; then
    _assert_record FAIL "contains: $path missing"
    return
  fi
  if grep -qF -- "$needle" "$path"; then
    _assert_record PASS "contains '$needle': $path"
  else
    _assert_record FAIL "missing substring '$needle': $path"
  fi
}

assert_jq_eq() {
  local path="$1" expr="$2" expected="$3"
  if [[ ! -f "$path" ]]; then
    _assert_record FAIL "jq: $path missing"
    return
  fi
  local actual
  actual="$(jq -r "$expr" "$path" 2>/dev/null || echo "<jq-error>")"
  if [[ "$actual" = "$expected" ]]; then
    _assert_record PASS "jq '$expr' == '$expected' in $path"
  else
    _assert_record FAIL "jq '$expr' = '$actual' (expected '$expected') in $path"
  fi
}

assert_stdout_contains() {
  local out_path="$1" needle="$2"
  if [[ ! -f "$out_path" ]]; then
    _assert_record FAIL "stdout contains: $out_path missing"
    return
  fi
  # run.json is JSON; the visible reply is in .result.
  local body
  if [[ "$out_path" == *.json ]] && jq -e .result "$out_path" >/dev/null 2>&1; then
    body="$(jq -r .result "$out_path")"
  else
    body="$(cat "$out_path")"
  fi
  if echo "$body" | grep -qF -- "$needle"; then
    _assert_record PASS "result contains '$needle'"
  else
    _assert_record FAIL "result missing '$needle' (in $out_path)"
  fi
}

# Compare a written recipe file against its canonical body extracted from
# the source recipe markdown. The source has the body in a fenced
# ```markdown ... ``` block under "## Slash-command body".
assert_canonical_body() {
  local written="$1" source_md="$2"
  if [[ ! -f "$written" ]]; then
    _assert_record FAIL "canonical: $written missing"
    return
  fi
  if [[ ! -f "$source_md" ]]; then
    _assert_record FAIL "canonical: source $source_md missing"
    return
  fi
  local extracted
  extracted="$(awk '
    /^## Slash-command body/ { in_section=1; next }
    in_section && /^```markdown/ { in_block=1; next }
    in_block && /^```/ { exit }
    in_block { print }
  ' "$source_md")"
  if [[ -z "$extracted" ]]; then
    _assert_record FAIL "canonical: no fenced markdown block under 'Slash-command body' in $source_md"
    return
  fi
  if [[ "$extracted" = "$(cat "$written")" ]]; then
    _assert_record PASS "canonical body matches: $written"
  else
    _assert_record FAIL "canonical body diverges: $written vs $source_md"
    diff <(echo "$extracted") "$written" \
      | head -40 >> "$REPORT_DIR/diff.canonical.$(basename "$written").log" 2>/dev/null || true
  fi
}

assert_summary() {
  local total=$((ASSERT_PASSES + ASSERT_FAILS))
  echo
  echo "------------------------------------------------------------"
  echo "assertions: $ASSERT_PASSES/$total passed ($ASSERT_FAILS failed)"
  echo "------------------------------------------------------------"
  if [[ -n "${REPORT_DIR:-}" ]]; then
    {
      echo "passes=$ASSERT_PASSES"
      echo "fails=$ASSERT_FAILS"
      echo
      echo "$ASSERT_LOG"
    } > "$REPORT_DIR/assertions.log"
  fi
  if [[ "$ASSERT_FAILS" -gt 0 ]]; then
    return 1
  fi
}
