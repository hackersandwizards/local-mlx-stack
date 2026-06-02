# CLAUDE.md

Local MLX inference stack on this MacBook Pro (M3 Max, 64 GB unified memory, ~400 GB/s). Path: `/Users/bstemmildt/opt/local-mlx-stack`. Dual-backend, OpenAI-compatible serving for local models.

## Backends & models

- **`qwen3.6-35b`** *(default)* — `mlx-community/Qwen3.6-35B-A3B-4bit` (MoE, 35B total / 3B active, 4-bit). Served by **oMLX** on `:8080`. Text + tools, ~90 tok/s.
- **`qwen3.6-27b`** — `Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed` (dense 27B, 4-bit main + INT4 MTP sidecar). Served by **MTPLX** on `:8001`. Text + image + video + tools, ~25 tok/s with MTP on (~17 without).

## Serving

- `scripts/serve.sh` dispatches on `BACKEND=` in each `config/models/<name>.env`.
- Per-backend symlink dirs are load-bearing — **don't co-locate**: `~/.omlx/models/` (oMLX auto-discovers every subdir of its `--model-dir`) vs `~/.mtplx/models/`.
- oMLX: `omlx serve --model-dir ~/.omlx/models` + paged SSD prefix cache (50 GB) + 8 GB hot cache.
- MTPLX: `mtplx quickstart --profile performance-cold`; the verified-native tier needs `mtp.safetensors` + `mtplx_runtime.json` co-located with the model. Running process pattern is `mtplx.server.openai`.
- Justfile: `serve | bench | stop | status | disk | pull <name> | clean <name> | doctor | models`. `status`/`stop` are dual-backend aware; `just stop` kills both.

## Why this shape (2026-05-14 dual-backend migration)

- MTPLX's verified gate is the `qwen3-next-mtp` architecture; the 35B A3B is `qwen3_5_moe` and rejects. A MoE with only 3B active has too little verify-cost to amortize speculative drafting, so 35B stays on oMLX.
- The Youssofal repack of Qwen3.6-27B is the only verified-tier MTPLX checkpoint today; it preserves vision + video.
- Quality tradeoff: 4-bit vs prior unsloth 6-bit dynamic — small for instruction-following/coding, more visible on math/long-context.

## Clients (each lists both providers)

- **Zed** `~/.config/zed/settings.json` → `language_models.openai_compatible`: `local-mlx` (:8080) + `local-mlx-mtplx` (:8001, `images: true`). Validator needs the full `capabilities` block per model.
- **pi** `~/.pi/agent/models.json` → providers `local-mlx` + `local-mlx-mtplx`; `compat.thinkingFormat: "qwen"` enables client-side reasoning parse.
- **opencode** `~/.config/opencode/opencode.json` → two providers, same baseURL split; default `local-mlx/qwen3.6-35b`.

## Conventions

- Before recommending model changes, run `just models` (or `scripts/list.sh`) to see what is registered.
- New MTPLX models: confirm `mtplx inspect <path>` returns `tier: verified` + `runtime_compatibility: native` before wiring (it refuses otherwise without `--unsafe-force-unverified`).
- Benchmarks: `just bench <name>` (the 27B path hits `:8001` via `PORT=` in its `.env`).
- Reasoning split: oMLX/MTPLX split `reasoning_content` server-side in streaming only; non-streaming puts thinking into `content`. SSE clients use `--reasoning-parser qwen3`.
- **Verify before dismissing model names.** When the user names a model/version not in training data (cutoff Jan 2026; the clock may be months ahead), run one `WebSearch` before pushing back — confidently-wrong is worse than uncertain. (e.g. Qwen3.6-27B released 2026-04-22, post-cutoff.)
