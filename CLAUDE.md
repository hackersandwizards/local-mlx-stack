# CLAUDE.md

Local MLX inference on this MacBook Pro (M3 Max, 64 GB unified memory, ~400 GB/s). Path: `/Users/bstemmildt/opt/local-mlx-stack`. Single backend, OpenAI-compatible.

## Model

- **`qwen3.6-27b`** *(default)* — `Youssofal/Qwen3.6-27B-MTPLX-Optimized-Speed` (dense 27B, 4-bit main + INT4 MTP sidecar), MTPLX on `:8001`. Text + image + video + tools, ~40 tok/s.
- **`qwen3.8-27b`** — registered on `:8002`, weights pending. Same `qwen3_5` architecture as the 3.6-27B, so it is a checkpoint swap, not a runtime change. Replaces the 3.6 once it is benched.

## Serving

- `scripts/models.sh` is the registry: served id -> repo, port, sampling, plus the shared `PROFILE`.
- `scripts/serve.sh` runs `mtplx quickstart` with that preset. Justfile: `serve | bench | pull | status | models | stop | doctor`.
- MTPLX's model cache is `~/.mtplx/models`; `mtplx pull` writes `Org--Repo` there and `pull.sh` symlinks the short served id onto it.
- The verified-native tier needs `mtp.safetensors` + `mtplx_runtime.json` co-located with the model. Running process pattern is `mtplx.server.openai`.

## Why this shape (2026-08-14 single-backend migration)

- Dropped oMLX and `qwen3.6-35b` (MoE A3B, ~92 tok/s) on the user's call: quality per token over bulk throughput. The cost is real and not recoverable here — MTPLX rejects `qwen3_5_moe`, and a MoE with 3B active has too little verify-cost to amortize speculative drafting, so there is no fast lane left.
- With one backend the repo stopped needing a backend dispatch, two symlink dirs, per-model env files, and a Python layer for `hf download`. MTPLX covers pull, models, status, stop, inspect, and client wiring natively; what remains here is the sampling preset, the serve invocation, and a tok/s bench.
- Qwen3.8 has no 35B-class sibling — the MoE is 2.4T-A95B and does not fit — so nothing changes that decision when 3.8 lands.
- Quality tradeoff on the 4-bit repack vs the prior unsloth 6-bit dynamic: small for instruction-following and coding, more visible on math and long context.

## Clients

- **Zed** `~/.config/zed/settings.json` → `language_models.openai_compatible`. Validator needs the full `capabilities` block per model.
- **pi** `~/.pi/agent/models.json` → `compat.thinkingFormat: "qwen"` enables client-side reasoning parse.
- **opencode** `~/.config/opencode/opencode.json`.
- `mtplx connect <client>` prints settings for opencode, Claude Code, Open WebUI, and Swival.

## Conventions

- Before recommending model changes, read `scripts/models.sh` for what is registered and `mtplx models` for what is on disk.
- New models: confirm `mtplx inspect <path>` returns `tier: verified` + `runtime_compatibility: native` before wiring (it refuses otherwise without `--unsafe-force-unverified`). `just doctor` checks this.
- Benchmarks: `just bench <name>`. Throughput swings several tok/s with thermal state, so a single run ranks nothing — alternate the configs under test and give the machine a cooldown between them.
- Backend CLI flags drift between releases and the scripts fail closed on unknown ones. Check `mtplx quickstart --help` against `serve.sh` after a `brew upgrade`, and match process names against `pgrep -fl` rather than the command you typed.
- Reasoning split: MTPLX splits `reasoning_content` server-side in streaming only; non-streaming puts thinking into `content`. SSE clients use `--reasoning-parser qwen3`.
- Qwen3.8 adds `reasoning_effort` with `xhigh` as the default, which is expensive on a dense 27B. MTPLX 2.6.0's `--reasoning-effort` accepts only `auto|low|medium|high`. Set it per client rather than inheriting the default.
- **Verify before dismissing model names.** When the user names a model/version not in training data (cutoff Jan 2026; the clock may be months ahead), run one `WebSearch` before pushing back — confidently-wrong is worse than uncertain. (e.g. Qwen3.8-27B released 2026-08-14, post-cutoff.)
