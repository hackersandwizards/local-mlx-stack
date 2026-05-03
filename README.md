# local-mlx-stack

Version-controlled local MLX inference for Apple Silicon. Serves OpenAI-compatible endpoints on `127.0.0.1:8080` from a project-local `.venv` — no system Python touched, manual start only.

## Model

| Name | Repo | RAM | Notes |
|---|---|---|---|
| `qwen3.6-35b` | `mlx-community/Qwen3.6-35B-A3B-4bit` | ~21 GB peak | Default. Vision + text + tools. |

Served via `mlx_vlm.server` (handles text-only and image input). Single port (8080), one model at a time.

### Why only the 4-bit

We tested both `Qwen3.6-35B-A3B-4bit` and `-8bit` end-to-end on an M3 Max 64 GB. The 8-bit costs +17 GB peak RAM and ~20 % throughput; published Unsloth data on the dense 27B sibling shows the 4↔8 perplexity gap is ~0.19 % (measurement noise). [mlx-lm #1011](https://github.com/ml-explore/mlx-lm/issues/1011) shows that flat-8bit MoE checkpoints also degrade on long multi-turn tool calls — just later than 4-bit, not absent. If real quality issues surface, the upgrade path is DWQ (`Qwen3.6-35B-A3B-4bit-DWQ`), not 8-bit. DWQ has no vision support; we keep vision in the default lane and accept the trade.

## Bootstrap (fresh machine)

```bash
# clone this repo into ~/opt/local-mlx-stack
cd ~/opt/local-mlx-stack
just bootstrap         # uv sync + doctor
just pull qwen3.6-35b  # ~20 GB into HF cache
just serve             # → 127.0.0.1:8080
```

Requires: `uv`, `just`, `jq`, `lsof`, `curl` (all standard on macOS + `brew install uv just jq`).

## Verified on M3 Max 64 GB

- ~88 tok/s steady-state on the bench prompt (after 2-iteration warmup; ~21 GB peak RAM)
- Structured `tool_calls` dispatch via `mlx_vlm.server` works — no `mlx-lm` fallback needed
- German, image-input (data URL), and Python code generation all pass

## Daily use

```bash
just models            # list registered models
just serve             # default model, foreground (Ctrl-C to stop)
just bench             # tok/s against the running server (server must be up)
just status            # what models the server has cached
just stop              # kill any mlx_vlm.server
just disk              # HF cache footprint
```

Note: `just status` lists every model in the HF cache that the running server can see, not strictly which one is loaded. Whoever you launched with `just serve <name>` is the one actually serving.

## Cleanup

```bash
just clean qwen3.6-35b      # remove the model from HF cache
just clean-all              # remove every model in config/models/
just clean-cache            # nuke ~/.cache/huggingface/hub (with prompt)
```

## Troubleshooting

- **`port 8080 already in use`** — run `just stop`, or `lsof -nP -iTCP:8080 -sTCP:LISTEN` to find the holder.
- **`mlx-vlm missing`** — run `just bootstrap`.
- **Image URL fails with 403** — some hosts (e.g. Wikimedia) block `requests`' default User-Agent. Use a base64 data URL or a host that doesn't UA-gate.
- **Model loads slowly on first request** — `serve.sh` pre-warms in the background after start; if you hit `/v1/chat/completions` immediately it pays the load tax.
