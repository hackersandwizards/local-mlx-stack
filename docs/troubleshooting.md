# Troubleshooting

- `listen tcp 127.0.0.1:8001: bind: address already in use`: something holds the port. `lsof -nP -iTCP:8001 -sTCP:LISTEN` names it.
- `could not connect to a running Ollama instance`: `just pull`, `just status` and `just stop` talk to the server. Run `just serve` first.
- `model 'inkling-2-mini' not found`: run `just pull`.
- A pull or load that says the model requires a newer Ollama: the model needs 0.40.17. Check `ollama --version` against the mise entry in the README.
- An empty answer with `reasoning_effort: "none"`: seen on 0.40.17-rc3, see [configuration](configuration.md#thinking). Use `low`.
- Thinking missing in a client: Ollama sends it as `reasoning`, not `reasoning_content`.
- Freeing disk: `ollama rm inkling-2-mini`. Space does not return immediately -- hourly Time Machine local snapshots pin the deleted blocks for about a day. `tmutil listlocalsnapshots /` shows them.
