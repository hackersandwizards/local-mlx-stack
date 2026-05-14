# local-mlx-stack

Local inference for Apple Silicon. Two OpenAI-compatible servers on loopback, one per backend.

| Backend | Port | Default model | Why this backend |
|---|---|---|---|
| [oMLX](https://github.com/jundot/omlx) | `:8080` | `qwen3.6-35b` (default) | Multi-model serving, paged SSD prefix cache, native `reasoning_content` SSE split |
| [MTPLX](https://github.com/youssofal/MTPLX) | `:8001` | `qwen3.6-27b` | Native MTP speculative decoding — verified path only |

## Models

| Name | Repo | RAM | tok/s¹ | Notes |
|---|---|---|---|---|
| `qwen3.6-35b` *(default)* | `mlx-community/Qwen3.6-35B-A3B-4bit` | ~17 GB | ~90 | MoE, 3 B active params per token. Text + tools. Fast bulk generation. |
| `qwen3.6-27b` | `Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed` | ~16 GB | ~25 | Dense 27B 4-bit, with calibrated MTP head. Vision + text + tools. ~2× faster than the prior 6-bit unsloth checkpoint, at a slight quality cost. |

¹ Measured on M3 Max 64 GB via `just bench`, 300-token decode after warmup.

oMLX runs with paged SSD prefix cache (`~/.omlx/cache`, 50 GB) and 8 GB hot cache. MTPLX uses native MTP speculative decoding (`mtplx quickstart --profile performance-cold`); the 1.5× speedup over `--no-mtp` on the same checkpoint isolates MTP's contribution.

## Bootstrap (fresh machine)

```bash
# prereqs
brew install uv just jq
brew tap jundot/omlx https://github.com/jundot/omlx && brew install omlx
brew install youssofal/mtplx/mtplx

# repo
cd ~/opt/local-mlx-stack
just bootstrap         # uv sync + doctor
just pull-all          # fetches both models into HF cache + per-backend symlinks
just serve qwen3.6-35b # foreground on :8080 (Ctrl-C to stop)
# separate terminal:
just serve qwen3.6-27b # foreground on :8001
```

## Daily use

```bash
just models                # list registered models
just serve [NAME]          # default qwen3.6-35b; pick a backend by name
just bench [NAME]          # tok/s against the model's assigned port
just status                # what each backend's /v1/models reports
just stop                  # kill both omlx and mtplx
just disk                  # HF cache footprint
just pull NAME | pull-all  # fetch one or every registered model
just clean NAME | clean-all  # drop one or every registered symlink + HF cache entry
just clean-cache           # nuke ~/.cache/huggingface/hub and per-backend dirs (asks)
```

## How models are wired

- `config/models/<name>.env` declares `MODEL_ID`, `HF_REPO`, `BACKEND` (`omlx` or `mtplx`), and `PORT`.
- `scripts/pull.sh` runs `hf download` into `~/.cache/huggingface/hub/` and symlinks the snapshot into the per-backend dir: `~/.omlx/models/$MODEL_ID/` or `~/.mtplx/models/$MODEL_ID/`.
- `scripts/serve.sh` dispatches on `BACKEND` to `serve-omlx.sh` (which runs `omlx serve --model-dir ~/.omlx/models/`) or `serve-mtplx.sh` (`mtplx quickstart --model ~/.mtplx/models/$MODEL_ID`).

The per-backend symlink dir matters: omlx auto-discovers every subdir of its `--model-dir`, so MTPLX-only checkpoints must live elsewhere or omlx will also advertise them.

## Endpoints

Both expose OpenAI-compatible chat completions. Point clients at the right port per model:
- `http://127.0.0.1:8080/v1` → `qwen3.6-35b`
- `http://127.0.0.1:8001/v1` → `qwen3.6-27b`

oMLX admin UI at `http://127.0.0.1:8080/admin` (model load/unload, KV cache stats, benchmarks).

## Troubleshooting

- **`port 8080/8001 already in use`** — run `just stop`, or `lsof -nP -iTCP:8080,8001 -sTCP:LISTEN` to find the holder.
- **`omlx missing` / `mtplx missing`** — run the brew commands in Bootstrap.
- **Model loads slowly on first request** — `serve-omlx.sh` warms in the background; `mtplx` warms via `--warmup-tokens 16` during startup. Cold load on M3 Max: ~30 s (4-bit) to ~90 s (6-bit), ~16–17 GB resident.
- **Model not in `~/.omlx/models` or `~/.mtplx/models`** — run `just pull <name>`.
- **MTPLX reasoning content shows up in `content` instead of `reasoning_content`** — that's the non-streaming path. Clients that stream over SSE and parse Qwen3 thinking tags get the split. Run `just bench` to confirm tokens are generated cleanly; quality of the split is a client concern.
