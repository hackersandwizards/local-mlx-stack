# The one model, and the port every client config points at.
export MODEL := "inkling-2-mini"
export PORT := "8001"
export OLLAMA_HOST := "127.0.0.1:" + PORT

default:
    @just status

serve:
    ollama serve

pull:
    ollama pull {{MODEL}}

bench:
    scripts/bench.sh

status:
    @ollama ps

stop:
    ollama stop {{MODEL}}
