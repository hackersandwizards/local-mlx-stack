DEFAULT_MODEL := "qwen3.8-27b"

default:
    @just status

serve NAME=DEFAULT_MODEL:
    scripts/serve.sh {{NAME}}

bench NAME=DEFAULT_MODEL:
    scripts/bench.sh {{NAME}}

pull NAME=DEFAULT_MODEL:
    scripts/pull.sh {{NAME}}

doctor:
    @scripts/doctor.sh

models:
    @mtplx models

status:
    @mtplx status

stop:
    @. scripts/models.sh && \
      { mtplx stop --port $PORT --json > /dev/null 2>&1 && echo "✓ :$PORT stopped" || echo "(nothing on :$PORT)"; }
