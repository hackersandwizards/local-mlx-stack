#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: bench.sh <model-name>}"

PORT=8080
URL="http://127.0.0.1:$PORT/v1/chat/completions"
PROMPT="Write a 200-word technical summary of how Bloom filters work."
PAYLOAD=$(jq -nc --arg model "$MODEL_ID" --arg p "$PROMPT" \
  '{model:$model, max_tokens:300, messages:[{role:"user", content:$p}]}')

# Two warmup iterations: prefill JIT, Metal shader compile, KV alloc happen on iter 1;
# steady-state throughput stabilizes by iter 2 (verified empirically on M3 Max).
for _ in 1 2; do
  if ! curl -sf "$URL" -H 'Content-Type: application/json' -d "$PAYLOAD" >/dev/null; then
    echo "✗ no server responding on 127.0.0.1:$PORT — run 'just serve' first" >&2
    exit 1
  fi
done

RESP=$(curl -sf "$URL" -H 'Content-Type: application/json' -d "$PAYLOAD")

read -r TOKENS TPS < <(echo "$RESP" | jq -r '"\(.usage.output_tokens) \(.usage.generation_tps)"')
if [[ -z "$TOKENS" || "$TOKENS" == "null" ]]; then
  echo "✗ unexpected response (no usage.output_tokens):" >&2
  echo "$RESP" | head -c 400 >&2
  exit 1
fi

printf '→ %s tokens at %.1f tok/s\n' "$TOKENS" "$TPS"
