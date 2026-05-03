#!/usr/bin/env bash
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPTS_DIR/../config/models"
PORT="${PORT:-8080}"

port_in_use() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

chat_url() {
  echo "http://127.0.0.1:$PORT/v1/chat/completions"
}

chat_payload() {
  local prompt="$1" tokens="${2:-1}"
  jq -nc --arg model "$MODEL_ID" --arg p "$prompt" --argjson n "$tokens" \
    '{model:$model, max_tokens:$n, messages:[{role:"user", content:$p}]}'
}

load_model() {
  local name="$1"
  local file="$MODELS_DIR/$name.env"
  if [[ ! -f "$file" ]]; then
    echo "✗ unknown model '$name'. Available:" >&2
    "$SCRIPTS_DIR/list.sh" | sed 's/^/  - /' >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$file"
  set +a
}
