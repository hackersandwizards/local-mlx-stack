#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
# Invoked by serve.sh after load_model. Expects MODEL_ID, PORT, MAX_MODEL_MEMORY in env.
: "${MODEL_ID:?MODEL_ID not set}"
: "${PORT:?PORT not set}"

WARMUP_TIMEOUT_S=120  # oMLX cold-load + prefix-cache setup; 6-bit ~29 GB takes ~60–90 s on M3 Max

WARMUP_PAYLOAD=$(chat_payload "hi")
CHAT_URL=$(chat_url)

(
  for _ in $(seq 1 "$WARMUP_TIMEOUT_S"); do
    sleep 1
    kill -0 "$$" 2>/dev/null || exit 0
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
  --model-dir "$OMLX_MODELS_DIR" \
  --host 127.0.0.1 \
  --port "$PORT" \
  --max-model-memory "${MAX_MODEL_MEMORY:-35GB}" \
  --paged-ssd-cache-dir "$HOME/.omlx/cache" \
  --paged-ssd-cache-max-size 50GB \
  --hot-cache-max-size 8GB \
  --log-level info
