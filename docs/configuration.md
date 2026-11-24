# Configuration

What this repository sets for MTPLX, and what it leaves to MTPLX.

## What this repo owns

Four values in the `justfile`: the served id (`inkling-2-mini`), the pack repo (`Youssofal/Inkling-2-Mini-MTPLX-Optimized-Speed`), the loopback port (`8001`), and the SSD SessionBank cap (`20GB`).

MTPLX owns everything else. Useful direct commands:

| Task | Command |
| --- | --- |
| List cached packs | `mtplx models` |
| Inspect a pack's contract | `mtplx inspect <path>` |
| Reclaim orphaned SSD cache files | `mtplx gc --apply` |
| Inspect live server health | `curl -s http://127.0.0.1:8001/health \| jq` |
| Inspect live settings | `mtplx settings get --port 8001` |

## Sampler, profile and draft depth

MTPLX 2.13.3 sets these automatically from its `inkling2_loop` descriptor:

- Sampler: `temperature = 1.0`, `top_p = 1.0`, `top_k = 0` (Thinking Machines' official sampler; client-sent overrides are respected).
- Profile: `sustained` (recommended by the pack's `mtplx_runtime.json`).
- Speculative decoding: native DSpark drafter at default depth `3` (range `1–7`), plus context-copy speculation.

## Thinking

Default reasoning effort is `high`. Accepted `reasoning_effort` values: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`. Thinking arrives in `reasoning_content` (both streaming and non-streaming).

To disable thinking completely, send `"enable_thinking": false`. Sending `"reasoning_effort": "none"` alone still produces brief reasoning tokens.

## Context and SSD session cache

On this 64 GB M3 Max, MTPLX automatically resolves a machine-bound context window of `716,800` tokens (the model supports up to `1,048,576`, which would swap on 64 GB).

The persistent SSD SessionBank cache (`~/.mtplx/session-bank`) is on by default and capped at `20GB` by `just serve` (`--ssd-session-cache-max-size 20GB`).

## Clients

Both clients point at provider `local-mlx` (`http://127.0.0.1:8001/v1`, model `inkling-2-mini`):

- **Zed:** `~/.config/zed/settings.json` (`max_tokens: 716800`, tools, images, parallel tool calls, interleaved reasoning).
- **pi:** `~/.pi/agent/models.json` (`compat.thinkingFormat: "qwen"`, `headers["x-mtplx-client"]: "pi"`, `thinkingLevelMap` for `minimal`/`xhigh`/`max`) plus `~/.pi/agent/extensions/mtplx-session-headers.ts` to forward `x-mtplx-session-id` for SSD SessionBank reuse across restarts.
