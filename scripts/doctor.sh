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

VENV="$SCRIPTS_DIR/../.venv"
if [[ -d "$VENV" ]]; then
  ok ".venv present"
else
  warn ".venv missing. Run: just bootstrap"
fi

if compgen -G "$VENV/lib/python*/site-packages/mlx_vlm/__init__.py" >/dev/null; then
  ok "mlx-vlm installed"
else
  fail "mlx-vlm missing. Run: just bootstrap"
fi

bad=0
while read -r name; do
  id=$(load_model "$name" >/dev/null && echo "$MODEL_ID")
  if [[ "$id" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    ok "model '$name' → $id"
  else
    fail "model '$name' has invalid MODEL_ID: '${id:-unset}'"
    bad=1
  fi
done < <("$SCRIPTS_DIR/list.sh")
(( bad == 0 )) || exit 1

CACHE_PARENT="$HOME/.cache"
[[ -d "$HOME/.cache/huggingface" ]] && CACHE_PARENT="$HOME/.cache/huggingface"
if DISK_FREE_GB=$(df -Pk "$CACHE_PARENT" | awk 'NR==2 {printf "%d", $4/1024/1024}') && [[ -n "$DISK_FREE_GB" ]]; then
  if (( DISK_FREE_GB >= 60 )); then
    ok "$DISK_FREE_GB GB free for HF cache"
  else
    warn "only $DISK_FREE_GB GB free at $CACHE_PARENT. Registry needs ~21 GB."
  fi
else
  warn "could not read disk space at $CACHE_PARENT"
fi

PROXY_PORT="${PROXY_PORT:-8081}"
for p in "$PORT" "$PROXY_PORT"; do
  if port_in_use "$p"; then
    warn "port $p in use"
  else
    ok "port $p free"
  fi
done
