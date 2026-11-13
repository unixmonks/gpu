#!/usr/bin/env bash
# Runs on the GPU box inside tmux: installs Strata's terminal app from a pinned release (checked
# against the release's SHA256SUMS), then launches the profile's model on 127.0.0.1:8080.
set -euo pipefail
. ~/.gpu/"$1".env
STRATA_VERSION="${STRATA_VERSION:-v0.2.13}"
STRATA="$HOME/.local/bin/strata"

if [ ! -x "$STRATA" ]; then
  rel="https://github.com/Niko1221/Strata/releases/download/$STRATA_VERSION"
  tmp="$(mktemp -d)"
  curl -fsSL --retry 3 -o "$tmp/install.sh" "$rel/install.sh"
  curl -fsSL --retry 3 -o "$tmp/SHA256SUMS.txt" "$rel/SHA256SUMS.txt"
  (cd "$tmp" && grep ' install.sh$' SHA256SUMS.txt | sha256sum -c -) || { echo "install.sh does not match SHA256SUMS"; exit 1; }
  sh "$tmp/install.sh"
  rm -rf "$tmp"
fi

GPU_API_KEY="$(cat ~/.gpu/api-key)"; export GPU_API_KEY
args=(--family "$STRATA_FAMILY" --model "$STRATA_MODEL" --context "$CONTEXT"
      --data-dir "$DATA/strata" --access local --port 8080 --api-key-env GPU_API_KEY
      --vision off --yes --no-tui)
# shellcheck disable=SC2206
[ -n "${STRATA_EXTRA:-}" ] && args+=($STRATA_EXTRA)

echo "== strata launch ${args[*]}"
"$STRATA" launch --plan "${args[@]}"
"$STRATA" launch "${args[@]}"
"$STRATA" launch --status
