#!/usr/bin/env bash
# Served id -> repo and sampling. Sampling is per release: Qwen publishes a
# different preset per model card, and MTPLX persists none of it, so it lives
# here next to the model it belongs to.
MODELS_DIR="${MTPLX_MODEL_DIR:-$HOME/.mtplx/models}"

# One port, because serving is exclusive: serve.sh replaces whatever is running
# rather than starting a second daemon. Two 27B models at long context do not
# fit 64 GB together, and one port keeps every client config unchanged.
PORT=8001

# Faster by 5-10% than sustained. The tradeoff is that turbo's 4-bit
# speculative-verify kernels are not bit-exact against stock; see README.
PROFILE=turbo

# Every served id. doctor.sh and the justfile iterate this rather than
# repeating the list.
ALL_MODELS="qwen3.8-27b qwen3.8-27b-abliterated"

load_model() {
  case "${1:-}" in
    qwen3.8-27b)
      HF_REPO=Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed
      TEMPERATURE=1.0; TOP_P=0.95; TOP_K=20
      # The model card defaults to xhigh, which is expensive on a dense 27B.
      # MTPLX's own coding default is medium; pin it rather than inherit.
      REASONING_EFFORT=medium ;;
    qwen3.8-27b-abliterated)
      HF_REPO=PocketAiHub/Qwen3.8-27B-Abliterated-MTPLX-Optimized-Speed
      # Same quantization recipe as the model above, applied to abliterated
      # weights -- its mtplx_runtime.json names recipe_origin as that repo.
      # That file contradicts itself on sampling: `sampler` says 0.6, while
      # `recommended_draft_sampler` and the model card say 1.0. Take 1.0, which
      # is both the official Qwen3.8 preset and what its benchmarks ran on.
      TEMPERATURE=1.0; TOP_P=0.95; TOP_K=20
      REASONING_EFFORT=medium ;;
    *)
      echo "✗ unknown model '${1:-}'. Known: $ALL_MODELS" >&2
      return 1 ;;
  esac
  MODEL_ID="$1"
  MODEL_PATH="$MODELS_DIR/$MODEL_ID"
}
