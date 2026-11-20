# CLAUDE.md

Local MLX inference on this MacBook Pro (M3 Max, 64 GB unified memory, ~400 GB/s). Path: `/Users/bstemmildt/dev/hackersandwizards/internal/local-mlx-stack`. Single backend, single model, OpenAI-compatible.

## Model

**`inkling-2-mini`** -- `thinkingmachines/Inkling-2-Mini` from Ollama's library (tag `26b-a5b-nvfp4`, MoE, 26.4B with 3.4B active, middle 12 layers looped three times, NVFP4 and MXFP8 as released, 19 GB on disk, 22 GB loaded). Text, image and tools. Ollama rejects any other requested id with `not found`.

## Serving

- The `justfile` holds the model and the port and exports `OLLAMA_HOST=127.0.0.1:8001`. Recipes: `serve | pull | bench | status | stop`.
- `just serve` is `ollama serve` in the foreground. Ollama loads the model on the first request and unloads it after five idle minutes.
- The model store is `~/.ollama/models`.
- Ollama is installed by mise from `~/.config/mise/config.toml`, pinned to `0.40.17-rc3`: the model requires 0.40.17, and mise installs a release candidate only by exact version. Change the pin to `latest` once 0.40.17 is stable.

## Why this shape (2026-11-20, Inkling only)

- Replaced MTPLX and two Qwen packs (`qwen3.8-27b`, 27-28 tok/s; `qwen3.6-35b`, 94-100 tok/s) on the user's call: one model, chosen on the vendor's benchmarks against Qwen3.8-27B and on its footprint. Throughput was assumed, not measured: `docs/measurements.md` has two quiet runs at 25.4 and 28.0 tok/s and fourteen disturbed ones.
- What was given up: the fast lane, video input, and a stable backend release.
- Ollama's MLX runner was on that day the only Mac runtime that loaded this model with its draft model (the `mtp.safetensors` DSpark drafter). MTPLX had no loader for it, oMLX had Inkling 2 Small only, and mlx-lm's Inkling 2 pull request ([#2061](https://github.com/ml-explore/mlx-lm/pull/2061)) had no code for the looped layers.
- With one model and Ollama owning pull, store, template and sampling, the registry, the serve and pull scripts and the doctor went. What remains is the port, the model name and a tok/s bench.

## Clients

- **Zed** `~/.config/zed/settings.json` -> `language_models.openai_compatible`. Validator needs the full `capabilities` block per model.
- **pi** `~/.pi/agent/models.json` -> `compat.thinkingFormat: "openai"`.
- **opencode** `~/.config/opencode/opencode.json`.
- `ollama launch <client> --model inkling-2-mini` wires the clients Ollama knows.

## Conventions

- Before recommending a model change, read the `justfile` for what is served and `ollama list` for what is on disk.
- Benchmarks: `just bench`. Throughput swings with thermal state and foreign load, so a single run ranks nothing -- alternate the configurations under test, cool down 60 s between them, and log foreign CPU per run. On 2026-11-20 a second workload cut this model from 25-28 to 9-12 tok/s.
- **Check what macOS is doing before benchmarking.** `mediaanalysisd`, `spotlightknowledged` and Spotlight importers wake up precisely when the Mac is on AC and looks idle, and they compete for the memory bandwidth this workload is bound by. `uptime` plus `ps -Ao %cpu,comm -r | head` before starting.
- Read the installed `ollama serve --help` and `ollama show` before writing anything here about what a setting accepts, never a release note.
- Thinking arrives as `reasoning`, not `reasoning_content`. `reasoning_effort: "none"` on `/v1` returned empty answers on 0.40.17-rc3, not explained; re-test after an upgrade.
- **Verify before dismissing model names.** When the user names a model/version not in training data (the clock may be months ahead), run one `WebSearch` before pushing back -- confidently-wrong is worse than uncertain.
