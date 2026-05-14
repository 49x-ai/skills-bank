#!/usr/bin/env bash
# Search the Markdown memory layer. Resolves the project root from this
# script's own location, so it works whether invoked as
# ./scripts/memory-search.sh or from anywhere else.
set -euo pipefail

QUERY="${*:-}"

if [ -z "$QUERY" ]; then
  echo "Usage: ./scripts/memory-search.sh <query>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -d "$PROJECT_ROOT/memory" ]; then
  echo "No memory/ directory found at $PROJECT_ROOT" >&2
  exit 1
fi

rg -n --hidden \
  --glob 'memory/**/*.md' \
  --glob '!memory/archive/**' \
  "$QUERY" "$PROJECT_ROOT"
