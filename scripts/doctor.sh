#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=models.sh
source "$(dirname "$0")/models.sh"

command -v mtplx >/dev/null || {
  echo "✗ mtplx missing. Install: brew install youssofal/mtplx/mtplx" >&2
  exit 1
}
echo "✓ $(mtplx --version 2>/dev/null | head -1)"

bad=0
for name in qwen3.6-27b qwen3.8-27b; do
  load_model "$name"
  if [[ ! -e "$MODEL_PATH" ]]; then
    echo "⚠ $name not pulled. Run: just pull $name" >&2
    bad=1
    continue
  fi
  # MTPLX refuses unverified checkpoints at serve time without an explicit
  # override, so check the contract here rather than discovering it then.
  verdict=$(mtplx inspect --json --no-strict-exit-code "$MODEL_PATH" 2>/dev/null) || verdict=""
  tier=$(jq -r '.compatibility.tier // "unknown"' <<<"${verdict:-{\}}")
  runtime=$(jq -r '.compatibility.runtime_compatibility // "unknown"' <<<"${verdict:-{\}}")
  if [[ "$tier" == "verified" && "$runtime" == "native" ]]; then
    echo "✓ $name [:$PORT] $tier/$runtime"
  else
    echo "⚠ $name [:$PORT] tier=$tier runtime=$runtime (expected verified/native)" >&2
    bad=1
  fi
done

mtplx status 2>&1 | sed 's/^/  /'
(( bad == 0 ))
