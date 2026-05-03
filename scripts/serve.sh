#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: serve.sh <model-name>}"
cd "$PROJECT_ROOT"

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "✗ port $PORT already in use. Run 'just stop' or pick another port." >&2
  exit 1
fi

(
  for _ in {1..30}; do
    sleep 1
    curl -s "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1 && break
  done
  curl -s "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL_ID\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" >/dev/null 2>&1 \
    && echo "✓ model warm" >&2
) &
WARMUP_PID=$!
trap 'kill "$WARMUP_PID" 2>/dev/null || true' EXIT

echo "→ serving $MODEL_ID on http://127.0.0.1:$PORT"
exec uv run mlx_vlm.server --model "$MODEL_ID" --host 127.0.0.1 --port "$PORT"
