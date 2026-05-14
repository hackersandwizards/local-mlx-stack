#!/usr/bin/env bash
set -euo pipefail

echo "This will delete ~/.cache/huggingface/hub, ~/.omlx/models, ~/.mtplx/models entirely."
read -rp "Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { echo "(aborted)"; exit 1; }

rm -rf "$HOME/.cache/huggingface/hub" "$HOME/.omlx/models" "$HOME/.mtplx/models"
echo "✓ caches cleared"
