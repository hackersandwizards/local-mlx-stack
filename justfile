default:
    @just models

bootstrap:
    uv sync
    @just doctor

doctor:
    @scripts/doctor.sh

models:
    @scripts/list.sh | sed 's/^/  - /'

pull NAME:
    scripts/pull.sh {{NAME}}

pull-all:
    @scripts/list.sh | xargs -n1 scripts/pull.sh

serve NAME="qwen3.6-35b":
    scripts/serve.sh {{NAME}}

bench NAME="qwen3.6-35b":
    scripts/bench.sh {{NAME}}

status:
    @if RESP=$(curl -sf http://127.0.0.1:8080/v1/models 2>/dev/null); then \
      echo "$RESP" | jq -r '.data[].id'; \
    else \
      echo "(no server running on :8080)"; \
    fi

stop:
    @pkill -f mlx_vlm.server || echo "(nothing to stop)"

disk:
    @if [ -d ~/.cache/huggingface/hub ]; then uv run hf cache ls; else echo "(no HF cache yet)"; fi

clean NAME:
    scripts/clean.sh {{NAME}}

clean-all:
    @scripts/list.sh | xargs -n1 scripts/clean.sh

clean-cache:
    @echo "This will delete ~/.cache/huggingface/hub entirely (all HF models, not just our registry)."
    @read -p "Type 'yes' to continue: " confirm && [ "$$confirm" = "yes" ]
    rm -rf ~/.cache/huggingface/hub
    @echo "✓ HF cache cleared"
