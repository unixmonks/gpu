# gpu

Rent a GPU box, bring [Strata](https://github.com/Niko1221/Strata) or [Maya](https://github.com/mw00/project-maya) up on
it over SSH, and point OpenCode at it. The goal is to find out how much VRAM, RAM and NVMe a local machine needs to run
Opus-level reasoning on large open MoE models, at **1M context** and **Claude-like speed**.

Both engines keep the hot experts in VRAM and stream the rest from pinned RAM (and NVMe) over PCIe. So the box's VRAM,
RAM, PCIe links and disk all show up directly in the speed you get.

## Quick start

```sh
cp .env.example .env              # paste GPU_HOST / GPU_SSH_PORT from the provider's SSH line
./gpu check                       # is this box any good? GPUs, PCIe links, RAM, memlock, nvcc, disk
./gpu up maya-glm-flash           # install engine, download model, serve - in tmux on the box
./gpu wait                        # open the SSH tunnel, wait until the model answers
./gpu opencode                    # add provider "gpu" to ~/.config/opencode/opencode.json
./gpu code                        # OpenCode on the served model
./gpu stop                        # before you hand the box back
```

Start with `maya-glm-flash` (or `strata-qwen`) on a single 96 GB card to prove the whole flow cheaply. Then rent a
bigger box for the DeepSeek-sized profiles.

## Commands

| Command | What it does |
|---|---|
| `./gpu profiles` | List the engine/model/context profiles |
| `./gpu check` | Report the box: GPUs, PCIe gen and width (current and max), CPU flags, RAM, memlock and cgroup limits, disks, CUDA toolkit |
| `./gpu up <profile>` | Copy the scripts to `~/.gpu` on the box, install the engine, download the model, start serving in tmux, follow the log |
| `./gpu logs` | Follow the box's log (`~/.gpu/run.log`). Ctrl+C only stops following |
| `./gpu status` | Show the tmux session, the tunnel, and what `/v1/models` answers |
| `./gpu wait` | Open the tunnel and poll until the model answers |
| `./gpu tunnel` | Forward the box's `127.0.0.1:8080` to `127.0.0.1:18080` here |
| `./gpu opencode` | Add or replace the `gpu` provider in `opencode.json` (backs it up first; other providers and your default model are kept) |
| `./gpu code [args]` | Run `opencode -m gpu/<served model>` with `GPU_API_KEY` set |
| `./gpu ssh` | Attach to the box's tmux session |
| `./gpu stop` | Stop the engine, the tmux session and the tunnel |

## Profiles

A profile is a few lines in `profiles/`. Copy one to try another model or context.

| Profile | Engine | Model | Download | Context |
|---|---|---|---:|---|
| `maya-deepseek-1m` | Maya | DeepSeek-V4.1-Flash · Maya-S | 340 GB | 1M |
| `maya-deepseek-256k` | Maya | DeepSeek-V4.1-Flash · Maya-S | 340 GB | 256K |
| `maya-glm53` | Maya | GLM-5.3 744B · Maya-XS | 170 GB | 128K |
| `maya-glm-flash` | Maya | GLM-5.3-Flash 321B · Maya-S | 96.5 GB | 128K |
| `maya-minimax` | Maya | MiniMax-M3.1-Flash · Maya-S | | 256K |
| `strata-deepseek-1m` | Strata | DeepSeek-V4.1-Flash · ISTA-DAS 2.00 bpw | 257 GB | 1M |
| `strata-qwen` | Strata | Qwen3.8-Flash-Next 125B · IQ3_XXS | | 128K |
| `maya-beam` | Maya + [our Beam port](#reflection-beam-on-maya) | Beam-1.0-501B-A23B · unsloth UD-IQ2_XXS | 134 GB | 256K |
| `maya-beam-1m` | Maya + our Beam port | Beam-1.0-501B-A23B · unsloth UD-Q2_K_XL | 187 GB | 1M |
| `maya-beam-llamacpp-routing` | Maya + our Beam port | UD-IQ2_XXS, routed as llama.cpp does (for logit comparisons) | 134 GB | 32K |

Profile keys:

- `ENGINE`: `maya`, `maya-beam` or `strata`.
- `CONTEXT`: a token count for Maya (`1048576`). For Strata, a size such as `128k` or `1m`.
- **Maya keys:**
  - `MAYA_MODEL`: the setup id
  - `MAYA_GPUS`: e.g. `0,1`
  - `MAYA_EXTRA`: any other `./maya.sh` flags
  - `MAYA_VERSION`: default `v1.1.61`
- **Beam keys (`maya-beam`):**
  - `BEAM_QUANT`: a folder of unsloth's repo, e.g. `UD-IQ2_XXS`, `UD-Q2_K_XL`
  - `BEAM_KV`: `int8` (default), `bf16` or `fp8`
  - `BEAM_NO_GROUP_LIMIT=1`: llama.cpp's routing
  - `BEAM_EXTRA`: more `beam_setup.py` flags
- **Strata keys:**
  - `STRATA_FAMILY`, `STRATA_MODEL`
  - `STRATA_EXTRA`: any other `strata launch` flags
  - `STRATA_VERSION`: default `v0.2.13`

Engine flag references: Maya `docs/SETUP.md` and `docs/SETTINGS.md`, Strata `docs/TERMINAL_LAUNCH.md`.

## Settings (`.env`)

| Variable | Default | |
|---|---|---|
| `GPU_HOST` | | `user@host` from the provider |
| `GPU_SSH_PORT` | `22` | Vast and RunPod often use another port |
| `GPU_DATA_DIR` | `/workspace/gpu-data` if present, else `~/gpu-data` | Where models go on the box. Put it on the NVMe |
| `GPU_LOCAL_PORT` | `18080` | Local end of the tunnel |
| `HF_TOKEN` | | Only for gated Hugging Face repos |

## How it fits together

```
gpu                      local CLI
lib/opencode_config.py   merges the "gpu" provider into opencode.json
remote/start.sh          on the box: packages, stops systemd-oomd, picks the data dir, starts tmux
remote/maya.sh           clones Maya at the pinned tag, runs ./maya.sh --model … --yes --download-model
remote/maya-beam.sh      the unixmonks Maya fork (branch beam), CMake build, kernel test, GGUF download, serve
remote/strata.sh         installs Strata (installer checked against the release's SHA256SUMS), strata launch --yes --no-tui
remote/check.sh          hardware report
remote/stop.sh           stops the engine and tmux
profiles/*.env           engine / model / context
.state/                  generated API key, current profile, tunnel socket (git-ignored)
```

- **Survives disconnects:** setup and serving run inside tmux on the box, so a dropped SSH session doesn't stop a
  300 GB download or the server.
- **Not exposed:** the engine listens on the box's `127.0.0.1:8080` only, and you reach it through the SSH tunnel. An
  API key is still generated (`.state/api-key`) and required.
- **The key stays out of the config file:** OpenCode reads it from `GPU_API_KEY` (`{env:GPU_API_KEY}`), which
  `./gpu code` sets. To run `opencode` yourself, first run `export GPU_API_KEY=$(cat .state/api-key)`.
- **Compaction works:** the OpenCode entry sets `limit.context`, `limit.input` and `limit.output`. Without
  `limit.input`, OpenCode never compacts the conversation.

## Reflection Beam on Maya

[Beam-1.0-501B-A23B](https://huggingface.co/reflection/Beam-1.0-501B-A23B) is not one of Maya's models, so it runs from
a fork with a port: [unixmonks/project-maya](https://github.com/unixmonks/project-maya), branch `beam`, one commit
on Maya v1.1.61. It adds Beam to Maya's MiniMax engine
(`maya-mm3`): its attention (9 global layers, 43 sliding-window layers in small ring caches), the attention gate,
sandwich norms, depth-scaled residual, group-limited router, logit softcap, tokenizer, chat template and tool-call
parsing. Maya's existing placement and expert offload are reused unchanged. See the fork's [`docs/BEAM.md`](https://github.com/unixmonks/project-maya/blob/beam/docs/BEAM.md) for the
details.

Beam suits the 1M-context goal: only its 9 global layers keep the whole context, so 1M tokens of KV cache is about
18 GiB in INT8, not hundreds.

**Status: built and tested without a GPU, not yet run on one.**

| Checked without a GPU | Not run yet (first rental) |
|---|---|
| CUDA build of the engine and the kernel test | `mm3_beam_test`: the kernels against F64 references |
| the pack on unsloth's real UD-Q2_K_XL and UD-IQ2_XXS headers: all 38,366 tensors, types, geometry | a model forward |
| the tokenizer against Beam's `tokenizer.json`, exactly | logits against llama.cpp on the same GGUF (`maya-beam-llamacpp-routing`) |
| the chat template, the output parser and tool calls, streamed and whole | long prompts (past the 512-token rings) and decode speed |
| the server end to end on a stand-in engine (OpenAI and Anthropic APIs) | |
| Maya's existing server tests, unchanged | |

`./gpu up maya-beam` builds, runs the kernel test (its result is in the log and in `mm3_beam_test.log` on the box),
downloads the GGUF and serves. If the kernel test reports a FAIL, stop there.

## Picking a box

[PROVIDERS.md](PROVIDERS.md) compares providers and says where to rent first. What to look for, and what
`./gpu check` shows:

- **VRAM is what decides speed.** Every expert that misses VRAM crosses PCIe. Claude-like tok/s needs most of the
  active experts resident in VRAM. RAM and NVMe only decide how cheaply the cold ones are kept.
- **PCIe x16, Gen4 or Gen5.** Check the current and max link per GPU. Marketplace hosts on risers or x8/x4 links are
  much slower.
- **RAM at least model size minus VRAM**, if you want the whole model off the SSD. Maya pins all but about 6 GB of it.
- **`memlock` unlimited.** In Docker that means `--ulimit memlock=-1`, which many container hosts don't set. VMs and
  bare metal (Lambda, Latitude.sh, OVH) don't have this problem. On Vast or RunPod, check before downloading.
- **`nvcc` for Maya.** Maya compiles its engine (20–40 min the first time), so rent with a CUDA *devel* image, e.g.
  `nvidia/cuda:12.9.1-devel-ubuntu24.04`, or a 13.x image with driver 580+. Strata ships prebuilt engines.
- **NVMe space:** 100–350 GB free per model.
- **Avoid fractional slices of 8-GPU nodes.** You usually get 1/8 of the RAM and CPU.

## 1M context and speed

- **1M context:** DeepSeek-V4.1-Flash and GLM-5.3-Flash read 1M positions natively.
  - Strata has tested only up to 256K.
  - Maya recommends 256K and keeps the KV cache in RAM with a window in VRAM (`--kv-streaming`).
  - With both engines, expect the first reply to a 512K–1M prompt to take many minutes, and the KV cache to take VRAM
    away from experts.
- **Speed:** both engines log and display live tok/s (`./gpu logs`, or the dashboard via `./gpu ssh`). Compare that
  with Claude on the same prompts.
- **Calibration:** `./gpu up` skips the calibration runs, because `--yes` skips them. For the best numbers, stop the
  engine, run `./maya.sh --calibrate --no-start` on the box (`./gpu ssh`), then `./gpu up` again.

## Measuring speed

`lib/tps.py` streams a coding prompt and reports time to first token and decode tok/s. It speaks Anthropic's
`/v1/messages` or OpenAI's `/v1/chat/completions` (`--api openai`), so the same test runs against Claude and against
whatever the box serves:

```sh
ANTHROPIC_API_KEY=$(cat .state/api-key) python3 lib/tps.py http://127.0.0.1:18080 Beam-1.0-501B-A23B      # the box
BEARER_TOKEN=... python3 lib/tps.py https://api.anthropic.com claude-opus-5-5                               # Claude
```

Baselines measured on 2026-11-12: Claude Opus 5.5 about 123 tok/s decode (TTFT 3.4 s); Beam-1.0 hosted by Reflection
about 265 tok/s (TTFT 0.9 s).

## Safety

- Engines are pinned to a release tag. Read a release's changes before you raise the pin.
- Strata's docs site (stratallm.org) describes itself as unofficial. This harness installs from the GitHub releases only.
- Run the engines on rented boxes, not on machines that hold anything you care about.
- Run `./gpu stop` before handing the box back, and delete `GPU_DATA_DIR` if the provider keeps disks.
