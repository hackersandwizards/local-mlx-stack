# local-mlx-stack

One OpenAI-compatible server on loopback: [MTPLX](https://github.com/youssofal/MTPLX) serving [Inkling 2 Mini](https://huggingface.co/Youssofal/Inkling-2-Mini-MTPLX-Optimized-Speed) (`Optimized-Speed`) on Apple Silicon, with native speculative decoding and persistent SSD prompt caching. It is one person's local setup, published as it is, with every figure measured on an M3 Max with 64 GB.

| You want | Go to |
| --- | --- |
| Run the local model | [Requirements and first run](#requirements-and-first-run) |
| Point a client at it | [Endpoint](#endpoint) |
| Know what was measured, and what was not | [docs/measurements.md](docs/measurements.md) |
| Change thinking, context or SSD cache | [docs/configuration.md](docs/configuration.md) |
| Fix an error | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Change this repository | [CLAUDE.md](CLAUDE.md) |

## Requirements and first run

An Apple Silicon Mac with 32 GB of memory or more: the pack holds ~18 GB once loaded. You also need [`just`](https://github.com/casey/just), `jq`, and MTPLX 2.13.3 or newer with `llguidance`, installed by [mise](https://mise.jdx.dev) from this entry in `~/.config/mise/config.toml`:

```toml
[tools."pypi:mtplx"]
version = "latest"
extras = "server"
```

Then:

```bash
git clone https://github.com/hackersandwizards/local-mlx-stack.git
cd local-mlx-stack
mise install
just pull
just doctor
just serve
```

`just pull` fetches the pack (17.2 GB) into `~/.mtplx/models`. `just doctor` verifies `mtplx`, `llguidance`, and the pack's runtime contract. `just serve` runs the server in the foreground at `http://127.0.0.1:8001/v1`; Ctrl-C stops it. When it works, `curl -s http://127.0.0.1:8001/v1/models` names `inkling-2-mini`.

## Model

`inkling-2-mini`: `Youssofal/Inkling-2-Mini-MTPLX-Optimized-Speed` — Thinking Machines' Inkling 2 Mini (26.4B MoE, 3.4B active, middle 12 layers looped three times), keeping the official NVFP4 experts and embedding with 8-bit attention and output head, full vision tower, and the model's own DSpark draft head (17.2 GB on disk). It takes text, images and tools, and thinks before it answers.

## Daily use

- `just serve`: serve in the foreground, Ctrl-C to stop.
- `just pull`: fetch or update the pack into `~/.mtplx/models`.
- `just doctor`: check `mtplx`, `llguidance`, and the pack's runtime contract.
- `just bench`: end-to-end tok/s for one 300-token answer.
- `just status`: MTPLX status, cached models, and what answers on :8001.
- `just stop`: stop the MTPLX daemon on :8001.

MTPLX owns the model store (`~/.mtplx/models`), the persistent SSD prompt cache (`~/.mtplx/session-bank`), template, sampler and draft depth.

## Endpoint

```
http://127.0.0.1:8001/v1  -> inkling-2-mini
```

**MTPLX ignores the requested model id** and answers from the loaded pack. Check `curl -s http://127.0.0.1:8001/v1/models` to confirm what is loaded. Thinking arrives in `reasoning_content`.

## Documentation

- [Measurements](docs/measurements.md): disk, memory, and throughput readings on M3 Max.
- [Configuration](docs/configuration.md): what MTPLX owns, thinking levels, SSD cache, and client configs.
- [Troubleshooting](docs/troubleshooting.md): common errors and freeing disk.

## Work on it

The recipes live in the `justfile`, the benchmark in `scripts/bench.sh`. `just doctor` plus one request is the check after a change: there is no test suite and no release. Rules and reasoning: [CLAUDE.md](CLAUDE.md).

## License

[PolyForm Strict 1.0.0](LICENSE), copyright hackers&wizards GmbH. The name hackers&wizards and its logos are not licensed.
