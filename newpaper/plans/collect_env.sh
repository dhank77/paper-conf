#!/bin/bash
###############################################################################
# collect_env.sh -- toolchain / hardware capture for Table I.
#
# RUN ON BOTH MACHINES: ASUS Ascent GX10 (GB10) *and* the RTX 4090 desktop.
#
# Why this exists (reviews/03.md item #1):
#   Table I currently claims CUDA 12.0 for the GB10. That cannot be right.
#   results/gpu-4.txt reports the GB10 as "Compute 12.1" under -arch=native,
#   and sm_121 is a Blackwell target that no toolkit before CUDA 12.8 can
#   even emit. The only nvcc dump on file (results/spesifikasi/75-gcc-nvcc.txt)
#   says release 12.0 -- but it was captured on a host called "node6", which
#   therefore cannot be the machine that produced the GB10 results.
#
#   So: this must be run on the host that actually *builds and runs* the GB10
#   experiments, not on a login/head node. The script prints the hostname so
#   the provenance is recorded in the output itself.
#
# Takes about two seconds. Builds nothing, measures nothing.
#
# Usage:  bash collect_env.sh
# Output: results_env_<tag>.txt   -- send this file back.
###############################################################################

set -uo pipefail
cd "$(dirname "$0")"

if [ -d "/usr/local/cuda/bin" ]; then
    export PATH="/usr/local/cuda/bin:${PATH}"
fi
if [ -d "/usr/lib/aarch64-linux-gnu/tegra" ]; then
    export LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu/tegra:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
fi

GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
case "$GPU_NAME" in
    *GB10*)  TAG="gb10" ;;
    *4090*)  TAG="rtx4090" ;;
    *)       TAG="$(uname -m)" ;;
esac
OUT="results_env_${TAG}.txt"

{
echo "=============================================================="
echo " FSRCNN paper -- environment capture"
echo " tag:       $TAG"
echo " hostname:  $(hostname)"
echo " date:      $(date -Is)"
echo " cwd:       $(pwd)"
echo "=============================================================="
echo

echo "---------- [1] nvcc (THE ANSWER TO REVIEW ITEM #1) ----------"
if command -v nvcc >/dev/null 2>&1; then
    echo "which nvcc: $(command -v nvcc)"
    nvcc --version
else
    echo "nvcc NOT FOUND on PATH."
    echo "If CUDA lives somewhere non-standard, re-run as:"
    echo "  PATH=/path/to/cuda/bin:\$PATH bash collect_env.sh"
fi
echo

echo "---------- [2] driver / runtime as the GPU reports it ----------"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi
    echo
    echo "-- query form (easier to quote in the table) --"
    nvidia-smi --query-gpu=name,compute_cap,driver_version,memory.total \
               --format=csv 2>/dev/null
else
    echo "nvidia-smi NOT FOUND."
fi
echo

echo "---------- [3] what the runtime API actually sees ----------"
# This is the number that must be consistent with the nvcc release above.
# deviceQuery is not always installed, so compile a 12-line probe instead.
cat > /tmp/_cudaprobe.cu <<'EOF'
#include <cstdio>
#include <cuda_runtime_api.h>
int main() {
  int rt = 0, drv = 0, n = 0;
  cudaRuntimeGetVersion(&rt);
  cudaDriverGetVersion(&drv);
  cudaGetDeviceCount(&n);
  printf("cuda_runtime_version = %d  (i.e. %d.%d)\n", rt, rt / 1000,
         (rt % 1000) / 10);
  printf("cuda_driver_version  = %d  (i.e. %d.%d)\n", drv, drv / 1000,
         (drv % 1000) / 10);
  for (int i = 0; i < n; i++) {
    cudaDeviceProp p;
    cudaGetDeviceProperties(&p, i);
    printf("device %d: %s  sm_%d%d  %.2f GB  SMs=%d  clk=%.2f GHz\n", i, p.name,
           p.major, p.minor, (double)p.totalGlobalMem / (1 << 30),
           p.multiProcessorCount, p.clockRate / 1.0e6);
    printf("          unifiedAddressing=%d  integrated=%d  canMapHost=%d\n",
           p.unifiedAddressing, p.integrated, p.canMapHostMemory);
  }
  return 0;
}
EOF
if command -v nvcc >/dev/null 2>&1 &&
   nvcc -o /tmp/_cudaprobe /tmp/_cudaprobe.cu -lcudart 2>/dev/null; then
    /tmp/_cudaprobe
    echo
    echo "-- which -arch does 'native' resolve to on this host? --"
    # -arch=native failing here would mean the toolkit predates the GPU,
    # which is exactly the inconsistency we are chasing.
    if nvcc -arch=native -ptx -o /dev/null /tmp/_cudaprobe.cu 2>/tmp/_archerr; then
        echo "-arch=native: OK (toolkit can target this GPU)"
    else
        echo "-arch=native: FAILED -- toolkit is older than the GPU:"
        cat /tmp/_archerr
    fi
else
    echo "(probe not built -- no nvcc)"
fi
rm -f /tmp/_cudaprobe /tmp/_cudaprobe.cu /tmp/_archerr
echo

echo "---------- [4] host compiler ----------"
gcc --version 2>/dev/null | head -2 || echo "gcc not found"
echo "OpenMP: $(echo | gcc -fopenmp -dM -E - 2>/dev/null | grep -c _OPENMP) (1 = supported)"
echo

echo "---------- [5] CPU / memory / OS ----------"
if command -v lscpu >/dev/null 2>&1; then
    lscpu | grep -iE "^(architecture|model name|cpu\(s\)|thread|core|socket|nu?ma node\(s\)|cpu max|cpu min|l1d|l1i|l2|l3)"
else
    grep -m1 "model name" /proc/cpuinfo 2>/dev/null
    echo "cores: $(nproc 2>/dev/null)"
fi
echo
free -h 2>/dev/null || true
echo
uname -a
echo
cat /etc/os-release 2>/dev/null | grep -E "^(NAME|VERSION)=" || true
echo

echo "=============================================================="
echo " Done. Send back: $(pwd)/$OUT"
echo "=============================================================="
} 2>&1 | tee "$OUT"
