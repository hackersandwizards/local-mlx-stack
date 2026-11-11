# Troubleshooting

- `:8001 held by something MTPLX cannot stop`: `serve.sh` already tried to replace the holder and waited 30 s, so this is not another MTPLX daemon. The message prints the `lsof` output naming the process.
- `mtplx missing`: it is declared in `~/.config/mise/config.toml` as `"pypi:git+https://github.com/youssofal/MTPLX" = { version = "latest", with = ["llguidance"] }`; run `mise install`.
- Model not pulled: `just pull <name>`. A placeholder repo without weight shards fails there, not at serve time.
- `pull failed: [Errno 54] Connection reset by peer`: transient, not a blocked network. Rerun `just pull` -- it resumes from the `.incomplete` shard rather than restarting.
- `response_format: json_schema` returns `requires the optional llguidance dependency`: MTPLX's `server` extra comes without `llguidance`. It fails closed rather than returning unconstrained output. The mise entry carries `with = ["llguidance"]`; if that is missing, add it and run `mise install`. `just doctor` checks it.
- Reasoning shows up in `content` instead of `reasoning_content`: that is the non-streaming path. SSE clients get the split via `--reasoning-parser qwen3`.
- Freeing disk: `mtplx models` for sizes, then remove the directory under `~/.mtplx/models`. Space does not return immediately -- hourly Time Machine local snapshots pin the deleted blocks for about a day. `tmutil listlocalsnapshots /` shows them.
