#!/usr/bin/env bash
# Runs on the GPU box: prepares it, then launches remote/<engine>.sh for the profile inside tmux.
set -euo pipefail
cd ~/.gpu
PROFILE="$1"
. "./$PROFILE.env"

SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# Base packages; rented images are usually Ubuntu with apt.
missing=""
for c in git curl tmux python3 g++ openssl; do command -v "$c" >/dev/null || missing="$missing $c"; done
if ! python3 -c 'import venv, ensurepip' 2>/dev/null; then missing="$missing python3-venv"; fi
if [ -n "$missing" ]; then
  echo "installing:$missing"
  $SUDO apt-get update -qq
  $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl tmux python3 python3-venv python3-pip g++ openssl
fi

# Ubuntu's systemd-oomd kills a session that loads a large RAM tier (Maya docs/SETUP.md).
if systemctl is-active --quiet systemd-oomd 2>/dev/null; then $SUDO systemctl stop systemd-oomd || true; fi

# Data on the box's NVMe: GPU_DATA_DIR from .env, else /workspace (Vast/RunPod volume), else ~/gpu-data.
DATA="${GPU_DATA_DIR:-}"
[ -z "$DATA" ] && [ -d /workspace ] && [ -w /workspace ] && DATA=/workspace/gpu-data
DATA="${DATA:-$HOME/gpu-data}"
mkdir -p "$DATA"

if tmux has-session -t gpu 2>/dev/null; then
  echo "a 'gpu' tmux session is already running: ./gpu stop first, or ./gpu logs"
  exit 1
fi

: > run.log
echo "== $(date -Is) $PROFILE on $(hostname), data in $DATA" >> run.log
# The session stays open after the engine returns (Strata's --no-tui serves in the background),
# so nothing it started is cut off.
tmux new-session -d -s gpu \
  "DATA='$DATA' HF_TOKEN='${HF_TOKEN:-}' bash ~/.gpu/$ENGINE.sh '$PROFILE' 2>&1 | tee -a ~/.gpu/run.log; exec sleep infinity"
echo "started; log in ~/.gpu/run.log"
