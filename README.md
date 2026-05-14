# local-mlx-stack

Local inference for Apple Silicon. Serves OpenAI-compatible endpoints on `127.0.0.1:8080` via [oMLX](https://github.com/jundot/omlx). Multiple models on disk, one served at a time, manual start.

## Models

| Name | Repo | RAM | tok/s¹ | Notes |
|---|---|---|---|---|
| `qwen3.6-35b` *(default)* | `mlx-community/Qwen3.6-35B-A3B-4bit` | ~17 GB weights + KV | ~90 | MoE, 3 B active params per token. Text + tools. Fast bulk generation. |
| `qwen3.6-27b` | `unsloth/Qwen3.6-27B-UD-MLX-6bit` | ~29 GB weights + KV | ~12 | Dense 27B. Vision + text + tools. SWE-bench Verified 77.2%. Higher per-token quality. |

¹ Measured on M3 Max 64 GB via `just bench`, 300-token decode after prefix-cache warmup.

Served via `omlx serve` with paged SSD prefix cache (`~/.omlx/cache`, 50 GB) and 8 GB hot cache. KV state persists across requests, so repeated prefixes (system prompt + file context) don't re-prefill.

## Bootstrap (fresh machine)

```bash
# prereqs
brew install uv just jq
brew tap jundot/omlx https://github.com/jundot/omlx && brew install omlx

# repo
cd ~/opt/local-mlx-stack
just bootstrap         # uv sync + doctor
just pull qwen3.6-35b  # ~17 GB into HF cache, symlinks into ~/.omlx/models/
just serve             # default (qwen3.6-35b) → 127.0.0.1:8080
```

## Daily use

```bash
just models            # list registered models
just serve             # default model, foreground (Ctrl-C to stop)
just bench             # tok/s against the running server
just status            # what /v1/models reports
just stop              # kill omlx serve
just disk              # HF cache footprint
just clean qwen3.6-35b # remove model from HF cache + ~/.omlx/models symlink
```

## How models are wired

- `config/models/<name>.env` declares `MODEL_ID` (oMLX-visible name) and `HF_REPO` (HuggingFace repo).
- `scripts/pull.sh` runs `hf download` into `~/.cache/huggingface/hub/` and symlinks the snapshot into `~/.omlx/models/$MODEL_ID/`.
- `scripts/serve.sh` runs `omlx serve --model-dir ~/.omlx/models/`. oMLX discovers models by subdir name.

oMLX cannot read the HF Hub cache layout directly ([issue #10](https://github.com/jundot/omlx/issues/10)); the symlink bridges it without duplicating 29 GB of weights.

## Endpoints

OpenAI-compatible and Anthropic Messages on `:8080`. Point any client at `http://127.0.0.1:8080/v1`.

Admin UI at `http://127.0.0.1:8080/admin` (model load/unload, KV cache stats, benchmarks).

## Troubleshooting

- **`port 8080 already in use`** — run `just stop`, or `lsof -nP -iTCP:8080 -sTCP:LISTEN` to find the holder.
- **`omlx missing`** — run the brew commands in Bootstrap.
- **Model loads slowly on first request** — `serve.sh` warms in the background; if you hit `/v1/chat/completions` immediately it pays the load tax (~30–60 s for 17 GB, ~60–90 s for 29 GB).
- **Model not in `~/.omlx/models`** — run `just pull qwen3.6-35b` (or `qwen3.6-27b`).
