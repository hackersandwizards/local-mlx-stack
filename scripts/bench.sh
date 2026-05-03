#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: bench.sh <model-name>}"
PROMPT="Write a 200-word technical summary of how Bloom filters work."
START=$(date +%s.%N)
RESP=$(curl -s "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL_ID\",\"max_tokens\":300,\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}")
END=$(date +%s.%N)
TOKENS=$(echo "$RESP" | jq -r '.usage.completion_tokens')
ELAPSED=$(echo "$END - $START" | bc)
echo "→ $TOKENS tokens in ${ELAPSED}s = $(echo "scale=1; $TOKENS/$ELAPSED" | bc) tok/s"
