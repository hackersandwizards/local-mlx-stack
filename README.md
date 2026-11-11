# local-mlx-stack

One OpenAI-compatible server on loopback: [MTPLX](https://github.com/youssofal/MTPLX) with native MTP speculative decoding, serving Qwen models on Apple Silicon. Two models share one port, a quality one and a fast one; `just serve <name>` replaces whatever is running there. It is one person's local setup, published as it is, with every figure measured on an M3 Max with 64 GB.

| You want | Go to |
| --- | --- |
| Run a local model | [Requirements and first run](#requirements-and-first-run) |
| Point a client at it | [Endpoint](#endpoint) |
| Know why these models and the `turbo` profile | [docs/measurements.md](docs/measurements.md) |
| Change sampling or reasoning effort | [docs/configuration.md](docs/configuration.md) |
| Fix an error | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Change this repository | [CLAUDE.md](CLAUDE.md) |

## Requirements and first run

An Apple Silicon Mac with room for the model in unified memory: the default pack peaks at 32.7 GB. You also need [`just`](https://github.com/casey/just), `jq`, and MTPLX with `llguidance`, installed by [mise](https://mise.jdx.dev) from this table in `~/.config/mise/config.toml`:

```toml
[tools."pypi:git+https://github.com/youssofal/MTPLX"]
version = "latest"
with = ["llguidance"]
```

Then:

```bash
git clone https://github.com/hackersandwizards/local-mlx-stack.git
cd local-mlx-stack
mise install
just pull
just pull qwen3.6-35b
just doctor
just serve
```

`just pull` fetches the default model (about 30 GB) and `just pull qwen3.6-35b` the fast one (21 GB). An interrupted pull resumes when you run it again. `just doctor` checks both models against the contract. `just serve` runs the server in the foreground at `http://127.0.0.1:8001/v1`; Ctrl-C stops it. When it works, `curl -s http://127.0.0.1:8001/v1/models` names the loaded model.

## Models

- `qwen3.8-27b`, the default: `Youssofal/Qwen3.8-27B-MTPLX-Optimized-Quality`, dense 27B, 8-bit, 30.0 GB on disk, 27-28 tok/s. Text, image, video and tools.
- `qwen3.6-35b`, the fast lane: `Youssofal/Qwen3.6-35B-A3B-MTPLX-Optimized-Speed`, MoE with 3B active, 4-bit, 21.0 GB, 94-100 tok/s.

MTP speculative decoding is worth 2.03x here: `--mtp` against `--no-mtp`, same weights and loader. How these figures were measured: [docs/measurements.md](docs/measurements.md). `scripts/models.sh` holds the registry.

## Daily use

- `just serve [NAME]`: serve a model in the foreground, Ctrl-C to stop.
- `just bench [NAME]`: end-to-end tok/s against the model's port.
- `just pull [NAME]`: `mtplx pull` plus a symlink to the short served id.
- `just status`, `just models`: MTPLX's own status and model list.
- `just stop`: stop the MTPLX daemon on the port.
- `just doctor`: contract check per model, then `mtplx status`.

MTPLX owns the model cache, downloads, health and client wiring; call `mtplx` directly for those ([docs/configuration.md](docs/configuration.md)).

## Endpoint

```
http://127.0.0.1:8001/v1  -> qwen3.8-27b | qwen3.6-35b
```

One endpoint, one model at a time. Register both ids in your client: `mtplx connect <client>` prints the settings for opencode, Claude Code, Open WebUI and Swival. Switching then means `just serve <name>` plus picking the other id in the client.

**MTPLX does not check the requested id.** It answers from whatever is loaded, no error and no warning. The response's own `model` field and `curl -s http://127.0.0.1:8001/v1/models` name the loaded weights -- check there, not in the client's dropdown.

## Documentation

- [Measurements](docs/measurements.md): throughput per model, the `turbo` profile against `sustained`, MTPLX against `mlx_lm`.
- [Configuration](docs/configuration.md): what MTPLX owns, the sampling presets and reasoning effort, the client config files.
- [Troubleshooting](docs/troubleshooting.md): the error messages of the scripts and of MTPLX, and freeing disk.

## Work on it

The scripts live in `scripts/`, the recipes in the `justfile`. `just doctor` is the check after a change: there is no test suite and no release. Rules and the reasoning behind the setup: [CLAUDE.md](CLAUDE.md).

## License

[PolyForm Strict 1.0.0](LICENSE), copyright hackers&wizards GmbH. The name hackers&wizards and its logos are not licensed.
