#!/usr/bin/env bash
set -euo pipefail
# Invoked by serve.sh after load_model. Expects MODEL_ID, MODEL_PATH, PORT in env.
: "${MODEL_ID:?MODEL_ID not set}"
: "${MODEL_PATH:?MODEL_PATH not set}"
: "${PORT:?PORT not set}"

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
  --reasoning auto \
  --reasoning-parser qwen3 \
  --no-stats-footer \
  --yes
