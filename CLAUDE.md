# CLAUDE.md

Local MLX inference on this MacBook Pro (M3 Max, 64 GB unified memory, ~400 GB/s). Path: `/Users/bstemmildt/opt/local-mlx-stack`. Single backend, OpenAI-compatible.

## Models

Serving is **exclusive**: one port, one model. `serve.sh` replaces whatever holds `:8001` instead of refusing to start, so every client config stays valid across a model switch — only the `model` id in the request changes. Two 27B models at long context do not fit 64 GB together.

- **`qwen3.8-27b`** *(default)* — `Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed` (dense 27B, 4-bit g32 with 8-bit embeddings and last 8 MLP blocks, 16-bit GDN/norms/MTP head). Text + image + video + tools, 32-33 tok/s.
- **`qwen3.8-27b-abliterated`** — `PocketAiHub/Qwen3.8-27B-Abliterated-MTPLX-Optimized-Speed`. Refusal-direction projection over 80 language residual tensors, vision tower untouched, MTP head preserved. Its `mtplx_runtime.json` names `recipe_origin` as the build above, so the quantization layout and size match; measured 34-36 tok/s against the other's 32-33.

## Serving

- `scripts/models.sh` is the registry: served id -> repo and sampling, plus the shared `PORT` and `PROFILE`. `PORT` is shared because serving is exclusive; the justfile sources the registry rather than repeating the number.
- `scripts/serve.sh` runs `mtplx quickstart` with that preset. Justfile: `serve | bench | pull | status | models | stop | doctor`.
- MTPLX's model cache is `~/.mtplx/models`; `mtplx pull` writes `Org--Repo` there and `pull.sh` symlinks the short served id onto it.
- The verified-native tier needs `mtp.safetensors` + `mtplx_runtime.json` co-located with the model. Running process pattern is `mtplx.server.openai`.

## Why this shape (2026-08-14 single-backend migration)

- Dropped oMLX and `qwen3.6-35b` (MoE A3B, ~92 tok/s) on the user's call: quality per token over bulk throughput. The cost is real and not recoverable here — MTPLX rejects `qwen3_5_moe`, and a MoE with 3B active has too little verify-cost to amortize speculative drafting, so there is no fast lane left.
- With one backend the repo stopped needing a backend dispatch, two symlink dirs, per-model env files, and a Python layer for `hf download`. MTPLX covers pull, models, status, stop, inspect, and client wiring natively; what remains here is the sampling preset, the serve invocation, and a tok/s bench.
- Qwen3.8 has no 35B-class sibling — the MoE is 2.4T-A95B and does not fit — so nothing changed that decision when 3.8 landed.
- Quality tradeoff on the 4-bit repack vs the prior unsloth 6-bit dynamic: small for instruction-following and coding, more visible on math and long context.

## Why MTPLX (checked 2026-08-16)

Not preference — lack of competition. On Metal, llama.cpp's MTP is a net loss at every setting ([#23752](https://github.com/ggml-org/llama.cpp/issues/23752): -11% to -24%; the per-step Metal kernel launch costs more than the speculation saves). mlx-lm's native MTP is [PR #990](https://github.com/ml-explore/mlx-lm/pull/990), open since March 2026, Qwen3.5/3.6 only. mlx-vlm can use `mlx-community/Qwen3.8-27B-MTP-4bit` as a draft model from the CLI, but its server has no speculative-decoding support ([#981](https://github.com/Blaizzy/mlx-vlm/issues/981), closed without a branch). MTPLX is therefore the only way to get MTP behind an OpenAI-compatible endpoint here. Re-check if PR #990 merges and picks up 3.8.

## Clients

- **Zed** `~/.config/zed/settings.json` → `language_models.openai_compatible`. Validator needs the full `capabilities` block per model.
- **pi** `~/.pi/agent/models.json` → `compat.thinkingFormat: "qwen"` enables client-side reasoning parse.
- **opencode** `~/.config/opencode/opencode.json`.
- `mtplx connect <client>` prints settings for opencode, Claude Code, Open WebUI, and Swival.

## Conventions

- Before recommending model changes, read `scripts/models.sh` for what is registered and `mtplx models` for what is on disk.
- New models: confirm `mtplx inspect <path>` returns `tier: verified` + `runtime_compatibility: native` before wiring (it refuses otherwise without `--unsafe-force-unverified`). `just doctor` checks this.
- Benchmarks: `just bench <name>`. Throughput swings several tok/s with thermal state, so a single run ranks nothing — alternate the configs under test and give the machine a cooldown between them. There is also a warmup ramp of about five runs after a server start (measured 2026-08-16: 18.6 climbing to 33.3 tok/s over seven runs). Discard the ramp before taking a median, or you will report a third less than the real number. The ramp is **MTPLX-specific**: `mlx_lm` was flat within 1 tok/s from cold on 2026-08-21, so it is warmup, not thermal.
- **Check what macOS is doing before benchmarking.** `mediaanalysisd`, `spotlightknowledged` and Spotlight importers wake up precisely when the Mac is on AC and looks idle, and they compete for the memory bandwidth this workload is bound by. A run on 2026-08-21 had to be discarded because a config collapsed from 20.4 to 10.6 tok/s mid-sequence. `uptime` plus `ps -Ao %cpu,comm -r | head` before starting; `touch <dir>/.metadata_never_index` in the model directories stops Spotlight re-indexing 20 GB of weights after every pull. Log foreign CPU per run rather than trusting a quiet start — the cost is bounded (~5% at 130% foreign CPU) but only measurable if recorded.
- MTP is worth **2.03x** here (`--mtp` vs `--no-mtp`, same weights and loader, 2026-08-21). That is the number the whole backend choice rests on; re-measure it rather than the stack-vs-stack comparison if MTPLX is ever questioned.
- Backend CLI flags drift between releases and the scripts fail closed on unknown ones. Check `mtplx quickstart --help` against `serve.sh` after a `brew upgrade`, and match process names against `pgrep -fl` rather than the command you typed. Read the installed `--help` before writing anything here about what a flag accepts; this file carried a wrong claim about `--reasoning-effort` for two days because it was written from a release note instead.
- Reasoning split: MTPLX splits `reasoning_content` server-side in streaming only; non-streaming puts thinking into `content`. SSE clients use `--reasoning-parser qwen3`.
- `reasoning_effort` lives in `scripts/models.sh` (`medium`), not in the client configs. MTPLX accepts `auto|low|medium|high|xhigh` on the flag and per request; cost measured on **2.7.1**, same prompt: `low` 1891, `medium` 2439, `xhigh` 3801 completion tokens. Not re-measured against 2.9.0.
- `--preserve-thinking auto` resolves differently per model: `scoped` for 3.6, **preserve-all** for 3.8, because that is its trained contract. Agent loops accumulate context faster on 3.8 as a result.
- `response_format: json_schema` needs `llguidance`, which the Homebrew formula omits from its `server` extra. It fails closed. `just doctor` checks it; a `brew upgrade` builds a fresh venv and drops the manual install.
- **`brew upgrade` leaks the old venv.** The formula versions the path (`var/mtplx/venv-<version>`) and `postinstall` removes only its own; `brew cleanup` never touches `var/`. By 2026-08-21 that was 24 dead venvs at 10 GB. Delete all but the current one — the `bin/mtplx` wrapper re-bootstraps a missing venv by itself, so there is no reason to keep a rollback copy.
- The SSD session bank (`~/.mtplx/session-bank`) is on by default and budgeted at `min(cap, free_disk/4)` with the cap defaulting to `100GB` — effectively unbounded here. `serve.sh` pins `--ssd-session-cache-max-size 20GB`. It had grown to 5.3 GB in five days.
- Downloads: `HF_HUB_DISABLE_XET=1` is worth setting. Measured 2026-08-21 pulling 36 GB: Xet on 702 MB/min, Xet on with `HF_XET_HIGH_PERFORMANCE=1` **387**, Xet off **2003**. Xet's chunk dedup buys nothing on a first-time model pull and costs a third of a core. `mtplx pull` runs its own downloader and stayed at ~320 MB/min regardless. Aborting and restarting a download does **not** resume: `hf download` opens fresh `.incomplete` files and re-fetches from zero.
- **Verify before dismissing model names.** When the user names a model/version not in training data (cutoff Jan 2026; the clock may be months ahead), run one `WebSearch` before pushing back — confidently-wrong is worse than uncertain. (e.g. Qwen3.8-27B released 2026-08-14, post-cutoff.)
