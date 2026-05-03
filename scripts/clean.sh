#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: clean.sh <model-name>}"
cd "$PROJECT_ROOT"
echo "→ removing $MODEL_ID from HF cache…"

if uv run huggingface-cli delete-cache --disable-tui \
     --repo "$MODEL_ID" --repo-type model -y 2>/dev/null; then
  echo "✓ removed via huggingface-cli"
else
  CACHE_DIR="$HOME/.cache/huggingface/hub/models--$(echo "$MODEL_ID" | tr '/' '-')"
  if [[ -d "$CACHE_DIR" ]]; then
    rm -rf "$CACHE_DIR"
    echo "✓ removed $CACHE_DIR"
  else
    echo "(model not in cache; nothing to clean)"
  fi
fi
