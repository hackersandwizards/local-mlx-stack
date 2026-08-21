# local-mlx-stack

One OpenAI-compatible server on loopback: [MTPLX](https://github.com/youssofal/MTPLX) with native MTP speculative decoding, serving a dense Qwen 27B on Apple Silicon. Two models share the port -- serving is exclusive, `just serve <name>` replaces whatever is running.

## Models

| Name | Repo | Port | Disk | tok/s¹ | Notes |
|---|---|---|---|---|---|
| `qwen3.8-27b` *(default)* | `Youssofal/Qwen3.8-27B-MTPLX-Optimized-Speed` | 8001 | 21.3 GB | 33-37 | Dense 27B, 4-bit g32 with 8-bit embeddings and last 8 MLP blocks, 16-bit GDN/norms/MTP head. Text + image + video + tools, verified against the running server. |
| `qwen3.8-27b-abliterated` | `PocketAiHub/Qwen3.8-27B-Abliterated-MTPLX-Optimized-Speed` | 8001 | 21.3 GB | 34-36 | Refusal direction projected out of 80 language residual tensors; vision tower and MTP head untouched. Its `mtplx_runtime.json` names `recipe_origin` as the build above, so the quantization layout is identical and throughput should match. |

Both share the port: serving is exclusive, `just serve <name>` replaces whatever is running.

¹ M3 Max 64 GB, `just bench`, 300-token decode, both measured under `turbo` on 2026-08-21. The two builds are indistinguishable, as the shared quantization recipe predicts -- do not read the ranges as a difference. The earlier 32-33 for `qwen3.8-27b` was measured under `sustained` and is not comparable. **The first runs are not the number.** Seven consecutive runs with 45 s cooldowns on 2026-08-16 gave 18.6, 24.1, 28.6, 28.9, 31.8, 33.3, 32.4 -- a monotone warmup ramp that only plateaus after ~5 runs. Stopping at three would have understated it by a third. Discard the ramp, then take a median.

The other two builds of the same checkpoint, if the tradeoff is ever revisited: `Bare-Speed` (16 GB) and `Optimized-Quality` (29.4 GB download, 32.7 GB peak, 8-bit g64 throughout, KL 0.00105 to the original). Quality fits in 64 GB but doubles the weight bandwidth on a memory-bound M3 Max and shrinks the session bank; it is unmeasured here.

## Daily use

```bash
just serve [NAME]   # foreground, Ctrl-C to stop
just bench [NAME]   # end-to-end tok/s against the model's port
just pull [NAME]    # mtplx pull + symlink to the short served id
just status         # mtplx status
just models         # mtplx models
just stop           # stops whatever holds the port
just doctor         # contract check per model, then mtplx status
```

## What this repo owns

MTPLX owns the model cache, downloads, health, and client wiring. Calling it directly is usually the right move:

| Task | Command |
|---|---|
| Download a model | `mtplx pull <hf-repo>` |
| List the cache | `mtplx models` |
| Compatibility check | `mtplx inspect <path>` |
| Wire up a client | `mtplx connect opencode` (also Claude Code, Open WebUI, Swival) |
| Stop a daemon | `mtplx stop --port <p>` |
| Find the fastest draft depth | `mtplx tune` |

What is left here is what MTPLX does not persist: the per-model sampling preset, the exact serve invocation, and a benchmark that reports decode throughput rather than draft depth. `scripts/models.sh` holds the whole registry.

## Sampling

Qwen publishes a different preset per release, so it belongs next to the model and lives in `scripts/models.sh`. MTPLX persists none of it: `mtplx settings set` only reaches a running daemon, and `~/.mtplx/config.toml` covers the default model and profile, not sampling.

- `qwen3.8-27b`: `temp 1.0`, `top_p 0.95`, `top_k 20` -- the official sampler from the MTPLX 2.7.0 release notes.

The preset does not pin `presence_penalty`; MTPLX has `--default-presence-penalty` but the thinking preset sets it to 0 anyway. Clients override per request.

`REASONING_EFFORT` sits in the same registry entry. The model card defaults to `xhigh`, which is expensive on a dense 27B; MTPLX's own coding default is `medium`, so `serve.sh` pins that rather than inheriting. Measured per request on 2026-08-16, same prompt: `low` 1891, `medium` 2439, `xhigh` 3801 completion tokens. Clients override per request via `reasoning_effort`.

## Profile

`PROFILE` in `scripts/models.sh`, currently `turbo`, shared by both models. Until 2026-08-14 this was `performance-cold`, which MTPLX itself describes as "not recommended for long context"; from then until 2026-08-21 it was `sustained`.

Measured on the 3.8 on 2026-08-21 as part of the stack comparison below -- same run, same alternation, 300-token decode, median of ten:

| Profile | tok/s | vs `sustained` |
|---|---|---|
| `sustained` | 27.73 | -- |
| `turbo` | 33.02 | **+19%** |

The 3.6 measurement from 2026-08-14 put this gap at 5-10% (`sustained` 33.2/31.3, `turbo` 35.3/34.3 across a short and a long lane). On the 3.8 it is roughly twice that, so the profile matters more here than the old number suggested.

`turbo` is on as of 2026-08-21, a deliberate trade: its 4-bit speculative-verify kernels are argmax- and sampler-distribution-validated but **not bit-exact against stock**, so this buys throughput with quality per token -- the opposite of the axis the 2026-08-14 migration chose. No measurement settles that; it is a judgement call, and it was made knowingly.

Its compiled verify engages up to **32,768** tokens of context and falls back to the eager path above that, so most agent sessions stay inside it. (This README said 12,288 until 2026-08-21; that was MTPLX 2.7.1. `mtplx status` prints the current fence.) `exact` sits on the other side of the same axis and is unmeasured here.

Single runs rank nothing: absolute throughput moved by more than 50% across sessions on identical configs, driven by thermal state and how warm the session bank was. The numbers above are medians of ten across two alternating rounds -- see below for the method.

## Stack comparison

Is MLX or MTPLX the faster way to run this model here? Measured 2026-08-21, M3 Max 64 GB on AC power. Five configurations alternating over two rounds; per server start five warmup runs discarded and five counted; 300-token decode, 60 s cooldown. Sampling forced identical everywhere (`1.0 / 0.95 / 20`) -- `mlx_lm.server` defaults to `0.0 / 1.0 / 0` and would otherwise measure something else entirely. Session bank cleared beforehand, since `mlx_lm` has no equivalent and a warm one flatters MTPLX.

| Stack | Model | Size | tok/s | vs AR baseline |
|---|---|---|---|---|
| MTPLX, `turbo`, MTP | own build, 4-bit g32 mixed | 21.3 GB | **33.02** | 2.03x |
| MTPLX, `sustained`, MTP | own build, 4-bit g32 mixed | 21.3 GB | 27.73 | 1.70x |
| `mlx_lm` | orca abliterated, 4-bit g64 | 15 GB | 20.65 | 1.27x |
| MTPLX, `turbo`, **no MTP** | own build, 4-bit g32 mixed | 21.3 GB | 16.27 | 1.00x |
| `mlx_lm` | orca abliterated, 6-bit g64 | 21 GB | 13.38 | 0.82x |

Three separate conclusions, and only the first is causal:

1. **MTP speculative decoding is worth 2.03x.** Same loader, same weights, same profile -- `--mtp` against `--no-mtp` is the only controlled comparison here, because it changes exactly one variable. This is the number that justifies the whole backend choice. For reference, PocketAiHub measured 2.35x for the same recipe on an M5 Max.
2. **MTPLX beats `mlx_lm` by 2.47x at equal size**, 33.02 against 13.38 for the 21 GB pair. But that comparison changes backend, quantization layout *and* MTP at once, so it ranks stacks, not backends. `mlx_lm` has no MTP path for Qwen3.8 at all (see the note on MTPLX above), so this is the honest practical question -- just not a clean experiment.
3. **Quantization size dominates on a memory-bound machine.** orca 4-bit (15 GB) runs 1.54x the 6-bit (21 GB) build of the same weights. Bandwidth, not arithmetic, is the constraint.

Caveats worth carrying: macOS background jobs (`mediaanalysisd`, Spotlight) claimed 69-161% of a core across the run and would not stay quiet. Their cost is bounded, though -- configuration A ran once at 7% foreign CPU and once at 132% and lost 4.8% between them, against gaps of 60-147% being measured. Round 1 and round 2 agree within ~5% for every configuration, which is why these medians are usable at all.

`mlx_lm` shows no warmup ramp: five consecutive runs sat within 1 tok/s of each other from cold. The 18.6 to 33.3 climb documented under `just bench` is MTPLX-specific, not thermal.

## Endpoints

```
http://127.0.0.1:8001/v1  -> qwen3.8-27b | qwen3.8-27b-abliterated
```

One endpoint, one model at a time. Both ids are registered in every client, so switching means `just serve <name>` plus picking the other id in the client -- no config edit.

**MTPLX does not check the requested id.** Ask for `qwen3.8-27b-abliterated` while the base model is loaded and you get an answer from the base model, no error and no warning. The response's own `model` field reports what actually served it, and `curl -s :8001/v1/models` names the loaded one -- check there, not in the client's dropdown, whenever it matters which weights answered.

Clients are configured in `~/.config/zed/settings.json`, `~/.pi/agent/models.json`, and `~/.config/opencode/opencode.json`. `mtplx connect <client>` prints the settings for the ones it knows.

## Troubleshooting

- `:8001 held by something MTPLX cannot stop`: `serve.sh` already tried to replace the holder and waited 30 s, so this is not another MTPLX daemon. The message prints the `lsof` output naming the process.
- `mtplx missing`: `brew install youssofal/mtplx/mtplx`.
- Model not pulled: `just pull <name>`. A placeholder repo without weight shards fails there, not at serve time.
- `pull failed: [Errno 54] Connection reset by peer`: transient, not a blocked network. Rerun `just pull` -- it resumes from the `.incomplete` shard rather than restarting.
- `response_format: json_schema` returns `requires the optional llguidance dependency`: the Homebrew formula installs the `server` extra without `llguidance`. It fails closed rather than returning unconstrained output. Fix with `/opt/homebrew/var/mtplx/venv-<version>/bin/pip install llguidance`; this does not survive `brew upgrade`, so `just doctor` checks it.
- Reasoning shows up in `content` instead of `reasoning_content`: that is the non-streaming path. SSE clients get the split via `--reasoning-parser qwen3`.
- Freeing disk: `mtplx models` for sizes, then remove the directory under `~/.mtplx/models`. Space does not return immediately -- hourly Time Machine local snapshots pin the deleted blocks for about a day. `tmutil listlocalsnapshots /` shows them.
