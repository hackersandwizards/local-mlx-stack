# local-mlx-stack

One OpenAI-compatible server on loopback: [Ollama](https://ollama.com) with its MLX runner, serving [Inkling 2 Mini](https://huggingface.co/thinkingmachines/Inkling-2-Mini) on Apple Silicon, with the model's own draft model for speculative decoding. It is one person's local setup, published as it is, with every figure measured on an M3 Max with 64 GB.

| You want | Go to |
| --- | --- |
| Run a local model | [Requirements and first run](#requirements-and-first-run) |
| Point a client at it | [Endpoint](#endpoint) |
| Know what was measured, and what was not | [docs/measurements.md](docs/measurements.md) |
| Change thinking, context or memory use | [docs/configuration.md](docs/configuration.md) |
| Fix an error | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Change this repository | [CLAUDE.md](CLAUDE.md) |

## Requirements and first run

An Apple Silicon Mac with 32 GB of memory or more: the model holds 22 GB once loaded. You also need [`just`](https://github.com/casey/just), `jq`, and Ollama 0.40.17 or newer, installed by [mise](https://mise.jdx.dev) from this entry in `~/.config/mise/config.toml`:

```toml
[tools]
ollama = "0.40.17-rc3"
```

On 2026-11-20 the release that runs this model is a release candidate, which mise installs only when the entry names it exactly. Once 0.40.17 is stable, `"latest"` does.

Then:

```bash
git clone https://github.com/hackersandwizards/local-mlx-stack.git
cd local-mlx-stack
mise install
just serve
```

`just serve` runs the server in the foreground at `http://127.0.0.1:8001/v1`; Ctrl-C stops it. In a second terminal, `just pull` fetches the model (19 GB) through the running server. When it works, `curl -s http://127.0.0.1:8001/v1/models` names `inkling-2-mini:latest`.

## Model

`inkling-2-mini`: Thinking Machines' Inkling 2 Mini, a mixture-of-experts model with 26.4B parameters, of which 3.4B are active per token. Its middle 12 layers run three times, which the vendor counts as 5.4B effective. Ollama loads the checkpoint as released, in NVFP4 and MXFP8, so nothing is quantized here. It takes text, images and tools, and thinks before it answers.

It was chosen on 2026-11-20 on the vendor's benchmarks and replaced two Qwen packs served by MTPLX. Its throughput against them is not settled: [docs/measurements.md](docs/measurements.md) has the runs.

## Daily use

- `just serve`: serve in the foreground, Ctrl-C to stop.
- `just pull`: fetch or update the model; needs the server running.
- `just bench`: end-to-end tok/s for one 300-token answer.
- `just status`: what is loaded, how much memory it holds, and until when.
- `just stop`: unload the model and free its memory; the server keeps running.

Ollama loads the model on the first request and unloads it after five idle minutes. It owns the model store (`~/.ollama/models`), downloads and client wiring; call `ollama` directly for those, with `OLLAMA_HOST=127.0.0.1:8001` set.

## Endpoint

```
http://127.0.0.1:8001/v1  -> inkling-2-mini
```

A request for any other model id is answered with `model '<id>' not found`. Thinking arrives in the `reasoning` field of a message or stream delta, not in `reasoning_content`.

## Documentation

- [Measurements](docs/measurements.md): disk, memory and the throughput runs of 2026-11-20, with what disturbed them.
- [Configuration](docs/configuration.md): what Ollama owns, thinking levels, context length, the client config files.
- [Troubleshooting](docs/troubleshooting.md): the errors met so far, and freeing disk.

## Work on it

The recipes live in the `justfile`, the benchmark in `scripts/bench.sh`. `just serve` plus one request is the check after a change: there is no test suite and no release. Rules and the reasoning behind the setup: [CLAUDE.md](CLAUDE.md).

## License

[PolyForm Strict 1.0.0](LICENSE), copyright hackers&wizards GmbH. The name hackers&wizards and its logos are not licensed.
