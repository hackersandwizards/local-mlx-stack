# Measurements

What was measured for Inkling 2 Mini on Ollama's MLX runner, and what was not. All runs on an M3 Max with 64 GB, Ollama 0.40.17-rc3, on 2026-11-20.

## Size

| | Value | How |
|---|---|---|
| On disk | 19 GB | `du` over the model store after `ollama pull`; the weights are 19.5 GB and the draft model 0.6 GB in the vendor's repository |
| Loaded | 22 GB | `ollama ps`, context 262,144 tokens, the default Ollama picked on this machine |
| Pull | 4.6 minutes | at 27 MB/s as `ollama pull` reported it |

## Throughput

Not settled. The prompt and the 300-token decode are those of `scripts/bench.sh`, thinking at the model's default `high`, one warmup request per round. Foreign CPU is the sum over every other process, in percent of one core, read before each run.

| Round | Foreign CPU | Runs | tok/s |
|---|---|---|---|
| 1, runs 1-2 | 237, 42 | 2 | 25.4, 28.0 |
| 1, run 3 | 81 | 1 | 13.6 |
| 1, runs 4-8 | 899 to 1307 | 5 | 22.2, 17.4, 10.9, 11.8, 12.0 |
| 2 | 302 to 1460 | 8 | 11.2, 11.5, 9.8, 11.8, 9.2, 9.3, 8.9, 15.8 (median 10.5) |

Another workload on the machine took 9 to 14 cores from the fourth run on. The slowdown follows that load, but run 3 was slow at low load too, so the cause is not shown. Two quiet runs rank nothing.

The speculative decoder was on in every run: the draft model loaded, and per request 23 to 42% of the drafted tokens were accepted, with 1.5 to 4.3 tokens drafted per step.

## Against the previous setup

Until 2026-11-20 this repository served two Qwen packs through MTPLX. Their figures, measured here on 2026-10-11 with MTPLX 2.12.2 by alternating both over three rounds of eight runs, foreign CPU 41 to 297%:

| Model | Disk | tok/s |
|---|---|---|
| Qwen3.8 27B, 8-bit, MTPLX Optimized-Quality | 30.0 GB | 27 to 28 |
| Qwen3.6 35B-A3B, 4-bit, MTPLX Optimized-Speed | 21.0 GB | 94 to 100 |

No run alternated Inkling 2 Mini with either, so there is no ranking. The switch was made on the vendor's benchmark table and on the smaller footprint, with throughput assumed to be at least that of the 27B. A valid comparison alternates the configurations, cools down 60 s between them and records foreign CPU per run; the method and both old setups are in this file's history.
