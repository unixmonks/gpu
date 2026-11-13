# Providers

Where to rent a box for `./gpu up`, and what to check before downloading a model. Prices are on-demand per
GPU-hour from third-party trackers as of November 2026. They vary by tier and region, so check the provider's own
page before renting.

## What a box needs

| Need | Why | How to check |
|---|---|---|
| x86-64, NVIDIA, SSH access | both engines and this harness | provider listing |
| RTX 30/40/50 or RTX PRO 6000 (Blackwell) | Strata ships prebuilt engines for GeForce-class cards. Datacenter cards (H100, sm_90) aren't in its list; Maya compiles for whatever is there | `./gpu check` |
| CUDA *devel* image (`nvcc`) | Maya compiles its engine | `./gpu check` → "CUDA toolkit" |
| `memlock` unlimited | Maya pins its expert tier in RAM | `./gpu check` → "memlock limit" |
| PCIe x16, Gen4/Gen5 | missed experts stream over PCIe | `./gpu check` → link gen/width |
| RAM ≥ model size − VRAM | keeps cold experts off the SSD | `./gpu check` → RAM |
| 200–400 GB free NVMe | 100–350 GB per model | `./gpu check` → disk |

## Options

| Provider | Kind | Fits for | Price (approx.) | Watch out for |
|---|---|---|---|---|
| **[Vast.ai](https://vast.ai)** | Docker marketplace | First runs and consumer/pro cards: RTX PRO 6000, 5090, 4090, multi-GPU hosts | RTX PRO 6000 from ~$1–1.7/hr | Every host differs. memlock is set by the host and can't be raised from inside the container. Filter on RAM, disk and PCIe bandwidth, and run `./gpu check` first |
| **[RunPod](https://runpod.io)** | Docker pods | Same cards, more uniform than Vast | RTX PRO 6000 ~$1.6–2.5/hr | Same memlock limit as Vast. RAM per pod is fixed by GPU count |
| **[Lambda](https://lambda.ai)** | VMs with root | Datacenter cards, big RAM, the 1M-context DeepSeek runs | 1x H100 PCIe ~$3.29/hr, SXM ~$4.29/hr. The 8x H100 node has 1.8 TB RAM and 22 TB SSD | Maya only for H100s (Strata has no H100 engine). Check RAM per 1x instance on Lambda's page |
| **[Latitude.sh](https://latitude.sh) / [OVH](https://ovhcloud.com)** | Bare metal | Full control: memlock, PCIe, NVMe all yours | higher, often monthly | Slower to provision |

## Recommendation

**First rental: Vast.ai, one RTX PRO 6000 (96 GB)**, with these settings:

- **Instance filters:**
  - host RAM ≥ 256 GB
  - disk ≥ 300 GB
  - high PCIe bandwidth
  - image `nvidia/cuda:12.9.1-devel-ubuntu24.04`
- **First commands:** `./gpu check`, then `./gpu up maya-glm-flash`, then `./gpu up strata-qwen`.

Why this box:

- **Cheapest way to prove the whole flow,** at roughly $1–2/hr. A box with a bad memlock limit or PCIe link costs
  minutes, not a day.
- **Runs both engines.** The PRO 6000 is Blackwell (sm_120): Strata's prebuilt engines cover it, and Maya builds for it.
- **96 GB holds most of GLM-5.3-Flash Maya-S.** This is the config Maya reports 81 tok/s on, so it's a meaningful
  first speed reading.

If `./gpu check` shows a memlock limit that isn't `unlimited`, destroy the instance and try another host. If no host
works, move to Lambda (a VM where you're root) or bare metal.

**After the smoke test:**

- **DeepSeek-sized and 1M-context profiles:** the engines keep only the hot experts on the card, so one GPU with
  enough RAM runs them. RAM is the hard requirement: 256–512 GB+, enough to hold the model's cold experts.
  - **Find the VRAM curve:** run the same profile on 1× 5090, then 1× RTX PRO 6000, then 2× RTX PRO 6000. Stop at the
    first box that hits your speed target.
  - Lambda's multi-H100 nodes are Maya-only.
- **Buying a box:** the consumer and pro cards (5090, PRO 6000) are what you'd buy, so test on those rather than
  H100s.

## Sources

- [Thundercompute: RTX PRO 6000 pricing, Nov 2026](https://www.thundercompute.com/blog/nvidia-rtx-pro-6000-pricing)
- [Computeprices: RTX PRO 6000 on Vast.ai](https://computeprices.com/providers/vast/gpus/rtx-pro-6000)
- [GPUPerHour: RTX PRO 6000 Blackwell host specs](https://gpuperhour.com/rent/rtx-pro-6000-blackwell)
- [Lambda H100 pricing, Oct 2026](https://themodelpress.com/explainers/h100-rental-price)
- [Lambda 8x H100 node specs](https://www.spheron.network/blog/lambda-cloud-h100-pricing-2026/)
- [memlock can't be raised inside a rented container](https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/76567628/change-memlock-limit-in-a-docker-container-is-it-possible)
