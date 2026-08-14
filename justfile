DEFAULT_MODEL := "qwen3.6-27b"

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
    @mtplx stop --port 8001 --json > /dev/null 2>&1 && echo "✓ :8001 stopped" || echo "(nothing on :8001)"
    @mtplx stop --port 8002 --json > /dev/null 2>&1 && echo "✓ :8002 stopped" || echo "(nothing on :8002)"
