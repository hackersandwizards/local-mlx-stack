#!/usr/bin/env bash
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPTS_DIR/../config/models"
PORT="${PORT:-8080}"

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
