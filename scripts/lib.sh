#!/usr/bin/env bash
MODELS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config/models" && pwd)"

list_models() {
  find "$MODELS_DIR" -name '*.env' -exec basename {} .env \; | sort
}

load_model() {
  local name="$1"
  local file="$MODELS_DIR/$name.env"
  if [[ ! -f "$file" ]]; then
    echo "✗ unknown model '$name'. Available:" >&2
    list_models | sed 's/^/  - /' >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090  # dynamic source by design (env per model)
  source "$file"
  set +a
}
