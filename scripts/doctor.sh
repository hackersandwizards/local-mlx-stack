#!/usr/bin/env bash
set -euo pipefail
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

if uv run python -c 'import mlx_vlm' 2>/dev/null; then
  ok "mlx-vlm importable"
else
  fail "mlx-vlm missing — run: just bootstrap"
fi

CACHE_PARENT="$HOME/.cache"
[[ -d "$HOME/.cache/huggingface" ]] && CACHE_PARENT="$HOME/.cache/huggingface"
# POSIX df (1K blocks) → GB; works under both BSD df and GNU coreutils df
DISK_FREE_GB=$(df -Pk "$CACHE_PARENT" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1024/1024}' || true)
if [[ -n "${DISK_FREE_GB:-}" ]] && (( DISK_FREE_GB >= 60 )); then
  ok "$DISK_FREE_GB GB free for HF cache"
else
  warn "only ${DISK_FREE_GB:-?} GB free at $CACHE_PARENT — registry totals ~52 GB"
fi

if lsof -nP -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1; then
  warn "port 8080 in use"
else
  ok "port 8080 free"
fi
