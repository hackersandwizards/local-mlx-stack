# Troubleshooting

- `Address already in use` on port 8001: check what holds it with `lsof -nP -iTCP:8001 -sTCP:LISTEN`. If it is MTPLX, run `just stop`.
- `mtplx missing`: declared in `~/.config/mise/config.toml` as `"pypi:mtplx" = { version = "latest", extras = "server" }`; run `mise install`.
- `response_format: json_schema` fails with missing `llguidance`: ensure `extras = "server"` is set on `pypi:mtplx` in `~/.config/mise/config.toml`, then run `mise install` and `just doctor`.
- Model not pulled: run `just pull`. If a download drops with `Connection reset by peer`, re-run `just pull` — it resumes from partial shards.
- Thinking still appears with `reasoning_effort: "none"`: Inkling 2 Mini still emits brief reasoning tokens unless `enable_thinking: false` is sent.
- Freeing disk:
  - Reclaim orphaned SSD SessionBank files: `mtplx gc --apply`.
  - Remove cached packs: `mtplx models` shows paths under `~/.mtplx/models`. Space may stay pinned for up to a day by hourly Time Machine local snapshots (`tmutil listlocalsnapshots /`).
