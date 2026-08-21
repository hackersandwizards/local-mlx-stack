#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=models.sh
source "$(dirname "$0")/models.sh"
load_model "${1:-qwen3.8-27b}"

# Serving is exclusive: one port, one model. Replace whoever holds it rather
# than making the caller stop it first. Wait for the port to actually clear --
# starting into a still-bound port fails with a less obvious error.
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "→ :$PORT busy, replacing"
  mtplx stop --port "$PORT" >/dev/null 2>&1 || true
  for _ in $(seq 30); do
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 || break
    sleep 1
  done
  if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "✗ :$PORT held by something MTPLX cannot stop:" >&2
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2
    exit 1
  fi
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
  --reasoning-effort "$REASONING_EFFORT" \
  --reasoning-parser qwen3 \
  --ssd-session-cache-max-size 20GB \
  --no-stats-footer \
  --yes
