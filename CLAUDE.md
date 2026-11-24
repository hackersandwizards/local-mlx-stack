# CLAUDE.md

Local MLX inference on this MacBook Pro (M3 Max, 64 GB unified memory, ~400 GB/s). Path: `/Users/bstemmildt/dev/hackersandwizards/internal/local-mlx-stack`. Single backend (MTPLX), single model, OpenAI-compatible.

## Model

**`inkling-2-mini`** -- `Youssofal/Inkling-2-Mini-MTPLX-Optimized-Speed` (Thinking Machines' Inkling 2 Mini: MoE 26.4B, 3.4B active, middle 12 layers looped three times; official NVFP4 experts and embedding, 8-bit attention and output head, full vision tower, native DSpark draft head; 17.2 GB on disk, ~18.3 GB peak resident, 716,800-token context window on 64 GB). Text, image and tools.

**MTPLX ignores the requested `model` id** and answers from whatever is loaded. Check `/v1/models` or the response's `model` field to verify what answered.

## Serving

- The `justfile` is the single source of truth for `MODEL`, `REPO`, `PORT` (`8001`), and `SSD_CACHE_MAX` (`20GB`). Recipes: `serve | pull | bench | status | stop | doctor`.
- `just serve` runs `mtplx quickstart` in the foreground. MTPLX resolves the `inkling2_loop` backend, `sustained` profile, sampler (`temperature=1.0, top_p=1.0, top_k=0`), draft depth (`3`), reasoning parser (`qwen3`, default effort `high`), native tool prompt mode, and tokenizer template automatically.
- Model store: `~/.mtplx/models` (`just pull` touches `.metadata_never_index` to keep Spotlight out).
- Persistent SSD SessionBank cache: `~/.mtplx/session-bank`, capped at `20GB` via `--ssd-session-cache-max-size`.
- MTPLX is installed by mise from `~/.config/mise/config.toml` as `"pypi:mtplx" = { version = "latest", extras = "server" }` (includes `llguidance` for `response_format: json_schema`).

## Why this shape (2026-11-24, back to MTPLX for Inkling 2 Mini)

- On 2026-11-20 this repo briefly moved to Ollama `0.40.17-rc3` because no other Mac runtime loaded Inkling 2 Mini with its DSpark drafter on launch day.
- By 2026-11-24 MTPLX `2.13.3` shipped native Inkling 2 Mini Metal kernels, copy-lane speculation, and persistent SSD prompt caching (SessionBank). Ollama and its 19 GB store were removed in favor of this minimal single-model MTPLX setup.
- `Optimized-Speed` (17.2 GB) was chosen over `Optimized-Quality` (20.2 GB) and `Bare-Speed` (16.0 GB): on Youssofal's model card it has no measurable loss penalty against the original weights (`-0.0007 ± 0.0031` nats, 96.5% top-1 agreement) while cutting RAM by 3 GB and raising decode speed (+14% average, +21% long answers on M5 Max).
- Because MTPLX 2.13.3 carries Inkling's own sampler, template, reasoning parser, and pack resolution natively, no `models.sh`, `serve.sh`, `pull.sh`, or symlinks are needed.

## Clients

- **Zed** `~/.config/zed/settings.json` -> `language_models.openai_compatible.local-mlx` (`max_tokens: 716800`, full `capabilities` block).
- **pi** `~/.pi/agent/models.json` -> `providers.local-mlx` with `compat.thinkingFormat: "qwen"` (sends `enable_thinking` + `reasoning_effort`), `headers["x-mtplx-client"]: "pi"`, and `~/.pi/agent/extensions/mtplx-session-headers.ts` (attaches `x-mtplx-session-id` for SSD SessionBank reuse across restarts).
- **opencode** `~/.config/opencode/opencode.json` -> `provider.local-mlx` with `modalities` (text + image), `tool_call: true`, `headers["x-mtplx-client"]: "opencode"`, and Inkling effort `variants`.

## Conventions

- Before recommending a model or backend change, read the `justfile` for what is configured and `mtplx models` for what is on disk.
- Verify any new pack with `just doctor` (`mtplx inspect` must report `tier: verified` and `runtime_compatibility: native`).
- Backend CLI flags drift between MTPLX releases. Read the installed `mtplx quickstart --help` before writing anything here about what a flag accepts, never a release note.
- Benchmarks: `just bench`. Check `uptime` and `ps -Ao %cpu,comm -r | head` first (`mediaanalysisd` / `spotlightknowledged` compete for memory bandwidth), alternate configurations with a 60 s cooldown, and log foreign CPU per run.
- Thinking arrives in `reasoning_content`. `enable_thinking: false` turns thinking off completely; `reasoning_effort: "none"` still emits short reasoning tokens on Inkling 2 Mini.
- **Verify before dismissing model names.** When the user names a model/version not in training data (the clock may be months ahead), run one web search before pushing back.
