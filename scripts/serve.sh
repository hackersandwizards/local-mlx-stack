#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=models.sh
source "$(dirname "$0")/models.sh"
load_model "${1:-qwen3.6-27b}"

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "✗ port $PORT already in use. Run 'just stop'." >&2
  exit 1
fi

if [[ ! -e "$MODEL_PATH" ]]; then
  echo "✗ '$MODEL_ID' not at $MODEL_PATH. Run 'just pull $MODEL_ID' first." >&2
  exit 1
fi

echo "→ serving $MODEL_ID on http://127.0.0.1:$PORT (profile $PROFILE)"
exec mtplx quickstart \
  --model "$MODEL_PATH" \
  --model-id "$MODEL_ID" \
  --host 127.0.0.1 \
  --port "$PORT" \
  --profile "$PROFILE" \
  --default-temperature "$TEMPERATURE" \
  --default-top-p "$TOP_P" \
  --default-top-k "$TOP_K" \
  --reasoning auto \
  --reasoning-parser qwen3 \
  --no-stats-footer \
  --yes
