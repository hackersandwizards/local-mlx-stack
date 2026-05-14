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

if command -v mtplx >/dev/null; then
  ok "mtplx installed ($(mtplx --version 2>/dev/null | head -1))"
else
  fail "mtplx missing. Install: brew install youssofal/mtplx/mtplx"
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
  if [[ -e "$MODEL_PATH" ]]; then
    ok "model '$name' [$BACKEND :$PORT] → $MODEL_PATH"
  else
    warn "model '$name' missing symlink. Run: just pull $name"
    bad=1
  fi
  if [[ "$BACKEND" == "mtplx" && -e "$MODEL_PATH" ]] && command -v mtplx >/dev/null; then
    if verdict=$(mtplx inspect --json --no-strict-exit-code "$MODEL_PATH" 2>/dev/null); then
      tier=$(jq -r '.compatibility.tier // "unknown"' <<<"$verdict")
      runtime=$(jq -r '.compatibility.runtime_compatibility // "unknown"' <<<"$verdict")
      if [[ "$tier" == "verified" && "$runtime" == "native" ]]; then
        ok "  mtplx contract: $tier / $runtime"
      else
        warn "  mtplx contract: tier=$tier runtime=$runtime (expected verified/native)"
        bad=1
      fi
    else
      warn "  mtplx inspect failed for '$name'"
      bad=1
    fi
  fi
  if served_id=$(curl -sf --max-time 1 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null); then
    if grep -qx "$MODEL_ID" <<<"$served_id"; then
      ok "  :$PORT serving '$MODEL_ID'"
    else
      warn "  :$PORT in use but serving [$served_id], not '$MODEL_ID'"
    fi
  elif port_in_use "$PORT"; then
    warn "  :$PORT in use by non-OpenAI process (would block '$name')"
  fi
done < <("$SCRIPTS_DIR/list.sh")

CACHE_PARENT="$HOME/.cache"
[[ -d "$HOME/.cache/huggingface" ]] && CACHE_PARENT="$HOME/.cache/huggingface"
if DISK_FREE_GB=$(df -Pk "$CACHE_PARENT" | awk 'NR==2 {printf "%d", $4/1024/1024}') && [[ -n "$DISK_FREE_GB" ]]; then
  if (( DISK_FREE_GB >= 60 )); then
    ok "$DISK_FREE_GB GB free for HF cache"
  else
    warn "only $DISK_FREE_GB GB free at $CACHE_PARENT. 27B checkpoints need ~16–30 GB."
  fi
else
  warn "could not read disk space at $CACHE_PARENT"
fi

(( bad == 0 ))
