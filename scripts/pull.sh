#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=models.sh
source "$(dirname "$0")/models.sh"
load_model "${1:?usage: pull.sh <model>}"

# mtplx pull downloads into MODELS_DIR as Org--Repo and exits non-zero when the
# weight shards are missing or partial, so a placeholder repo fails here.
mtplx pull "$HF_REPO"

ln -sfn "$MODELS_DIR/${HF_REPO//\//--}" "$MODEL_PATH"
echo "✓ $MODEL_ID → ${HF_REPO//\//--}"
