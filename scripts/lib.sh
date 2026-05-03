#!/usr/bin/env bash
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPTS_DIR/../config/models"

list_models() { "$SCRIPTS_DIR/list.sh"; }

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
