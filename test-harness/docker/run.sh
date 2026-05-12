#!/usr/bin/env bash
# docker/run.sh — invoke a harness driver inside the container.
#
# Usage:
#   docker/run.sh drivers/tier1/install-recipes-defaults.sh
#   docker/run.sh drivers/tier2/connect-pair.sh
#   docker/run.sh --shell                    # interactive shell for debugging
#   docker/run.sh --build                    # rebuild image (also auto-built if missing)
#
# Reads .env from test-harness/.env. Required:
#   CLAUDE_CODE_OAUTH_TOKEN
# Optional (Tier 2 only):
#   TEST_BOT_TOKEN, TEST_CHAT_ID, TEST_SENDER_ID

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$HARNESS_ROOT/.." && pwd)"
IMAGE_TAG="cos-bot-harness:latest"

# ---- env -------------------------------------------------------------------

build_image() {
  echo "[run.sh] building $IMAGE_TAG"
  docker build -t "$IMAGE_TAG" -f "$HARNESS_ROOT/docker/Dockerfile" "$HARNESS_ROOT/docker"
}

# --build needs no env; bail out before the auth check.
if [[ "${1:-}" = "--build" ]]; then
  build_image
  exit 0
fi

if [[ -f "$HARNESS_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$HARNESS_ROOT/.env"
  set +a
fi

if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
  echo "error: CLAUDE_CODE_OAUTH_TOKEN not set." >&2
  echo "       Run 'claude setup-token' on the host and paste the result" >&2
  echo "       into $HARNESS_ROOT/.env (see .env.example)." >&2
  exit 1
fi

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  build_image
fi

# ---- run -------------------------------------------------------------------

# Reports dir lives on the host so artifacts survive container removal.
mkdir -p "$HARNESS_ROOT/reports"

DOCKER_ARGS=(
  --rm
  --init
  -v "$REPO_ROOT:/repo:ro"
  -v "$HARNESS_ROOT/reports:/repo/test-harness/reports"
  -e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN"
  -e "TEST_BOT_TOKEN=${TEST_BOT_TOKEN:-}"
  -e "TEST_CHAT_ID=${TEST_CHAT_ID:-}"
  -e "TEST_SENDER_ID=${TEST_SENDER_ID:-}"
  -e "RUN_ID=${RUN_ID:-}"
  -e "KEEP_SANDBOX=${KEEP_SANDBOX:-0}"
  -w /repo
)

# Tier 2 needs the official telegram plugin (provides the MCP channel
# server). Bind-mount the host's cached copy if present so we don't
# have to re-fetch it in the container. Optional — Tier 1 doesn't need it.
TELEGRAM_PLUGIN_HOST_DIR="$(echo "$HOME/.claude/plugins/cache/claude-plugins-official/telegram"/*/ 2>/dev/null | head -1 | tr -d '\n')"
if [[ -n "$TELEGRAM_PLUGIN_HOST_DIR" && -d "$TELEGRAM_PLUGIN_HOST_DIR" ]]; then
  # Mount outside /repo (which is read-only and can't host new sub-mount points).
  DOCKER_ARGS+=(-v "$TELEGRAM_PLUGIN_HOST_DIR:/opt/telegram-plugin:ro")
  DOCKER_ARGS+=(-e "TELEGRAM_PLUGIN_DIR=/opt/telegram-plugin")
fi

if [[ "${1:-}" = "--shell" ]]; then
  exec docker run -it "${DOCKER_ARGS[@]}" "$IMAGE_TAG" /bin/bash
fi

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <driver-path-relative-to-test-harness> [args...]" >&2
  echo "       $0 --shell" >&2
  echo "       $0 --build" >&2
  exit 2
fi

DRIVER="$1"
shift

# Drivers expect paths relative to $HARNESS_ROOT (e.g. drivers/tier1/foo.sh).
exec docker run "${DOCKER_ARGS[@]}" "$IMAGE_TAG" \
  bash -c "cd /repo/test-harness && exec ./$DRIVER $*"
