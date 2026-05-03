#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: pull.sh <model-name>}"
cd "$PROJECT_ROOT"
echo "→ downloading $MODEL_ID to HF cache (~/.cache/huggingface/hub)…"
exec uv run huggingface-cli download "$MODEL_ID"
