#!/usr/bin/env bash
set -euo pipefail
# End-to-end decode throughput. `mtplx tune` measures draft depth, not tok/s.
# shellcheck source=models.sh
source "$(dirname "$0")/models.sh"
load_model "${1:-qwen3.8-27b}"

URL="http://127.0.0.1:$PORT/v1/chat/completions"
PROMPT="Write a 200-word technical summary of how Bloom filters work."
payload() {
  jq -nc --arg m "$MODEL_ID" --arg p "$PROMPT" --argjson n "$1" \
    '{model:$m, max_tokens:$n, messages:[{role:"user", content:$p}]}'
}

# Warmup primes prefill JIT + Metal kernels + KV alloc.
if ! curl -sf --max-time 120 "$URL" -H 'Content-Type: application/json' -d "$(payload 1)" >/dev/null; then
  echo "✗ no server on 127.0.0.1:$PORT. Run 'just serve $MODEL_ID' first." >&2
  exit 1
fi

RESP=$(curl -sf -w '\n__TIME__%{time_total}' --max-time 600 "$URL" \
  -H 'Content-Type: application/json' -d "$(payload 300)")
ELAPSED=$(printf '%s\n' "$RESP" | awk -F'__TIME__' '/__TIME__/{print $2}')
BODY=$(printf '%s\n' "$RESP" | sed 's/__TIME__.*$//')

TOKENS=$(printf '%s' "$BODY" | jq -r '.usage.completion_tokens // empty')
if [[ -z "$TOKENS" ]]; then
  echo "✗ unexpected response (no usage tokens):" >&2
  printf '%s' "$BODY" | head -c 400 >&2
  exit 1
fi

awk -v t="$TOKENS" -v e="$ELAPSED" 'BEGIN {printf "→ %d tokens in %.2fs (%.1f tok/s)\n", t, e, t/e}'
