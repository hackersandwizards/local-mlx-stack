#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: clean.sh <model-name>}"
exec uv run hf cache rm "model/$MODEL_ID" -y
