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

now() { python3 -c 'import time; print(time.time())'; }

# Discard first iteration (prefill JIT, Metal shader compile, KV alloc all happen here).
if ! curl -sf "$URL" -H 'Content-Type: application/json' -d "$PAYLOAD" >/dev/null; then
  echo "✗ no server responding on 127.0.0.1:$PORT — run 'just serve' first" >&2
  exit 1
fi

START=$(now)
RESP=$(curl -sf "$URL" -H 'Content-Type: application/json' -d "$PAYLOAD")
END=$(now)

TOKENS=$(echo "$RESP" | jq -r '.usage.completion_tokens // empty')
if [[ -z "$TOKENS" ]]; then
  echo "✗ unexpected response (no usage.completion_tokens):" >&2
  echo "$RESP" | head -c 400 >&2
  exit 1
fi

python3 -c "
t, s, e = $TOKENS, $START, $END
elapsed = e - s
print(f'→ {t} tokens in {elapsed:.2f}s = {t/elapsed:.1f} tok/s')
"
