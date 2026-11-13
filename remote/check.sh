#!/usr/bin/env bash
# Runs on the GPU box: what the engines care about. Both stream experts over PCIe and pin RAM,
# so a narrow PCIe link or a memlock limit costs as much as a smaller GPU.
echo "== GPUs (PCIe gen / width, current and max)"
nvidia-smi --query-gpu=index,name,memory.total,driver_version,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max \
  --format=csv 2>/dev/null || echo "nvidia-smi not found"
echo "== CUDA toolkit (Maya needs nvcc)"
(command -v nvcc || ls /usr/local/cuda/bin/nvcc) 2>/dev/null && nvcc --version 2>/dev/null | tail -1 || echo "no nvcc"
echo "== CPU"
lscpu | grep -E 'Model name|^CPU\(s\)|Socket|NUMA node\(s\)'
echo "flags: $(grep -o -w -E 'avx2|avx512f|amx_tile' /proc/cpuinfo | sort -u | tr '\n' ' ')"
echo "== RAM"
free -g | head -2
echo "memlock limit: $(ulimit -l)   (Maya pins its expert tier; 'unlimited' is best)"
echo "cgroup memory limit: $(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo n/a)"
echo "== Disk"
df -h "${GPU_DATA_DIR:-/workspace}" "$HOME" 2>/dev/null | sort -u
lsblk -d -o NAME,SIZE,ROTA,MODEL 2>/dev/null | grep -v loop
