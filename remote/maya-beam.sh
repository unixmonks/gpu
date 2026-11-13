#!/usr/bin/env bash
# Runs on the GPU box inside tmux: Project Maya at its pinned release with this repo's Beam patches (patches/maya-beam),
# built with CMake for this box's GPUs; Beam's kernel test; a Beam GGUF from unsloth; the pack and the server on
# 127.0.0.1:8080.  Each step is skipped when its result is there from a run before.
set -euo pipefail
. ~/.gpu/"$1".env
MAYA_VERSION="${MAYA_VERSION:-v1.1.61}"
BEAM_REPO="${BEAM_REPO:-unsloth/Beam-1.0-501B-A23B-GGUF}"
DIR="$DATA/project-maya-beam"
MODELS="$DATA/models/beam"

command -v nvcc >/dev/null || [ -x /usr/local/cuda/bin/nvcc ] || {
  echo "Maya compiles its engine and needs the CUDA toolkit (nvcc): rent the box with a CUDA *devel* image."
  exit 1
}
export PATH="/usr/local/cuda/bin:$PATH"

echo "== Maya $MAYA_VERSION + the Beam patches"
if [ ! -d "$DIR/.git" ]; then
  git clone --depth 1 --branch "$MAYA_VERSION" https://github.com/mw00/project-maya.git "$DIR"
  git -C "$DIR" -c user.name=gpu -c user.email=gpu@localhost am ~/.gpu/patches/*.patch
fi
cd "$DIR"

echo "== Python environment"
if [ ! -x .venv/bin/python ]; then
  python3 -m venv .venv
  .venv/bin/pip install -q --upgrade pip
  .venv/bin/pip install -q numpy jinja2 regex pyyaml tqdm requests cmake ninja pillow psutil "jsonschema>=4.18,<5" \
    "huggingface_hub[cli]"
fi
export PATH="$DIR/.venv/bin:$PATH"

echo "== build (maya-mm3, mm3_beam_test)"
if [ ! -x build/maya-mm3 ] || [ ! -x build/mm3_beam_test ]; then
  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_TESTS=ON \
    -DCMAKE_CUDA_ARCHITECTURES=native
  cmake --build build --target maya-mm3 mm3_beam_test -j "$(nproc)"
fi

echo "== Beam's kernels against F64 references"
build/mm3_beam_test | tee "$DATA/mm3_beam_test.log"

echo "== $BEAM_REPO $BEAM_QUANT"
hf download "$BEAM_REPO" --include "$BEAM_QUANT/*" --local-dir "$MODELS"

echo "== pack and config"
group=()
[ "${BEAM_NO_GROUP_LIMIT:-0}" = 1 ] && group=(--no-group-limit)
.venv/bin/python tools/mm3/beam_setup.py --model "$MODELS/$BEAM_QUANT" --context "$CONTEXT" \
  --kv-cache "${BEAM_KV:-int8}" --port 8080 "${group[@]}" ${BEAM_EXTRA:-}

echo "== serving on 127.0.0.1:8080"
exec .venv/bin/python serve/server.py --engine maya --config maya-beam.json --port 8080 \
  --api-key "$(cat ~/.gpu/api-key)"
