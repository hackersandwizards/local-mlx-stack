#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: bench.sh <model-name>}"

URL=$(chat_url)
PROMPT="Write a 200-word technical summary of how Bloom filters work."
PAYLOAD=$(chat_payload "$PROMPT" 300)
WARMUP_PAYLOAD=$(chat_payload "$PROMPT" 1)

# Warmup primes prefill JIT + Metal kernels + KV alloc.
if ! curl -sf "$URL" -H 'Content-Type: application/json' -d "$WARMUP_PAYLOAD" >/dev/null; then
  echo "✗ no server responding on 127.0.0.1:$PORT. Run 'just serve' first." >&2
  exit 1
fi

RESP=$(curl -sf -w '\n__TIME__%{time_total}' "$URL" -H 'Content-Type: application/json' -d "$PAYLOAD")
ELAPSED=$(printf '%s\n' "$RESP" | awk -F'__TIME__' '/__TIME__/{print $2}')
BODY=$(printf '%s\n' "$RESP" | sed 's/__TIME__.*$//')

TOKENS=$(printf '%s' "$BODY" | jq -r '.usage.output_tokens // .usage.completion_tokens // empty')
if [[ -z "$TOKENS" || "$TOKENS" == "null" ]]; then
  echo "✗ unexpected response (no usage tokens):" >&2
  printf '%s' "$BODY" | head -c 400 >&2
  exit 1
fi

awk -v t="$TOKENS" -v e="$ELAPSED" 'BEGIN {printf "→ %d tokens in %.2fs (%.1f tok/s)\n", t, e, t/e}'
