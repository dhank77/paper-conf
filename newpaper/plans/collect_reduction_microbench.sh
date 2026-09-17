#!/bin/bash
###############################################################################
# collect_reduction_microbench.sh -- high-precision re-measurement of
# spatial_reduction_kernel's true per-launch time (Section VII open question).
#
# RUN ON BOTH MACHINES: ASUS Ascent GX10 (GB10) *and* the RTX 4090 desktop.
#
# collect_l2_readwrite_profile.sh already ruled out L2 caching as the cause
# of the RTX 4090's apparent 2.5x-over-GDDR6X-peak effective bandwidth
# (dram__bytes_read.sum showed ~100% of the buffer genuinely comes from
# DRAM). That leaves the TIMING method as the likely culprit: Table III's
# 2.62 ms / 150 launches = 17.5 us per launch is measured with a single
# CUDA Event pair per profiling run, and at that timescale the event pair's
# own recording latency/resolution can be a real fraction of what's
# measured. spatial_reduction_microbench.cu removes that risk by wrapping
# thousands of back-to-back launches in ONE event pair, so per-launch timer
# overhead is amortized to near zero. This script builds and runs it.
#
# Usage:  bash collect_reduction_microbench.sh
#         LAUNCHES=20000 REPS=8 bash collect_reduction_microbench.sh
# Output: results_microbench_<tag>.txt -- send it back.
###############################################################################

set -uo pipefail
cd "$(dirname "$0")"

if [ -d "/usr/local/cuda/bin" ]; then
    export PATH="/usr/local/cuda/bin:${PATH}"
fi
if [ -d "/usr/lib/aarch64-linux-gnu/tegra" ]; then
    export LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu/tegra:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
fi

LAUNCHES="${LAUNCHES:-10000}"
REPS="${REPS:-6}"
THREADS_REDUCE="${THREADS_REDUCE:-256}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

command -v nvcc >/dev/null 2>&1 || die "nvcc not on PATH."
[ -f "spatial_reduction_microbench.cu" ] || die "missing spatial_reduction_microbench.cu"

GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
case "$GPU_NAME" in
    *GB10*) TAG="gb10";    PEAK_GBPS=273  ;;  # LPDDR5x peak, ASUS GX10 datasheet
    *4090*) TAG="rtx4090"; PEAK_GBPS=1008 ;;  # GDDR6X peak, NVIDIA Ada whitepaper
    *)      TAG="unknown"; PEAK_GBPS=0
            warn "Could not identify the GPU from nvidia-smi (got '${GPU_NAME:-nothing}')." ;;
esac

OUT_TXT="results_microbench_${TAG}.txt"

# ---------------------------------------------------------------------------
# Build (same fallback -arch ladder as the other collect_*.sh scripts)
# ---------------------------------------------------------------------------
rm -f ./spatial_reduction_microbench
built=0
for arch in native sm_121 sm_120 sm_90 sm_89 sm_87; do
    if nvcc -arch="$arch" -O3 -o spatial_reduction_microbench \
            spatial_reduction_microbench.cu -lcudart 2>/dev/null; then
        info "built spatial_reduction_microbench (-arch=$arch)"
        built=1
        break
    fi
done
[ "$built" = "1" ] || die "could not compile spatial_reduction_microbench.cu with any -arch option"

info "Platform: ${GPU_NAME:-unknown}  tag=$TAG  launches/rep=$LAUNCHES  reps=$REPS  threads_reduce=$THREADS_REDUCE"
info "Running (this is thousands of tiny kernel launches per rep -- should take well under a minute)..."

RAW_OUT="$(./spatial_reduction_microbench "$LAUNCHES" "$REPS" "$THREADS_REDUCE" 2>&1)"
STATUS=$?
[ $STATUS -eq 0 ] || { echo "$RAW_OUT"; die "spatial_reduction_microbench exited with status $STATUS"; }

MEAN_GBPS="$(echo "$RAW_OUT" | grep -oE 'mean_effective_bandwidth_GBps=[0-9.]+' | cut -d= -f2)"
MEAN_US="$(echo "$RAW_OUT" | grep -oE 'mean_per_launch_us=[0-9.]+' | cut -d= -f2)"

{
echo "=============================================================="
echo " spatial_reduction_kernel microbenchmark -- $TAG"
echo " gpu:       ${GPU_NAME:-unknown}"
echo " hostname:  $(hostname)"
echo " date:      $(date -Is)"
echo " launches/rep: $LAUNCHES   reps: $REPS   threads_reduce: $THREADS_REDUCE"
echo "=============================================================="
echo
echo "$RAW_OUT"
echo
if [ -n "$MEAN_GBPS" ] && [ "$PEAK_GBPS" != "0" ]; then
    python3 -c "
mean_gbps = $MEAN_GBPS
peak = $PEAK_GBPS
ratio = mean_gbps / peak
print(f'Comparison to hardware peak:')
print(f'  measured effective bandwidth : {mean_gbps:.1f} GB/s')
print(f'  {\"$TAG\"} rated peak bandwidth  : {peak} GB/s')
print(f'  ratio                        : {ratio:.2f}x')
if ratio > 1.05:
    print()
    print('  Still above peak: the anomaly survives this much more precise')
    print('  timing method, so it is NOT a CUDA-Event measurement artifact.')
    print('  The mechanism remains a genuine open question (Section VII).')
elif ratio < 0.95:
    print()
    print('  Below peak now: Table III\\'s 2.62 ms figure was very likely')
    print('  inflated by per-launch CUDA-Event overhead at that short a')
    print('  timescale. This measurement is the more trustworthy one.')
else:
    print()
    print('  Close to peak (within ~5%): consistent with the kernel being')
    print('  a normal, unremarkable DRAM-bandwidth-bound kernel. The original')
    print('  Table III number was very likely a timing-overhead artifact.')
"
fi
echo
echo "Reading this: this program bypasses Table III's per-launch CUDA-Event"
echo "methodology entirely -- thousands of launches share ONE event pair, so"
echo "per-launch timer overhead is amortized to near zero. If the measured"
echo "bandwidth here still exceeds the platform's rated peak, the anomaly is"
echo "real and not a measurement artifact of the original methodology."
echo
echo "File to send back:"
echo "  $(pwd)/$OUT_TXT"
echo "=============================================================="
} | tee "$OUT_TXT"
