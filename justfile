# One model, one port, one MTPLX server.
export MODEL := "inkling-2-mini"
export REPO := "Youssofal/Inkling-2-Mini-MTPLX-Optimized-Speed"
export PORT := "8001"
SSD_CACHE_MAX := "20GB"
MODEL_DIR := env_var("HOME") + "/.mtplx/models/Youssofal--Inkling-2-Mini-MTPLX-Optimized-Speed"

[private]
default:
    @just --list

# Serve the model in the foreground on 127.0.0.1:{{PORT}}
[group('server')]
serve:
    mtplx quickstart       --model {{REPO}}       --model-id {{MODEL}}       --host 127.0.0.1       --port {{PORT}}       --ssd-session-cache-max-size {{SSD_CACHE_MAX}}       --no-stats-footer       --yes

# Download or update the model pack into ~/.mtplx/models
[group('model')]
pull:
    mkdir -p "$HOME/.mtplx/models" && touch "$HOME/.mtplx/models/.metadata_never_index"
    HF_HUB_DISABLE_XET=1 mtplx pull {{REPO}}

# Measure end-to-end decode throughput against :{{PORT}}
[group('check')]
bench:
    scripts/bench.sh

# Show MTPLX status, cached models, and what answers on :{{PORT}}
[group('server')]
status:
    @mtplx status
    @echo ""
    @mtplx models
    @echo ""
    @curl -sf "http://127.0.0.1:{{PORT}}/v1/models" | jq -r '.data[] | "serving: \(.id) (context \(.context_length))"' 2>/dev/null || echo "serving: (stopped)"

# Stop the MTPLX daemon on :{{PORT}}
[group('server')]
stop:
    mtplx stop --port {{PORT}}

# Check mtplx, llguidance, and the pulled pack's runtime contract
[group('check')]
doctor:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v mtplx >/dev/null || { echo "✗ mtplx missing — run: mise install" >&2; exit 1; }
    echo "✓ $(mtplx --version | head -1)"
    MTPLX_PY=$(mtplx status 2>/dev/null | awk '/^python:/ {print $2}')
    if [[ -z "$MTPLX_PY" ]] || ! "$MTPLX_PY" -c 'import llguidance' 2>/dev/null; then
      echo '✗ llguidance missing — add extras = "server" to pypi:mtplx in ~/.config/mise/config.toml' >&2
      exit 1
    fi
    echo "✓ llguidance"
    if [[ ! -d "{{MODEL_DIR}}" ]]; then
      echo "✗ {{REPO}} not pulled — run: just pull" >&2
      exit 1
    fi
    verdict=$(mtplx inspect --json --no-strict-exit-code "{{MODEL_DIR}}")
    tier=$(jq -r '.compatibility.tier // "unknown"' <<<"$verdict")
    runtime=$(jq -r '.compatibility.runtime_compatibility // "unknown"' <<<"$verdict")
    if [[ "$tier" != "verified" || "$runtime" != "native" ]]; then
      echo "✗ contract check failed: tier=$tier runtime=$runtime" >&2
      exit 1
    fi
    echo "✓ {{MODEL}} ($tier/$runtime)"
