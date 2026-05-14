#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

ok()   { echo "✓ $1"; }
warn() { echo "⚠ $1" >&2; }
fail() { echo "✗ $1" >&2; }

if command -v uv >/dev/null; then
  ok "uv installed"
else
  fail "uv missing. Install: brew install uv"
fi

if command -v omlx >/dev/null; then
  ok "omlx installed"
else
  fail "omlx missing. Install: brew tap jundot/omlx https://github.com/jundot/omlx && brew install omlx"
fi

VENV="$SCRIPTS_DIR/../.venv"
if [[ -d "$VENV" ]]; then
  ok ".venv present"
else
  warn ".venv missing. Run: just bootstrap"
fi

bad=0
while read -r name; do
  load_model "$name" >/dev/null
  : "${MODEL_ID:?MODEL_ID unset in $name.env}"
  : "${HF_REPO:?HF_REPO unset in $name.env}"
  link="$HOME/.omlx/models/$MODEL_ID"
  if [[ -e "$link" ]]; then
    ok "model '$name' → ~/.omlx/models/$MODEL_ID"
  else
    warn "model '$name' missing symlink. Run: just pull $name"
    bad=1
  fi
done < <("$SCRIPTS_DIR/list.sh")

CACHE_PARENT="$HOME/.cache"
[[ -d "$HOME/.cache/huggingface" ]] && CACHE_PARENT="$HOME/.cache/huggingface"
if DISK_FREE_GB=$(df -Pk "$CACHE_PARENT" | awk 'NR==2 {printf "%d", $4/1024/1024}') && [[ -n "$DISK_FREE_GB" ]]; then
  if (( DISK_FREE_GB >= 60 )); then
    ok "$DISK_FREE_GB GB free for HF cache"
  else
    warn "only $DISK_FREE_GB GB free at $CACHE_PARENT. Qwen3.6-27B needs ~30 GB."
  fi
else
  warn "could not read disk space at $CACHE_PARENT"
fi

if port_in_use "$PORT"; then
  warn "port $PORT in use"
else
  ok "port $PORT free"
fi

(( bad == 0 ))
