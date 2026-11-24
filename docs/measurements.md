# Measurements

What was measured for Inkling 2 Mini on this MacBook Pro (M3 Max, 64 GB unified memory), and what was not.

## Current setup (2026-11-24, MTPLX 2.13.3, Optimized-Speed)

Pack: `Youssofal/Inkling-2-Mini-MTPLX-Optimized-Speed`, profile `sustained`, draft depth `3`.

| Metric | Value | How |
| --- | --- | --- |
| On disk | 17.2 GB | `mtplx models` |
| Resident / peak memory | 16.0 GiB weights / 18.3 GB peak | `mtplx_stats.peak_memory_bytes` on short requests |
| Context window | 716,800 tokens | `/v1/models` (`context_length`, machine-bound on 64 GiB) |
| Model load time | 42.6 s | server startup log |

### Initial throughput readings (not a quiet benchmark)

Three runs with `scripts/bench.sh` (300 completion tokens, default thinking `high`) while OrbStack and `rspec` held ~200% foreign CPU on the machine:

| Run | Foreign CPU | End-to-end (`scripts/bench.sh`) | Decode (`mtplx_stats.decode_tok_s`) |
| --- | --- | --- | --- |
| 1 (alongside smoke requests) | ~200% | 66.8 tok/s (300 tok in 4.49 s) | ~80–81 tok/s on short smoke requests |
| 2 (solo) | 206% | 61.1 tok/s (300 tok in 4.91 s) | — |
| 3 (solo) | ~200% | 64.6 tok/s (300 tok in 4.64 s) | — |

A quiet multi-run measurement (low foreign CPU, 60 s cooldown) has not been run yet.

## Historical reference

Previous setups measured on the same M3 Max:

| Date | Stack & model | Disk | Measured tok/s | Notes |
| --- | --- | --- | --- | --- |
| 2026-11-20 | Ollama `0.40.17-rc3` (MLX), `inkling-2-mini` (NVFP4/MXFP8) | 19 GB | 25.4, 28.0 (2 quiet runs); 8.9–22.2 under heavy load | 22 GB loaded, 262,144 context |
| 2026-10-11 | MTPLX `2.12.2` (`turbo`), `qwen3.8-27b` Optimized-Quality (8-bit) | 30.0 GB | 27–28 | 3 rounds × 8 alternating runs, foreign CPU 41–297% |
| 2026-10-11 | MTPLX `2.12.2` (`turbo`), `qwen3.6-35b` Optimized-Speed (4-bit) | 21.0 GB | 94–100 | Same alternating run |
