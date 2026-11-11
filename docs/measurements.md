# Measurements

How the throughput figures in the README were measured, and the profile and stack choices they rest on. All runs on an M3 Max with 64 GB.

## Models

| Name | Repo | Port | Disk | tok/s¹ | Notes |
|---|---|---|---|---|---|
| `qwen3.8-27b` *(default)* | `Youssofal/Qwen3.8-27B-MTPLX-Optimized-Quality` | 8001 | 30.0 GB | 27-28 | Dense 27B, 8-bit g64 throughout, 16-bit GDN/norms/MTP head. 32.7 GB peak per the model card. Text + image + video + tools. |
| `qwen3.6-35b` | `Youssofal/Qwen3.6-35B-A3B-MTPLX-Optimized-Speed` | 8001 | 21.0 GB | 94-100² | MoE, 35B with 3B active, 4-bit g64, MTP. The fast lane: about 3.6x the throughput of the model above, from the previous Qwen generation. |

¹ M3 Max 64 GB, 300-token decode under `turbo`, MTPLX 2.12.2, measured 2026-10-11 by alternating this pack with `Optimized-Speed` (4-bit, 21.3 GB) over four rounds, eight runs per server start, 60 s cooldown, foreign CPU 65-297% throughout. Medians of rounds 2-4: Quality 27.3 / 28.0 / 27.8, Speed 35.0 / 33.2 / 34.8 -- Quality costs about 20% throughput. Round 1 is excluded and not explained: on its first start after the download Quality ran at 12.7-16.1 and Speed at 25.0-31.3. Quality per token was not measured here; the model card gives 99.3% top-1 agreement with bf16 for Quality against 96.0% for Speed (KL 0.0005 against 0.012).

² Same method, measured 2026-10-11 by alternating with `qwen3.8-27b` over three rounds of eight runs, foreign CPU 41-133%. Medians per round: `qwen3.6-35b` 98.3 / 94.2 / 100.4, `qwen3.8-27b` 26.4 / 26.9 / 27.6. No run of the 35B fell below 90.0. Its quality against the 27B is unmeasured here.

The warmup ramp recorded on 2026-08-16 (18.6, 24.1, 28.6, 28.9, 31.8, 33.3, 32.4 over seven runs) did not appear on 2.12.2 in rounds 2-4: the first counted run after `bench.sh`'s one-token warmup was already at the plateau. Still read the first runs before taking a median.

The other builds of the same checkpoint: `Optimized-Speed` (4-bit g32 mixed, 21.3 GB, the default here until 2026-10-11) and `Bare-Speed` (16 GB, unmeasured here).

## Profile

`PROFILE` in `scripts/models.sh`, currently `turbo`, shared by both models. Until 2026-08-14 this was `performance-cold`, which MTPLX itself describes as "not recommended for long context"; from then until 2026-08-21 it was `sustained`.

Measured on the 3.8 `Optimized-Speed` pack on 2026-08-21 as part of the stack comparison below -- same run, same alternation, 300-token decode, median of ten:

| Profile | tok/s | vs `sustained` |
|---|---|---|
| `sustained` | 27.73 | -- |
| `turbo` | 33.02 | **+19%** |

The 3.6 measurement from 2026-08-14 put this gap at 5-10% (`sustained` 33.2/31.3, `turbo` 35.3/34.3 across a short and a long lane). On the 3.8 it is roughly twice that, so the profile matters more here than the old number suggested.

`turbo` is on as of 2026-08-21, a deliberate trade: its 4-bit speculative-verify kernels are argmax- and sampler-distribution-validated but **not bit-exact against stock**, so this buys throughput with quality per token -- the opposite of the axis the 2026-08-14 migration chose. No measurement settles that; it is a judgement call, and it was made knowingly. Whether those kernels engage on the 8-bit pack is unverified; `turbo` against `sustained` is unmeasured on it.

Its compiled verify engages up to **32,768** tokens of context and falls back to the eager path above that, so most agent sessions stay inside it. (This README said 12,288 until 2026-08-21; that was MTPLX 2.7.1. `mtplx status` prints the current fence.) `exact` sits on the other side of the same axis and is unmeasured here.

Single runs rank nothing: absolute throughput moved by more than 50% across sessions on identical configs, driven by thermal state and how warm the session bank was. The numbers above are medians of ten across two alternating rounds -- see below for the method.

## Stack comparison

Is MLX or MTPLX the faster way to run this model here? Measured 2026-08-21 on the `Optimized-Speed` pack, M3 Max 64 GB on AC power. Five configurations alternating over two rounds; per server start five warmup runs discarded and five counted; 300-token decode, 60 s cooldown. Sampling forced identical everywhere (`1.0 / 0.95 / 20`) -- `mlx_lm.server` defaults to `0.0 / 1.0 / 0` and would otherwise measure something else entirely. Session bank cleared beforehand, since `mlx_lm` has no equivalent and a warm one flatters MTPLX.

| Stack | Model | Size | tok/s | vs AR baseline |
|---|---|---|---|---|
| MTPLX, `turbo`, MTP | own build, 4-bit g32 mixed | 21.3 GB | **33.02** | 2.03x |
| MTPLX, `sustained`, MTP | own build, 4-bit g32 mixed | 21.3 GB | 27.73 | 1.70x |
| `mlx_lm` | orca abliterated, 4-bit g64 | 15 GB | 20.65 | 1.27x |
| MTPLX, `turbo`, **no MTP** | own build, 4-bit g32 mixed | 21.3 GB | 16.27 | 1.00x |
| `mlx_lm` | orca abliterated, 6-bit g64 | 21 GB | 13.38 | 0.82x |

Three separate conclusions, and only the first is causal:

1. **MTP speculative decoding is worth 2.03x.** Same loader, same weights, same profile -- `--mtp` against `--no-mtp` is the only controlled comparison here, because it changes exactly one variable. This is the number that justifies the whole backend choice. For reference, PocketAiHub measured 2.35x for the same recipe on an M5 Max.
2. **MTPLX beats `mlx_lm` by 2.47x at equal size**, 33.02 against 13.38 for the 21 GB pair. But that comparison changes backend, quantization layout *and* MTP at once, so it ranks stacks, not backends. `mlx_lm` has no MTP path for Qwen3.8 at all (see "Why MTPLX" in `CLAUDE.md`), so this is the honest practical question -- just not a clean experiment.
3. **Quantization size dominates on a memory-bound machine.** orca 4-bit (15 GB) runs 1.54x the 6-bit (21 GB) build of the same weights. Bandwidth, not arithmetic, is the constraint.

Caveats worth carrying: macOS background jobs (`mediaanalysisd`, Spotlight) claimed 69-161% of a core across the run and would not stay quiet. Their cost is bounded, though -- configuration A ran once at 7% foreign CPU and once at 132% and lost 4.8% between them, against gaps of 60-147% being measured. Round 1 and round 2 agree within ~5% for every configuration, which is why these medians are usable at all.

`mlx_lm` shows no warmup ramp: five consecutive runs sat within 1 tok/s of each other from cold. The 18.6 to 33.3 climb recorded under Models is MTPLX-specific, not thermal.
