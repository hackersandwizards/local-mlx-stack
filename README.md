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
| `qwen3.6-27b` | `Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed` | ~16 GB | ~40 | Dense 27B 4-bit, with calibrated MTP head. Vision + text + tools. ~2× faster than the prior 6-bit unsloth checkpoint, at a slight quality cost. |

¹ Measured on M3 Max 64 GB via `just bench`, 300-token decode after warmup. Last measured 2026-08-14 on omlx 0.5.7 / mtplx 2.6.0.

`qwen3.8-27b` is registered but not yet pulled: [Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed](https://huggingface.co/Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed) is still a README-only placeholder. It is the same `qwen3_5` architecture as the 3.6-27B (the two `config.json` differ only in `transformers_version`), so it is a checkpoint swap, not a runtime change. It gets its own port `:8002` so it can run next to the 3.6 for an A/B. `just doctor` reports it missing until the weights land.

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

- `config/models/<name>.env` declares `MODEL_ID`, `HF_REPO`, `BACKEND` (`omlx` or `mtplx`), and `PORT`, plus `MEMORY_GUARD_GB` (omlx) or `TEMPERATURE`/`TOP_P`/`TOP_K` (mtplx).
- `scripts/pull.sh` runs `hf download` into `~/.cache/huggingface/hub/` and symlinks the snapshot into the per-backend dir: `~/.omlx/models/$MODEL_ID/` or `~/.mtplx/models/$MODEL_ID/`. It refuses to link a snapshot without `*.safetensors`, so a README-only placeholder repo fails at pull instead of at serve.
- `scripts/serve.sh` dispatches on `BACKEND` to `serve-omlx.sh` (which runs `omlx serve --model-dir ~/.omlx/models/`) or `serve-mtplx.sh` (`mtplx quickstart --model ~/.mtplx/models/$MODEL_ID`).

The per-backend symlink dir matters: omlx auto-discovers every subdir of its `--model-dir`, so MTPLX-only checkpoints must live elsewhere or omlx will also advertise them. `serve-omlx.sh` additionally passes `--no-hf-cache`, because omlx otherwise advertises every repo in `~/.cache/huggingface/hub` as well — including the MTPLX build, which omlx must never load. With it, `:8080` lists exactly the registered omlx models.

## Sampling

Sampling is a per-model fact — Qwen publishes a different preset per release — so each MTPLX model's `.env` owns it and `serve-mtplx.sh` fails loudly if it is unset. Clients may still override per request.

- **omlx / 35B** — global `sampling` block in `~/.omlx/settings.json`, read by `omlx serve`. The model's own `generation_config.json` is not used by omlx. Currently Qwen3.6's thinking/coding preset: `temp 0.6`, `top_p 0.95`, `top_k 20`.
- **MTPLX** — `TEMPERATURE` / `TOP_P` / `TOP_K` in `config/models/<name>.env`, passed as `--default-temperature` / `--default-top-p` / `--default-top-k`. 3.6-27B uses the model card's precise-coding preset (`0.6 / 0.95 / 20`); 3.8-27B uses its thinking preset (`1.0 / 0.95 / 20`), since that card publishes no separate coding preset.

Neither backend can pin `presence_penalty`, so the guide's thinking/general preset (`presence_penalty 1.5`) is not fully reproducible here.

## Endpoints

Both expose OpenAI-compatible chat completions. Point clients at the right port per model:
- `http://127.0.0.1:8080/v1` → `qwen3.6-35b`
- `http://127.0.0.1:8001/v1` → `qwen3.6-27b`
- `http://127.0.0.1:8002/v1` → `qwen3.8-27b` (once pulled)

oMLX admin UI at `http://127.0.0.1:8080/admin` (model load/unload, KV cache stats, benchmarks).

## Troubleshooting

- **`port 8080/8001 already in use`** — run `just stop`, or `lsof -nP -iTCP:8080,8001 -sTCP:LISTEN` to find the holder.
- **`omlx missing` / `mtplx missing`** — run the brew commands in Bootstrap.
- **Model loads slowly on first request** — `serve-omlx.sh` warms in the background; `mtplx` runs a startup warmup generation (`--warmup-tokens`, on by default). Cold load on M3 Max: ~30 s (4-bit) to ~90 s (6-bit), ~16–17 GB resident.
- **Model not in `~/.omlx/models` or `~/.mtplx/models`** — run `just pull <name>`.
- **MTPLX reasoning content shows up in `content` instead of `reasoning_content`** — that's the non-streaming path. Clients that stream over SSE and parse Qwen3 thinking tags get the split. Run `just bench` to confirm tokens are generated cleanly; quality of the split is a client concern.
