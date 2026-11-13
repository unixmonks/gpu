#!/usr/bin/env bash
# Runs on the GPU box: stops whichever engine is serving and the tmux session.
[ -x ~/.local/bin/strata ] && ~/.local/bin/strata launch --stop 2>/dev/null
# Maya's server and engine end with maya.py on any signal (docs/SETUP.md).
tmux kill-session -t gpu 2>/dev/null && echo "stopped" || echo "nothing running"
