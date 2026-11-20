# Configuration

What this repository sets for Ollama, and what it leaves to Ollama.

## What this repo owns

Two values, both in the `justfile`: the model (`inkling-2-mini`) and the address (`127.0.0.1:8001`, passed as `OLLAMA_HOST`). The port is not Ollama's default 11434 because the client configs point at 8001.

Ollama owns the rest. With `OLLAMA_HOST=127.0.0.1:8001` set:

| Task | Command |
|---|---|
| Download or update the model | `ollama pull inkling-2-mini` |
| List the store | `ollama list` |
| Template, capabilities, required version | `ollama show inkling-2-mini` |
| What is loaded | `ollama ps` |
| Wire up a client | `ollama launch <client> --model inkling-2-mini` |

The model ships its own chat template and sampling, so no preset lives here.

## Thinking

The model thinks at `high` unless a request says otherwise. `ollama show` lists the levels: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. Clients set one per request with `reasoning_effort`.

On 0.40.17-rc3, `reasoning_effort: "none"` on `/v1/chat/completions` returned an empty answer that still used every allowed token; it is not explained. `"think": false` on Ollama's own `/api/chat` answered without thinking. An unknown level is accepted without an error.

## Context and memory

Ollama picked a context of 262,144 tokens on this machine, at 22 GB loaded. `OLLAMA_CONTEXT_LENGTH` sets another; how much memory a smaller one saves is not measured here. `OLLAMA_KEEP_ALIVE` sets how long an idle model stays loaded (default five minutes); `just stop` unloads it at once.

## Clients

Clients are configured in `~/.config/zed/settings.json`, `~/.pi/agent/models.json`, and `~/.config/opencode/opencode.json`. pi takes `compat.thinkingFormat: "openai"`, which sends `reasoning_effort`.
