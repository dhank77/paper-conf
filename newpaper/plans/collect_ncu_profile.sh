#!/bin/bash
###############################################################################
# collect_ncu_profile.sh -- Nsight Compute hardware counters for Layer 8.
#
# RUN ON BOTH MACHINES: ASUS Ascent GX10 (GB10) *and* the RTX 4090 desktop.
#
# Reviewer 1 (weakness #5) and Reviewer 2 both asked for the L2 residency
# story in Section VII to be backed by real profiler counters instead of
# bandwidth arithmetic against hardware ceilings. This script profiles the
# production binary's two Layer-8 kernels (deconv_kernel, spatial_reduction_
# kernel) at the paper's winning grid (32x8_256) with `ncu` and pulls exactly
# the three metrics the Limitations section already names:
#   - L2 hit rate       (lts__t_sector_hit_rate.pct)
#   - L2 throughput      (lts__throughput.avg.pct_of_peak_sustained_elapsed)
#   - DRAM throughput    (dram__throughput.avg.pct_of_peak_sustained_elapsed)
#   - achieved occupancy (sm__warps_active.avg.pct_of_peak_sustained_active)
#
# Only the first frame's worth of launches is profiled (56 deconv_kernel +
# 1 spatial_reduction_kernel = 57 launches via --launch-count), not all 150
# frames: ncu's counter collection replays each kernel multiple times per
# pass, so profiling the full run would take a very long time and adds
# nothing -- every frame issues the same kernel over the same problem size,
# so one frame's counters are representative.
#
# Usage:  bash collect_ncu_profile.sh
#         NCU_LAUNCHES=113 bash collect_ncu_profile.sh   # profile 2 frames
# Output: results_ncu_<tag>.txt    (human-readable summary)
#         results_ncu_<tag>.csv    (ncu's own per-kernel CSV export)
#         results_ncu_<tag>.ncu-rep (full report, open in the Nsight Compute
#                                    GUI if you want more than the 4 metrics
#                                    below)
#         Send all three back.
#
# If this fails with ERR_NVGPUCTRPERM: the driver restricts performance
# counters to root on this machine. Re-run as
#   sudo bash collect_ncu_profile.sh
# or, more permanently (requires reboot):
#   echo 'options nvidia NVreg_RestrictProfilingToAdminUsers=0' | \
#     sudo tee /etc/modprobe.d/nvidia-profiling.conf
###############################################################################

set -uo pipefail
cd "$(dirname "$0")"

if [ -d "/usr/local/cuda/bin" ]; then
    export PATH="/usr/local/cuda/bin:${PATH}"
fi
if [ -d "/usr/lib/aarch64-linux-gnu/tegra" ]; then
    export LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu/tegra:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
fi

INPUT_YUV="suzie_qcif.yuv"
NCU_LAUNCHES="${NCU_LAUNCHES:-57}"   # 56 deconv_kernel + 1 spatial_reduction_kernel = 1 frame
GRID="32 8 256"                       # the paper's winning grid (Section V-A)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
command -v nvcc >/dev/null 2>&1 || die "nvcc not on PATH."
command -v python3 >/dev/null 2>&1 || die "python3 not on PATH (needed to parse ncu's quoted-CSV output correctly)."

# Nsight Compute is frequently installed as a *versioned* package
# (e.g. apt's "nsight-compute-2026.2.1") that drops its binary under a
# versioned directory without ever symlinking "ncu" onto PATH -- so
# `command -v ncu` alone is not reliable. Try PATH first, then every
# install layout we have actually seen, then a bounded filesystem search,
# and only as a last resort try to apt-install the unversioned meta
# package (which does register PATH) if we're root and apt is present.
find_ncu() {
    command -v ncu 2>/dev/null && return 0
    local cand
    for cand in /usr/local/cuda/bin/ncu \
                /opt/nvidia/nsight-compute/*/ncu \
                /opt/nvidia/nsight-compute-*/ncu \
                /usr/local/NVIDIA-Nsight-Compute*/ncu \
                /usr/local/cuda-*/bin/ncu; do
        [ -x "$cand" ] && echo "$cand" && return 0
    done
    find /opt /usr/local /usr/lib/nvidia 2>/dev/null -maxdepth 5 -type f -name ncu -perm -u+x -print -quit
}

# Respect an explicit override (NCU_BIN=/custom/path/ncu bash collect_ncu_profile.sh)
# before doing any auto-detection at all.
NCU_BIN="${NCU_BIN:-}"
[ -n "$NCU_BIN" ] || NCU_BIN="$(find_ncu)"

if [ -z "$NCU_BIN" ] && command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    warn "ncu not found anywhere on this machine; attempting 'apt-get install -y nsight-compute' (unversioned meta package, registers PATH)..."
    apt-get install -y nsight-compute >/tmp/_ncu_apt_install.log 2>&1 || true
    hash -r
    NCU_BIN="$(find_ncu)"
fi

[ -n "$NCU_BIN" ] || die "ncu (Nsight Compute) not found, and auto-install did not resolve it (see /tmp/_ncu_apt_install.log if it ran). Install manually with 'apt install nsight-compute', or if it's already installed under a custom path, run: NCU_BIN=/path/to/ncu bash $0"

info "Using ncu: $NCU_BIN"
[ -f "$INPUT_YUV" ] || die "missing $INPUT_YUV (run from plans/)"
[ -f "fsrcnn_gpu_main.cu" ] || die "missing fsrcnn_gpu_main.cu"
for i in 1 2 3 4 5 6 7 8; do
    for p in weights_layer biasess_layer; do
        [ -f "${p}${i}.txt" ] || die "missing ${p}${i}.txt"
    done
done

GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
case "$GPU_NAME" in
    *GB10*) TAG="gb10" ;;
    *4090*) TAG="rtx4090" ;;
    *)      TAG="unknown"
            warn "Could not identify the GPU from nvidia-smi (got '${GPU_NAME:-nothing}'); tagging output 'unknown'." ;;
esac

OUT_TXT="results_ncu_${TAG}.txt"
OUT_CSV="results_ncu_${TAG}.csv"
OUT_REP="results_ncu_${TAG}.ncu-rep"

# ---------------------------------------------------------------------------
# Build (same fallback -arch ladder as collect_gpu_profile.sh)
# ---------------------------------------------------------------------------
ARM_FLAGS=""
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    ARM_FLAGS="-D_BITS_MATH_VECTOR_H -D__Float32x4_t=void* -D__Float64x2_t=void* -D__SVFloat32_t=void* -D__SVFloat64_t=void* -D__SVBool_t=void*"
fi

rm -f ./fsrcnn_gpu_prof
built=0
for arch in native sm_121 sm_120 sm_90 sm_89 sm_87; do
    if nvcc -arch="$arch" $ARM_FLAGS -O3 -std=c++11 -Xcompiler -fopenmp \
            -Xcompiler -fno-tree-vectorize -o fsrcnn_gpu_prof fsrcnn_gpu_main.cu \
            -lm -lcudart 2>/dev/null; then
        info "built fsrcnn_gpu_prof (-arch=$arch)"
        built=1
        break
    fi
done
[ "$built" = "1" ] || die "could not compile fsrcnn_gpu_main.cu with any -arch option"

read -r BX BY TR <<< "$GRID"
info "Platform: ${GPU_NAME:-unknown}  tag=$TAG  grid=${BX}x${BY}_${TR}  launches=$NCU_LAUNCHES"

# ---------------------------------------------------------------------------
# Metric set. Kept small on purpose -- ncu's overhead scales with metric
# count because each extra metric group needs its own replay pass. This is
# exactly the four numbers Section VII currently infers from bandwidth
# arithmetic; if you want more (e.g. sector-level coalescing counters),
# open the .ncu-rep in the GUI instead of widening this list.
#
# dram__throughput.* does not exist on GB10 (confirmed via `ncu
# --query-metrics` on-device: GB10's Grace-Blackwell unified-memory design
# has no discrete DRAM/FBPA partition counters). gpu__compute_memory_
# throughput.avg.pct_of_peak_sustained_elapsed is requested alongside it as
# the closest cross-platform equivalent ("Compute Memory Pipeline
# Throughput", the whole SM<->Caches<->DRAM path). It is not a like-for-like
# swap for dram__throughput -- it is a broader aggregate -- so report both
# columns rather than treating them as interchangeable. Unsupported metrics
# are silently skipped by ncu rather than erroring the run, so requesting
# both on both platforms is safe.
# ---------------------------------------------------------------------------
METRICS="lts__t_sector_hit_rate.pct,lts__throughput.avg.pct_of_peak_sustained_elapsed,dram__throughput.avg.pct_of_peak_sustained_elapsed,gpu__compute_memory_throughput.avg.pct_of_peak_sustained_elapsed,sm__warps_active.avg.pct_of_peak_sustained_active"

info "Running ncu (this replays the first $NCU_LAUNCHES kernel launches several times -- expect a few minutes, not seconds)..."

# Two separate steps on purpose. Combining --csv/--log-file with -o in one
# invocation was tried first and silently swallowed the metrics table: with
# -o present, ncu writes the full result into the binary .ncu-rep and only
# prints its own Connected/Disconnected/"Report:" status lines to stdout,
# so --log-file just captured that status chatter instead of data. Step 1
# collects counters into the .ncu-rep; step 2 re-opens that saved report and
# asks it (and only it) for the CSV table, which is the documented way to
# get both a GUI-browsable report and a CSV export from the same run.
"$NCU_BIN" \
    --kernel-name-base function \
    --kernel-name "regex:deconv_kernel|spatial_reduction_kernel" \
    --launch-count "$NCU_LAUNCHES" \
    --metrics "$METRICS" \
    -o "${OUT_REP%.ncu-rep}" \
    -f \
    ./fsrcnn_gpu_prof "$INPUT_YUV" /tmp/_ncu_out.yuv "$BX" "$BY" "$TR" \
    > /tmp/_ncu_stdout.log 2>&1
STATUS=$?

if [ $STATUS -ne 0 ]; then
    if grep -qi "ERR_NVGPUCTRPERM\|permission" /tmp/_ncu_stdout.log 2>/dev/null; then
        cat /tmp/_ncu_stdout.log
        die "ncu was denied access to performance counters. Re-run with 'sudo bash collect_ncu_profile.sh', or see the header of this script for the permanent modprobe fix."
    fi
    cat /tmp/_ncu_stdout.log
    die "ncu exited with status $STATUS -- see output above."
fi

[ -f "$OUT_REP" ] || die "ncu did not produce $OUT_REP -- see /tmp/_ncu_stdout.log"

info "Re-opening $OUT_REP to export CSV..."
"$NCU_BIN" --import "$OUT_REP" --csv --page raw > "$OUT_CSV" 2>/tmp/_ncu_import.log
if [ ! -s "$OUT_CSV" ] || ! head -1 "$OUT_CSV" | grep -qi "Kernel Name"; then
    cat /tmp/_ncu_import.log
    die "CSV export from $OUT_REP did not look like a metrics table -- see /tmp/_ncu_import.log and inspect $OUT_REP by hand (ncu-ui / ncu --import)."
fi

rm -f /tmp/_ncu_out.yuv

# ---------------------------------------------------------------------------
# Summarize: mean per metric, split by kernel name, from ncu's own CSV.
#
# `--page raw` is wide format: one row per kernel launch, one column per
# metric (283 columns on GB10, 271 on RTX 4090 -- the two ncu versions/chips
# do not even agree on column order, so match by header NAME, never index).
# It also has a quoted "Kernel Name" column containing literal commas (the
# C++ argument list, e.g. "deconv_kernel(const double *, double *, ...)"),
# which a naive `awk -F','` would split incorrectly and misalign every
# column after it. Use python3's csv module instead, which both machines
# have by default, rather than depend on gawk-only FPAT csv parsing.
# ---------------------------------------------------------------------------
{
echo "=============================================================="
echo " FSRCNN Layer 8 -- Nsight Compute counters -- $TAG"
echo " gpu:       ${GPU_NAME:-unknown}"
echo " hostname:  $(hostname)"
echo " date:      $(date -Is)"
echo " grid:      ${BX}x${BY}_${TR} (paper's winning configuration)"
echo " launches:  $NCU_LAUNCHES (= 1 frame: 56x deconv_kernel + 1x spatial_reduction_kernel)"
echo "=============================================================="
echo
echo "Per-kernel mean of each metric (ncu CSV, matched by column name):"
echo

python3 - "$OUT_CSV" <<'PYEOF'
import csv, sys
from collections import defaultdict

path = sys.argv[1]
wanted = [
    "lts__t_sector_hit_rate.pct",
    "lts__throughput.avg.pct_of_peak_sustained_elapsed",
    "dram__throughput.avg.pct_of_peak_sustained_elapsed",
    "gpu__compute_memory_throughput.avg.pct_of_peak_sustained_elapsed",
    "sm__warps_active.avg.pct_of_peak_sustained_active",
]

with open(path, newline="") as f:
    r = csv.reader(f)
    header = next(r)
    idx = {name: header.index(name) for name in wanted if name in header}
    missing = [name for name in wanted if name not in header]
    kidx = header.index("Kernel Name") if "Kernel Name" in header else None

    sums = defaultdict(lambda: defaultdict(float))
    counts = defaultdict(int)
    for row in r:
        kname = row[kidx].split("(")[0] if kidx is not None else ""
        if not kname:
            continue
        counts[kname] += 1
        for name, i in idx.items():
            v = row[i].replace(",", "").replace("%", "").strip()
            try:
                sums[kname][name] += float(v)
            except ValueError:
                pass

for kname in sorted(counts):
    print(f"{kname} (n={counts[kname]})")
    for name in wanted:
        if name in idx:
            print(f"  {name:<70s} mean={sums[kname][name]/counts[kname]:.3f}")
        else:
            print(f"  {name:<70s} NOT AVAILABLE on this chip/ncu version")

if missing:
    print()
    print("Metrics not present in this export at all (skipped by ncu for this chip):")
    for name in missing:
        print(f"  - {name}")
PYEOF

echo
echo "Reading this: lts__t_sector_hit_rate.pct is the L2 hit rate the paper's"
echo "cache-boundary claim (Section IV-D / VI-D) currently infers from"
echo "bandwidth arithmetic. dram__throughput / gpu__compute_memory_throughput"
echo "and lts__throughput are the 'is it bandwidth-bound' checks -- GB10 has"
echo "no dram__ counters (unified-memory chip, confirmed via 'ncu"
echo "--query-metrics' on-device), so gpu__compute_memory_throughput is its"
echo "closest available equivalent; treat the two as different metrics, not"
echo "directly interchangeable, when comparing across platforms."
echo "sm__warps_active... is achieved occupancy, unrelated to the cache"
echo "claim but asked for by Reviewer 2."
echo
echo "Files to send back:"
echo "  $(pwd)/$OUT_TXT"
echo "  $(pwd)/$OUT_CSV"
echo "  $(pwd)/${OUT_REP}"
echo "=============================================================="
} | tee "$OUT_TXT"
