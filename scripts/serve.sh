#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: serve.sh <model-name>}"

WARMUP_TIMEOUT_S=90  # 4-bit (~21 GB) cold-load completes in ~30 s on M3 Max; 90 s is generous headroom

if port_in_use "$PORT"; then
  echo "✗ port $PORT already in use. Run 'just stop' or pick another port." >&2
  exit 1
fi

WARMUP_PAYLOAD=$(chat_payload "hi")
CHAT_URL=$(chat_url)

(
  for _ in $(seq 1 "$WARMUP_TIMEOUT_S"); do
    sleep 1
    kill -0 "$$" 2>/dev/null || exit 0  # parent (server) gone, stop probing
    curl -fs --connect-timeout 1 --max-time 2 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1 || continue
    curl -fs --connect-timeout 1 --max-time 60 "$CHAT_URL" \
      -H 'Content-Type: application/json' -d "$WARMUP_PAYLOAD" >/dev/null 2>&1 \
      && echo "✓ model warm" >&2
    exit 0
  done
  echo "⚠ warmup didn't complete in ${WARMUP_TIMEOUT_S}s. First request may be slow." >&2
) &

echo "→ serving $MODEL_ID on http://127.0.0.1:$PORT"
exec uv run mlx_vlm.server --model "$MODEL_ID" --host 127.0.0.1 --port "$PORT"
