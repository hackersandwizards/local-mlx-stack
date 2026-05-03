# local-mlx-stack

Version-controlled local MLX inference for Apple Silicon. Serves OpenAI-compatible endpoints on `127.0.0.1:8080` from a project-local `.venv`. No system Python touched, manual start only.

## Model

| Name | Repo | RAM | Notes |
|---|---|---|---|
| `qwen3.6-35b` | `mlx-community/Qwen3.6-35B-A3B-4bit` | ~21 GB peak | Default. Vision + text + tools. |

Served via `mlx_vlm.server` (handles text-only and image input). Single port (`8080`, override with `PORT=...`), one model at a time.

## Bootstrap (fresh machine)

```bash
# clone this repo into ~/opt/local-mlx-stack
cd ~/opt/local-mlx-stack
just bootstrap         # uv sync + doctor
just pull qwen3.6-35b  # ~20 GB into HF cache
just serve             # → 127.0.0.1:8080
```

Requires: `uv`, `just`, `jq`, `lsof`, `curl` (all standard on macOS + `brew install uv just jq`).

## On M3 Max 64 GB

- ~88 tok/s steady-state on the bench prompt; ~21 GB peak RAM
- OpenAI-compatible: structured `tool_calls`, German, image input (data URL), code

## Daily use

```bash
just models            # list registered models
just serve             # default model, foreground (Ctrl-C to stop)
just bench             # tok/s against the running server (server must be up)
just status            # what the server reports via /v1/models
just stop              # kill any mlx_vlm.server
just disk              # HF cache footprint
```

Note: `just status` reflects what the running server advertises at `/v1/models`. With `mlx_vlm.server --model X`, that's typically just `X`. The HF cache may hold more models than the live server exposes; use `just disk` to inspect cached weights.

## Cleanup

```bash
just clean qwen3.6-35b      # remove the model from HF cache
just clean-all              # remove every model in config/models/
just clean-cache            # nuke ~/.cache/huggingface/hub (with prompt)
```

## Troubleshooting

- **`port 8080 already in use`**: run `just stop`, or `lsof -nP -iTCP:8080 -sTCP:LISTEN` to find the holder.
- **`mlx-vlm missing`**: run `just bootstrap`.
- **Image URL fails with 403**: some hosts (e.g. Wikimedia) block `requests`' default User-Agent. Use a base64 data URL or a host that doesn't UA-gate.
- **Model loads slowly on first request**: `serve.sh` pre-warms in the background after start; if you hit `/v1/chat/completions` immediately it pays the load tax.
