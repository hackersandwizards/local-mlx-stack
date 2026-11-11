# Configuration

What this repository sets for MTPLX, and what it leaves to MTPLX. The registry is `scripts/models.sh`.

## What this repo owns

MTPLX owns the model cache, downloads, health, and client wiring. Calling it directly is usually the right move:

| Task | Command |
|---|---|
| Download a model | `mtplx pull <hf-repo>` |
| List the cache | `mtplx models` |
| Compatibility check | `mtplx inspect <path>` |
| Wire up a client | `mtplx connect opencode` (also Claude Code, Open WebUI, Swival) |
| Stop a daemon | `mtplx stop --port <p>` |
| Find the fastest draft depth | `mtplx tune` |

What is left here is what MTPLX does not persist: the per-model sampling preset, the exact serve invocation, and a benchmark that reports decode throughput rather than draft depth. `scripts/models.sh` holds the whole registry.

## Sampling

Qwen publishes a different preset per release, so it belongs next to the model and lives in `scripts/models.sh`. MTPLX persists none of it: `mtplx settings set` only reaches a running daemon, and `~/.mtplx/config.toml` covers the default model and profile, not sampling.

- `qwen3.8-27b`: `temp 1.0`, `top_p 0.95`, `top_k 20` -- the official sampler from the MTPLX 2.7.0 release notes.
- `qwen3.6-35b`: `temp 0.6`, `top_p 0.95`, `top_k 20` -- the `sampler` in the pack's own `mtplx_runtime.json`.

The preset does not pin `presence_penalty`; MTPLX has `--default-presence-penalty` but the thinking preset sets it to 0 anyway. Clients override per request.

`REASONING_EFFORT` sits in the same registry entry. The model card defaults to `xhigh`, which is expensive on a dense 27B; MTPLX's own coding default is `medium`, so the registry pins that and `serve.sh` passes it on. Measured per request on 2026-08-16, same prompt: `low` 1891, `medium` 2439, `xhigh` 3801 completion tokens. Clients override per request via `reasoning_effort`.

## Clients

Clients are configured in `~/.config/zed/settings.json`, `~/.pi/agent/models.json`, and `~/.config/opencode/opencode.json`. `mtplx connect <client>` prints the settings for the ones it knows.
