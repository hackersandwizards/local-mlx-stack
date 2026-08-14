#!/usr/bin/env bash
# Served id -> repo, port, sampling. Sampling is per release: Qwen publishes a
# different preset per model card, and MTPLX persists none of it, so it lives
# here next to the model it belongs to.
MODELS_DIR="${MTPLX_MODEL_DIR:-$HOME/.mtplx/models}"

# Long-context coding and agent sessions. See README for the measurement.
PROFILE=sustained

load_model() {
  case "${1:-}" in
    qwen3.6-27b)
      HF_REPO=Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed
      PORT=8001; TEMPERATURE=0.6; TOP_P=0.95; TOP_K=20 ;;
    qwen3.8-27b)
      HF_REPO=Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed
      PORT=8002; TEMPERATURE=1.0; TOP_P=0.95; TOP_K=20 ;;
    *)
      echo "✗ unknown model '${1:-}'. Known: qwen3.6-27b qwen3.8-27b" >&2
      return 1 ;;
  esac
  MODEL_ID="$1"
  MODEL_PATH="$MODELS_DIR/$MODEL_ID"
}
