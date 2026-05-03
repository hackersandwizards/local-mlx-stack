#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: bench.sh <model-name>}"

PROMPT="Write a 200-word technical summary of how Bloom filters work."
START=$(date +%s.%N)
if ! RESP=$(curl -sf "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL_ID\",\"max_tokens\":300,\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}"); then
  echo "✗ no server responding on 127.0.0.1:$PORT — run 'just serve' first" >&2
  exit 1
fi
END=$(date +%s.%N)

TOKENS=$(echo "$RESP" | jq -r '.usage.completion_tokens // empty')
if [[ -z "$TOKENS" ]]; then
  echo "✗ unexpected response (no usage.completion_tokens):" >&2
  echo "$RESP" | head -c 400 >&2
  exit 1
fi

ELAPSED=$(echo "$END - $START" | bc)
echo "→ $TOKENS tokens in ${ELAPSED}s = $(echo "scale=1; $TOKENS/$ELAPSED" | bc) tok/s"
