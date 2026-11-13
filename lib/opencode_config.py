"""Add or replace the "gpu" provider in an opencode.json, keeping every other setting.

usage: opencode_config.py CONFIG MODEL_ID CONTEXT LOCAL_PORT ENGINE
"""
import json
import os
import sys

path, model, context, port, engine = sys.argv[1:6]
# Profiles give Maya's token counts (1048576) or Strata's sizes (128k, 1m).
units = {"k": 1024, "m": 1024 * 1024}
context = context.lower()
context = int(context[:-1]) * units[context[-1]] if context[-1] in units else int(context)
# Room for the answer; OpenCode compacts the conversation once input reaches limit.input,
# and never compacts without it (Strata docs/TERMINAL_LAUNCH.md).
output = min(32768, context // 4)

cfg = {"$schema": "https://opencode.ai/config.json"}
if os.path.exists(path):
    with open(path) as f:
        cfg = json.load(f)

cfg.setdefault("provider", {})["gpu"] = {
    "npm": "@ai-sdk/openai-compatible",
    "name": f"Rented GPU ({engine})",
    "options": {
        "baseURL": f"http://127.0.0.1:{port}/v1",
        "apiKey": "{env:GPU_API_KEY}",
    },
    "models": {
        model: {
            "name": f"{model} ({engine})",
            "tool_call": True,
            "limit": {"context": context, "input": context - output, "output": output},
        }
    },
}

os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
