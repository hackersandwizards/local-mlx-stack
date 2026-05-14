#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: clean.sh <model-name>}"
: "${HF_REPO:?HF_REPO not set in model .env}"
rm -f "$(backend_link_dir "$BACKEND")/$MODEL_ID"
exec uv run hf cache rm "model/$HF_REPO" -y
