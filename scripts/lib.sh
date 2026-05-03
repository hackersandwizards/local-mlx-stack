#!/usr/bin/env bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$PROJECT_ROOT/config/models"

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
  set -a; source "$file"; set +a
}
