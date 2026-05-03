# local-mlx-stack

Version-controlled local MLX inference for Apple Silicon. Serves OpenAI-compatible endpoints on `127.0.0.1:8080` from a project-local `.venv` — no system Python touched, manual start only.

## Models

| Name | Repo | RAM | Notes |
|---|---|---|---|
| `qwen3.6-35b` | `mlx-community/Qwen3.6-35B-A3B-4bit` | ~17.5 GB | Default. Vision + text + tools. |
| `qwen3.6-35b-hq` | `mlx-community/Qwen3.6-35B-A3B-8bit` | ~35 GB | Higher quality, slower. |

Both served via `mlx_vlm.server` (handles text-only and image input). Single port (8080), one model at a time.

## Bootstrap (fresh machine)

```bash
# clone this repo into ~/opt/local-mlx-stack
cd ~/opt/local-mlx-stack
just bootstrap         # uv sync + doctor
just pull qwen3.6-35b  # ~17.5 GB download
just serve             # → 127.0.0.1:8080
```

Requires: `uv`, `just`, `jq`, `lsof`, `bc`, `curl` (all standard on macOS + `brew install uv just jq bc`).

## Status

- ✓ scaffold + `uv sync` verified on M3 Max 64 GB
- ✓ `just doctor` all-green
- ⏳ no model pulled yet, no server started yet — first end-to-end serve still TODO
- ⏳ tool-call parsing through `mlx_vlm.server` for Qwen3.6 unverified (see "Tool calls" below)

### Tool calls (unverified)

`mlx_vlm.server` exposes OpenAI-compatible endpoints, but Qwen3 tool-call structuring through it isn't documented. After the first `just serve qwen3.6-35b`, run:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model":"mlx-community/Qwen3.6-35B-A3B-4bit",
  "messages":[{"role":"user","content":"What is the weather in Hamburg?"}],
  "tools":[{"type":"function","function":{"name":"get_weather","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}]
}' | jq '.choices[0].message'
```

Pass = structured `.tool_calls` array. Fail = raw text in `.content` → fall back to `mlx-lm` for text/tools and keep `mlx-vlm` for vision only.

## Daily use

```bash
just models            # list registered models
just serve             # default model, foreground (Ctrl-C to stop)
just serve qwen3.6-35b-hq
just bench qwen3.6-35b # tok/s against the running server
just status            # what's running on :8080
just stop              # kill any mlx_vlm.server
just disk              # HF cache footprint
```

## Cleanup

```bash
just clean qwen3.6-35b-hq   # remove one model
just clean-all              # remove every model in config/models/
just clean-cache            # nuke ~/.cache/huggingface/hub (with prompt)
```

## Troubleshooting

- **`port 8080 already in use`** — run `just stop` or kill the process holding the port (`lsof -nP -iTCP:8080 -sTCP:LISTEN`).
- **`mlx-vlm missing`** — run `just bootstrap`.
- **Out of memory on 8-bit** — close other apps; the 8-bit model needs ~35 GB resident.
- **Model loads slowly on first request** — `serve.sh` pre-warms in the background after start; if you hit `/v1/chat/completions` immediately it pays the load tax.
