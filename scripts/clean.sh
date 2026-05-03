#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: clean.sh <model-name>}"
if [[ ! -d "$HOME/.cache/huggingface/hub" ]]; then
  echo "(no HF cache yet; nothing to clean)"
  exit 0
fi
exec uv run hf cache rm "$MODEL_ID" -y
