#!/usr/bin/env bash
# Served id -> repo and sampling. Sampling is per release: Qwen publishes a
# different preset per model card, and MTPLX persists none of it, so it lives
# here next to the model it belongs to.
MODELS_DIR="${MTPLX_MODEL_DIR:-$HOME/.mtplx/models}"

# serve.sh replaces whatever holds the port rather than starting a second daemon.
PORT=8001

# Faster than sustained; see README for the measurement and the tradeoff.
PROFILE=turbo

# Every served id. doctor.sh and the justfile iterate this rather than
# repeating the list.
ALL_MODELS="qwen3.8-27b qwen3.6-35b"

load_model() {
  case "${1:-}" in
    qwen3.8-27b)
      HF_REPO=Youssofal/Qwen3.8-27B-MTPLX-Optimized-Quality
      TEMPERATURE=1.0; TOP_P=0.95; TOP_K=20
      # The model card defaults to xhigh, which is expensive on a dense 27B.
      # MTPLX's own coding default is medium; pin it rather than inherit.
      REASONING_EFFORT=medium ;;
    qwen3.6-35b)
      HF_REPO=Youssofal/Qwen3.6-35B-A3B-MTPLX-Optimized-Speed
      TEMPERATURE=0.6; TOP_P=0.95; TOP_K=20
      REASONING_EFFORT=medium ;;
    *)
      echo "✗ unknown model '${1:-}'. Known: $ALL_MODELS" >&2
      return 1 ;;
  esac
  MODEL_ID="$1"
  MODEL_PATH="$MODELS_DIR/$MODEL_ID"
}
