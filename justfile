DEFAULT_MODEL := "qwen3.6-35b"

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

serve NAME=DEFAULT_MODEL:
    scripts/serve.sh {{NAME}}

bench NAME=DEFAULT_MODEL:
    scripts/bench.sh {{NAME}}

status:
    @scripts/status.sh

stop:
    @pkill -f 'omlx serve' && echo "✓ omlx stopped" || echo "(no omlx running)"
    @pkill -f 'mtplx.server.openai' && echo "✓ mtplx stopped" || echo "(no mtplx running)"

disk:
    @if [ -d ~/.cache/huggingface/hub ]; then uv run hf cache ls; else echo "(no HF cache yet)"; fi

clean NAME:
    scripts/clean.sh {{NAME}}

clean-all:
    @scripts/list.sh | xargs -n1 scripts/clean.sh

clean-cache:
    @scripts/clean-cache.sh
