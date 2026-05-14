#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_model "${1:?usage: serve.sh <model-name>}"

if port_in_use "$PORT"; then
  echo "✗ port $PORT already in use. Run 'just stop' or pick another port." >&2
  exit 1
fi

if [[ ! -e "$MODEL_PATH" ]]; then
  echo "✗ model '$MODEL_ID' not at $MODEL_PATH. Run 'just pull ${1}' first." >&2
  exit 1
fi

case "$BACKEND" in
  omlx)   exec "$SCRIPTS_DIR/serve-omlx.sh" ;;
  mtplx)  exec "$SCRIPTS_DIR/serve-mtplx.sh" ;;
  *)      echo "✗ unknown BACKEND '$BACKEND' in $MODEL_ID.env" >&2; exit 1 ;;
esac
