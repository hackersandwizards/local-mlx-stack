# local-mlx-stack

One OpenAI-compatible server on loopback: [MTPLX](https://github.com/youssofal/MTPLX) with native MTP speculative decoding, serving a dense Qwen 27B on Apple Silicon.

## Models

| Name | Repo | Port | Disk | tok/s¹ | Notes |
|---|---|---|---|---|---|
| `qwen3.6-27b` *(default)* | `Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed` | 8001 | 16.4 GB | ~40 | Dense 27B 4-bit with calibrated MTP head. Text + image + video + tools. |
| `qwen3.8-27b` | `Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed` | 8002 | - | - | Weights pending; the repo is still a README-only placeholder. Same `qwen3_5` architecture as the 3.6 (the two `config.json` differ only in `transformers_version`), so it is a checkpoint swap. Own port so it can run next to the 3.6 for an A/B. |

¹ M3 Max 64 GB, `just bench`, 300-token decode after warmup. Throughput moves several tok/s with thermal state, so treat single runs as indicative.

## Daily use

```bash
just serve [NAME]   # foreground, Ctrl-C to stop
just bench [NAME]   # end-to-end tok/s against the model's port
just pull [NAME]    # mtplx pull + symlink to the short served id
just status         # mtplx status
just models         # mtplx models
just stop           # stops :8001 and :8002
just doctor         # contract check per model, then mtplx status
```

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

- `qwen3.6-27b`: `temp 0.6`, `top_p 0.95`, `top_k 20`, the model card's precise-coding preset.
- `qwen3.8-27b`: `temp 1.0`, `top_p 0.95`, `top_k 20`. That card publishes no separate coding preset, so the thinking values are carried over unchanged until measured.

Neither preset pins `presence_penalty`; MTPLX has `--default-presence-penalty` but the thinking presets set it to 0 anyway. Clients override per request.

## Profile

`PROFILE` in `scripts/models.sh`, currently `sustained`. Until 2026-08-14 this was `performance-cold`, which MTPLX itself describes as "not recommended for long context".

Measured on 2026-08-14, alternating the candidates with 90 s cooldowns so thermal drift hits both equally (300-token decode, median of three; long lane is a 1500-token decode after a 10,523-token prompt):

| Profile | short | long |
|---|---|---|
| `sustained` | 33.2 / 31.3 | 29.7 / 28.1 |
| `turbo` | 35.3 / 34.3 | 31.3 / 30.2 |

`turbo` is 5-10% faster in both lanes and held that lead from the hotter position in each pair. It stays off anyway: its 4-bit speculative-verify kernels are argmax- and sampler-distribution-validated but not bit-exact against stock, and this stack exists to trade throughput for quality per token. `turbo` is the opt-in when a session is short-context and speed-bound; its compiled verify only engages up to 12,288 tokens of context and falls back to the eager path above that. `exact` sits on the other side of the same axis and is unmeasured here.

Single runs rank nothing. Absolute throughput moved by more than 50% across sessions on identical configs, driven by thermal state and how warm the session bank was.

## Endpoints

```
http://127.0.0.1:8001/v1  -> qwen3.6-27b
http://127.0.0.1:8002/v1  -> qwen3.8-27b (once pulled)
```

Clients are configured in `~/.config/zed/settings.json`, `~/.pi/agent/models.json`, and `~/.config/opencode/opencode.json`. `mtplx connect <client>` prints the settings for the ones it knows.

## Troubleshooting

- `port already in use`: `just stop`, or `lsof -nP -iTCP:8001,8002 -sTCP:LISTEN` to find the holder.
- `mtplx missing`: `brew install youssofal/mtplx/mtplx`.
- Model not pulled: `just pull <name>`. A placeholder repo without weight shards fails there, not at serve time.
- Reasoning shows up in `content` instead of `reasoning_content`: that is the non-streaming path. SSE clients get the split via `--reasoning-parser qwen3`.
- Freeing disk: `mtplx models` for sizes, then remove the directory under `~/.mtplx/models`.
