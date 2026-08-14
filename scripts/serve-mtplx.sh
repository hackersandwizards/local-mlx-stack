#!/usr/bin/env bash
set -euo pipefail
# Invoked by serve.sh after load_model. Expects MODEL_ID, MODEL_PATH, PORT and the
# sampling preset in env. Sampling is per-model (Qwen publishes different presets per
# release), so the .env owns it and a missing value fails here instead of silently
# serving at the model's own generation_config default.
: "${MODEL_ID:?MODEL_ID not set}"
: "${MODEL_PATH:?MODEL_PATH not set}"
: "${PORT:?PORT not set}"
: "${TEMPERATURE:?TEMPERATURE not set in model .env}"
: "${TOP_P:?TOP_P not set in model .env}"
: "${TOP_K:?TOP_K not set in model .env}"

if ! command -v mtplx >/dev/null; then
  echo "✗ mtplx missing. Install: brew install youssofal/mtplx/mtplx" >&2
  exit 1
fi

echo "→ serving $MODEL_ID via MTPLX on http://127.0.0.1:$PORT"
exec mtplx quickstart \
  --model "$MODEL_PATH" \
  --host 127.0.0.1 \
  --port "$PORT" \
  --model-id "$MODEL_ID" \
  --profile performance-cold \
  --default-temperature "$TEMPERATURE" \
  --default-top-p "$TOP_P" \
  --default-top-k "$TOP_K" \
  --reasoning auto \
  --reasoning-parser qwen3 \
  --no-stats-footer \
  --yes
