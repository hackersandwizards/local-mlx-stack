#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: serve.sh <model-name>}"

PORT=8080
WARMUP_TIMEOUT_S=90  # 4-bit (~21 GB) cold-load completes in ~30 s on M3 Max; 90 s is generous headroom

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "✗ port $PORT already in use. Run 'just stop' or pick another port." >&2
  exit 1
fi

(
  for _ in $(seq 1 "$WARMUP_TIMEOUT_S"); do
    sleep 1
    curl -fs "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1 || continue
    curl -fs "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
      -d "{\"model\":\"$MODEL_ID\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}" \
      >/dev/null 2>&1 \
      && echo "✓ model warm" >&2
    exit 0
  done
) &
disown

echo "→ serving $MODEL_ID on http://127.0.0.1:$PORT"
exec uv run mlx_vlm.server --model "$MODEL_ID" --host 127.0.0.1 --port "$PORT"
