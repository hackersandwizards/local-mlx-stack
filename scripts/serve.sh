#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: serve.sh <model-name>}"

WARMUP_TIMEOUT_S=120  # oMLX cold-load + prefix-cache setup; 6-bit ~29 GB takes ~60–90 s on M3 Max

if port_in_use "$PORT"; then
  echo "✗ port $PORT already in use. Run 'just stop' or pick another port." >&2
  exit 1
fi

if [[ ! -e "$HOME/.omlx/models/$MODEL_ID" ]]; then
  echo "✗ model '$MODEL_ID' not in ~/.omlx/models. Run 'just pull ${1}' first." >&2
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

echo "→ serving $MODEL_ID via oMLX on http://127.0.0.1:$PORT"
exec omlx serve \
  --model-dir "$HOME/.omlx/models" \
  --host 127.0.0.1 \
  --port "$PORT" \
  --max-model-memory "${MAX_MODEL_MEMORY:-35GB}" \
  --paged-ssd-cache-dir "$HOME/.omlx/cache" \
  --paged-ssd-cache-max-size 50GB \
  --hot-cache-max-size 8GB \
  --log-level info
