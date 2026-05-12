#!/usr/bin/env bash
# sandbox.sh — primitive for running a cos-bot skill in isolation.
#
# Two modes (auto-detected):
#   - In-container (canonical): $HOME is already the sandbox; we just
#     install the plugin once and capture artifacts to /repo/test-harness/reports.
#   - Host (fast-iteration only): mints /tmp/cos-bot-<runid>/ and uses a
#     pre-existing claude install. No HOME isolation — host Anthropic
#     keychain is used. Good for quick perf iteration; not a full E2E.
#
# Source from a driver:
#   source "$(dirname "$0")/../../lib/sandbox.sh"
#   mk_sandbox
#   install_local_plugin
#   run_claude -p --output-format json "/cos-bot:install-recipes defaults"
#   capture_session_jsonl
#   teardown    # honors KEEP_SANDBOX=1

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$LIB_DIR/.." && pwd)"
REPO_ROOT="$(cd "$HARNESS_ROOT/.." && pwd)"

# Detect: are we inside the harness container?
if [[ -f /.dockerenv && -d /repo/test-harness ]]; then
  IN_CONTAINER=1
else
  IN_CONTAINER=0
fi

# ---- env loader -------------------------------------------------------------

_load_env() {
  # In-container: env is already injected by docker/run.sh. Skip host .env.
  if [[ "$IN_CONTAINER" = "0" && -f "$HARNESS_ROOT/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$HARNESS_ROOT/.env"
    set +a
  fi
  # Container mode: OAuth token is required (sandbox HOME has no keychain).
  # Host mode: keychain is the active auth path; OAuth token is optional.
  if [[ "$IN_CONTAINER" = "1" && -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    echo "error: CLAUDE_CODE_OAUTH_TOKEN not set." >&2
    echo "       docker/run.sh injects it from $HARNESS_ROOT/.env." >&2
    echo "       Run 'claude setup-token' on the host and paste the value into .env." >&2
    return 1
  fi
  # Host mode default: empty token is fine, claude reads keychain.
  export CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-}"
}

# ---- sandbox lifecycle ------------------------------------------------------

mk_sandbox() {
  _load_env
  RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
  REPORT_DIR="$HARNESS_ROOT/reports/$RUN_ID"
  mkdir -p "$REPORT_DIR"

  if [[ "$IN_CONTAINER" = "1" ]]; then
    # Container mode: $HOME IS the sandbox. We're freshly spawned per
    # `docker run --rm`, so no need to provision per-run directories.
    SANDBOX="$HOME"
    # Project dir is a temp scratch space for skills that take pwd as input.
    PROJECT_DIR="$(mktemp -d -t cos-bot-project-XXXXXX)"
  else
    # Host mode: scratch /tmp directory. The skill's home overrides go
    # nowhere on macOS (keychain is read regardless), but we keep
    # PROJECT_DIR isolated so file writes don't pollute the repo.
    SANDBOX="$HARNESS_ROOT/sandboxes/$RUN_ID"
    PROJECT_DIR="$SANDBOX/project"
    mkdir -p "$PROJECT_DIR"
  fi

  export RUN_ID SANDBOX REPORT_DIR PROJECT_DIR
  echo "[sandbox] mode=$([ $IN_CONTAINER = 1 ] && echo container || echo host)"
  echo "[sandbox] RUN_ID=$RUN_ID"
  echo "[sandbox] PROJECT_DIR=$PROJECT_DIR"
  echo "[sandbox] REPORT_DIR=$REPORT_DIR"
}

# Pre-seed a Telegram bot token into the channel dir.
# Used by connect.sh and Tier 2 drivers.
seed_telegram_token() {
  local token="${1:-${TEST_BOT_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}}"
  if [[ -z "$token" ]]; then
    echo "error: seed_telegram_token needs a token (arg, TEST_BOT_TOKEN, or TELEGRAM_BOT_TOKEN)." >&2
    return 1
  fi
  local channel_dir
  if [[ "$IN_CONTAINER" = "1" ]]; then
    channel_dir="$HOME/.claude/channels/telegram"
  else
    channel_dir="$SANDBOX/.claude/channels/telegram"
  fi
  mkdir -p "$channel_dir"
  chmod 700 "$channel_dir"
  cat > "$channel_dir/.env" <<EOF
TELEGRAM_BOT_TOKEN=$token
EOF
  chmod 600 "$channel_dir/.env"
  echo "[sandbox] seeded $channel_dir/.env"
}

# Pre-seed access.json with a paired sender (for Tier 2 demo round-trip
# tests where pairing is a prerequisite, not the thing under test).
seed_paired_access() {
  local sender_id="${1:-${TEST_SENDER_ID:-}}"
  local chat_id="${2:-${TEST_CHAT_ID:-}}"
  if [[ -z "$sender_id" || -z "$chat_id" ]]; then
    echo "error: seed_paired_access needs sender_id + chat_id." >&2
    return 1
  fi
  local channel_dir
  if [[ "$IN_CONTAINER" = "1" ]]; then
    channel_dir="$HOME/.claude/channels/telegram"
  else
    channel_dir="$SANDBOX/.claude/channels/telegram"
  fi
  mkdir -p "$channel_dir"
  cat > "$channel_dir/access.json" <<EOF
{
  "version": 1,
  "allowFrom": ["$sender_id"],
  "chatIds": {"$sender_id": "$chat_id"},
  "policy": "dm-only"
}
EOF
  chmod 600 "$channel_dir/access.json"
  echo "[sandbox] seeded $channel_dir/access.json (sender=$sender_id chat=$chat_id)"
}

# Install cos-bot plugin so /cos-bot:* skills resolve. Two paths:
#   - In-container: write enabledPlugins config + symlink to /repo's plugin dir
#   - Host: pass --plugin-dir at invocation time (handled in run_claude)
install_local_plugin() {
  if [[ "$IN_CONTAINER" = "0" ]]; then
    # Host mode uses --plugin-dir; nothing to install.
    return 0
  fi
  local marker="$HOME/.claude/.cos-bot-installed"
  [[ -f "$marker" ]] && return 0

  echo "[sandbox] installing cos-bot plugin from /repo"
  # cos-bot/* skills resolve via --plugin-dir at runtime (passed by run_claude).

  # Pre-write ~/.claude.json + ~/.claude/settings.json to skip every
  # first-run wizard that would otherwise block headless runs in tmux:
  #   - theme picker
  #   - workspace-trust dialog (per-project flag in ~/.claude.json)
  #   - bypass-permissions warning (skipDangerousModePermissionPrompt)
  #   - auto-permissions prompt (skipAutoPermissionPrompt)
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "skipDangerousModePermissionPrompt": true,
  "skipAutoPermissionPrompt": true
}
EOF
  cat > "$HOME/.claude.json" <<EOF
{
  "hasCompletedOnboarding": true,
  "lastOnboardingVersion": "1.0.11",
  "firstStartTime": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
  "projects": {
    "$PROJECT_DIR": {
      "hasTrustDialogAccepted": true,
      "hasCompletedProjectOnboarding": true,
      "allowedTools": [],
      "mcpServers": {},
      "enabledMcpjsonServers": [],
      "disabledMcpjsonServers": []
    }
  }
}
EOF
  # The mkdir-before-this is now duplicated; that's fine, mkdir -p is idempotent.
  mkdir -p "$HOME/.claude"

  # If TELEGRAM_PLUGIN_DIR is mounted (Tier 2), also install the telegram
  # plugin into the standard cache layout so `--channels plugin:telegram@claude-plugins-official`
  # resolves. The cache layout matches what `/plugin install` writes.
  if [[ -n "${TELEGRAM_PLUGIN_DIR:-}" && -d "$TELEGRAM_PLUGIN_DIR" ]]; then
    local cache_dir="$HOME/.claude/plugins/cache/claude-plugins-official/telegram/0.0.6"
    mkdir -p "$(dirname "$cache_dir")"
    ln -sfn "$TELEGRAM_PLUGIN_DIR" "$cache_dir"
    mkdir -p "$HOME/.claude/plugins"
    cat > "$HOME/.claude/plugins/marketplaces.json" <<'EOF'
{
  "marketplaces": {
    "claude-plugins-official": {
      "source": {"source": "github", "repo": "anthropics/claude-plugins"}
    }
  }
}
EOF
    cat > "$HOME/.claude/plugins/config.json" <<'EOF'
{
  "enabledPlugins": {
    "telegram@claude-plugins-official": true
  }
}
EOF
    echo "[sandbox] linked telegram plugin into $cache_dir"
  fi

  touch "$marker"
}

# Run claude headless with the right env.
# Caller passes argv verbatim:
#   run_claude -p --output-format json "/cos-bot:install-recipes defaults"
run_claude() {
  local out="$REPORT_DIR/run.json"
  local err="$REPORT_DIR/run.stderr"
  # --plugin-dir is the simplest way to expose the cos-bot skills:
  # works identically in container and host modes; no marketplace
  # config gymnastics required.
  local plugin_path
  if [[ "$IN_CONTAINER" = "1" ]]; then
    plugin_path="/repo/plugins/cos-bot"
  else
    plugin_path="$REPO_ROOT/plugins/cos-bot"
  fi
  local args=(--plugin-dir "$plugin_path")
  args+=("$@")
  (
    cd "$PROJECT_DIR"
    if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
      CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN" \
        claude "${args[@]}" > "$out" 2> "$err"
    else
      # Host mode without an OAuth token — fall through to keychain auth.
      claude "${args[@]}" > "$out" 2> "$err"
    fi
  )
  echo "[sandbox] wrote $out"
}

# Locate the per-session JSONL claude wrote and copy it to the report.
capture_session_jsonl() {
  local sid
  sid="$(jq -r '.session_id // empty' "$REPORT_DIR/run.json" 2>/dev/null || true)"
  if [[ -z "$sid" ]]; then
    echo "[sandbox] no session_id in run.json; skipping"
    return 0
  fi
  local proj_dir="$HOME/.claude/projects"
  local jsonl
  jsonl="$(find "$proj_dir" -name "${sid}.jsonl" -type f 2>/dev/null | head -1)"
  if [[ -z "$jsonl" ]]; then
    echo "[sandbox] no jsonl for session $sid"
    return 0
  fi
  cp "$jsonl" "$REPORT_DIR/session.jsonl"
  echo "[sandbox] captured $jsonl → $REPORT_DIR/session.jsonl"
}

teardown() {
  if [[ "${KEEP_SANDBOX:-0}" = "1" ]]; then
    echo "[sandbox] --keep set; leaving artifacts in place"
    return 0
  fi
  if [[ "$IN_CONTAINER" = "0" && -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
    echo "[sandbox] removed $SANDBOX"
  fi
  # Container is auto-cleaned by `docker run --rm`.
}

parse_keep_flag() {
  for arg in "$@"; do
    [[ "$arg" = "--keep" ]] && export KEEP_SANDBOX=1
  done
}
