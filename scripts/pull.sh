#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: pull.sh <model-name>}"
echo "→ downloading $MODEL_ID to HF cache (~/.cache/huggingface/hub)…"
exec uv run hf download "$MODEL_ID"
