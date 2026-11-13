#!/usr/bin/env bash
# Runs on the GPU box inside tmux: clones Maya at a pinned release, sets the profile's model up
# without questions (downloads it into $DATA/models) and serves it on 127.0.0.1:8080.
set -euo pipefail
. ~/.gpu/"$1".env
MAYA_VERSION="${MAYA_VERSION:-v1.1.61}"
DIR="$DATA/project-maya"

command -v nvcc >/dev/null || [ -x /usr/local/cuda/bin/nvcc ] || {
  echo "Maya compiles its engine and needs the CUDA toolkit (nvcc). Rent the box with a CUDA *devel*"
  echo "image (e.g. nvidia/cuda:12.9.1-devel-ubuntu24.04, or a 13.x devel image with driver 580+)."
  exit 1
}
export PATH="/usr/local/cuda/bin:$PATH"

if [ ! -d "$DIR/.git" ]; then
  git clone --depth 1 --branch "$MAYA_VERSION" https://github.com/mw00/project-maya.git "$DIR"
fi
cd "$DIR"

# With --yes the setup takes its recommended answers and skips the calibrations; --download-model
# lets it fetch the model; --plain keeps it to text in this tmux pane. A second run reuses the
# build and the download.
args=(--model "$MAYA_MODEL" --context "$CONTEXT" --models-dir "$DATA/models"
      --download-model --yes --plain --no-vision --port 8080 --api-key "$(cat ~/.gpu/api-key)")
[ -n "${MAYA_GPUS:-}" ] && args+=(--gpus "$MAYA_GPUS")
# shellcheck disable=SC2206
[ -n "${MAYA_EXTRA:-}" ] && args+=($MAYA_EXTRA)

echo "== ./maya.sh ${args[*]/$(cat ~/.gpu/api-key)/***}"
exec ./maya.sh "${args[@]}"
