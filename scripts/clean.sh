#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: clean.sh <model-name>}"

CACHE_DIR="$HOME/.cache/huggingface/hub/models--$(echo "$MODEL_ID" | tr '/' '-')"
if [[ -d "$CACHE_DIR" ]]; then
  rm -rf "$CACHE_DIR"
  echo "✓ removed $CACHE_DIR"
else
  echo "(model not in cache; nothing to clean)"
fi
