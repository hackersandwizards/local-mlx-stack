#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

ok()   { echo "✓ $1"; }
warn() { echo "⚠ $1"; }
fail() { echo "✗ $1"; }

if command -v uv >/dev/null; then
  ok "uv installed"
else
  fail "uv missing — install: brew install uv"
fi

if [[ -d .venv ]]; then
  ok ".venv present"
else
  warn ".venv missing — run: just bootstrap"
fi

if compgen -G '.venv/lib/python*/site-packages/mlx_vlm/__init__.py' >/dev/null; then
  ok "mlx-vlm installed"
else
  fail "mlx-vlm missing — run: just bootstrap"
fi

bad=0
while read -r name; do
  # shellcheck disable=SC1090  # dynamic source by design (env per model)
  id=$(MODEL_ID=""; source "$MODELS_DIR/$name.env"; echo "$MODEL_ID")
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
    warn "only $DISK_FREE_GB GB free at $CACHE_PARENT — registry totals ~52 GB"
  fi
else
  warn "could not read disk space at $CACHE_PARENT"
fi

if lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1; then
  warn "port 8080 in use"
else
  ok "port 8080 free"
fi
