#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

while read -r name; do
  load_model "$name" >/dev/null
  if RESP=$(curl -sf --max-time 1 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null); then
    echo "[:$PORT] $name [$BACKEND]:"
    jq -r '.data[].id' <<<"$RESP" | sed 's/^/  /'
  else
    echo "[:$PORT] $name [$BACKEND]: (no server)"
  fi
done < <("$SCRIPTS_DIR/list.sh")
