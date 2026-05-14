#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: pull.sh <model-name>}"
: "${HF_REPO:?HF_REPO not set in model .env}"

echo "→ downloading $HF_REPO to HF cache (~/.cache/huggingface/hub)…"
uv run hf download "$HF_REPO"

SAFE_NAME="${HF_REPO//\//--}"
SNAPSHOT=$(find "$HOME/.cache/huggingface/hub/models--${SAFE_NAME}/snapshots" -mindepth 1 -maxdepth 1 -type d | head -1)
if [[ -z "$SNAPSHOT" ]]; then
  echo "✗ no snapshot found for $HF_REPO after download" >&2
  exit 1
fi

LINK_DIR="$(backend_link_dir "$BACKEND")"
mkdir -p "$LINK_DIR"
ln -sfn "$SNAPSHOT" "$LINK_DIR/$MODEL_ID"
echo "✓ $MODEL_ID [$BACKEND] linked → $SNAPSHOT"
