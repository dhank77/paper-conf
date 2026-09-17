#!/bin/bash
###############################################################################
# collect_l2_readwrite_profile.sh -- read-vs-write L2 breakdown for the
# GDDR6X-exceeding-peak anomaly (Section VII open question).
#
# RUN ON BOTH MACHINES: ASUS Ascent GX10 (GB10) *and* the RTX 4090 desktop.
#
# THE QUESTION THIS SCRIPT ANSWERS
# ---------------------------------------------------------------------------
# collect_ncu_profile.sh measured lts__t_sector_hit_rate.pct (a COMBINED
# read+write hit rate) at only 2.1% for spatial_reduction_kernel on the
# RTX 4090 -- too low, on its own, to explain why that kernel's *effective*
# bandwidth (bytes moved / measured time, from Table III) comes out to
# ~2,597 GB/s, 2.5x the RTX 4090's own 1,008 GB/s GDDR6X ceiling. A number
# that exceeds the physical DRAM ceiling can only be real if a large share
# of the reads are actually served by L2, not DRAM -- so either the combined
# hit-rate metric is hiding something, or the "effective bandwidth" estimate
# itself is off for an unrelated reason.
#
# spatial_reduction_kernel is close to 100% reads (it sums 56 channel planes
# someone else wrote a moment earlier; its own writes are a tiny 352x288
# output, ~0.3 MiB vs. the 43.3 MiB it reads). A hit rate that mixes reads
# and writes can dilute a high *read* hit rate with a low *write* hit rate
# (or vice versa) in a way that hides exactly the effect we're looking for.
# This script asks three more specific questions instead:
#
#   1. What is the L2 hit rate for READS only vs. WRITES only?
#      (lts__t_sector_op_read_hit_rate.pct / ..._write_hit_rate.pct)
#   2. In raw sector counts, how many read sectors were requested vs. hit?
#      (lts__t_sectors_srcunit_tex_op_read.sum and ..._lookup_hit.sum --
#      1 sector = 32 bytes, so this converts straight to a byte-level
#      cache-hit fraction, independent of whatever "hit rate" a percentage
#      metric happens to normalize by.)
#   3. Ground truth: how many bytes actually left the chip and touched
#      DRAM? (dram__bytes_read.sum, RTX 4090 only -- GB10 has no discrete
#      DRAM/FBPA counters, confirmed in the collect_ncu_profile.sh run.)
#      If this is much smaller than 43.3 MiB per launch, that alone proves
#      most of the traffic never reached DRAM, regardless of what any
#      "hit rate" percentage says.
#
# Only spatial_reduction_kernel is profiled (not deconv_kernel) to keep this
# fast and focused -- deconv_kernel isn't the kernel with the anomaly.
#
# Usage:  bash collect_l2_readwrite_profile.sh
#         NCU_FRAMES=5 bash collect_l2_readwrite_profile.sh   # more launches
# Output: results_l2rw_<tag>.txt/.csv/.ncu-rep -- send all three back.
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
NCU_FRAMES="${NCU_FRAMES:-3}"   # spatial_reduction_kernel = 1 launch/frame
GRID="32 8 256"                  # the paper's winning grid (Section V-A)
BYTES_PER_LAUNCH=$((56 * 352 * 288 * 8))  # 43.3 MiB private buffer, one full read per launch

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Preconditions (same detection logic as collect_ncu_profile.sh)
# ---------------------------------------------------------------------------
command -v nvcc >/dev/null 2>&1 || die "nvcc not on PATH."
command -v python3 >/dev/null 2>&1 || die "python3 not on PATH."

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

NCU_BIN="${NCU_BIN:-}"
[ -n "$NCU_BIN" ] || NCU_BIN="$(find_ncu)"
if [ -z "$NCU_BIN" ] && command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    warn "ncu not found; attempting 'apt-get install -y nsight-compute'..."
    apt-get install -y nsight-compute >/tmp/_ncu_apt_install.log 2>&1 || true
    hash -r
    NCU_BIN="$(find_ncu)"
fi
[ -n "$NCU_BIN" ] || die "ncu not found. Install with 'apt install nsight-compute', or set NCU_BIN=/path/to/ncu."
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
    *)      TAG="unknown"; warn "Could not identify GPU from nvidia-smi." ;;
esac

OUT_TXT="results_l2rw_${TAG}.txt"
OUT_CSV="results_l2rw_${TAG}.csv"
OUT_REP="results_l2rw_${TAG}.ncu-rep"

# ---------------------------------------------------------------------------
# Build
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
info "Platform: ${GPU_NAME:-unknown}  tag=$TAG  grid=${BX}x${BY}_${TR}  frames=$NCU_FRAMES (spatial_reduction_kernel only)"

# ---------------------------------------------------------------------------
# Metrics. Requesting a generous list on purpose: ncu silently drops any
# metric name unsupported on a given chip rather than erroring the run
# (already confirmed empirically with collect_ncu_profile.sh on GB10), so
# there is no cost to asking for read/write-split and raw-sector metrics
# even though we are not 100% certain every name below exists on both
# chips/ncu versions.
# ---------------------------------------------------------------------------
METRICS="lts__t_sector_op_read_hit_rate.pct,lts__t_sector_op_write_hit_rate.pct,lts__t_sectors_srcunit_tex_op_read.sum,lts__t_sectors_srcunit_tex_op_read_lookup_hit.sum,dram__bytes_read.sum,dram__bytes.sum"

info "Running ncu on spatial_reduction_kernel only (this is a short kernel; ncu's replay overhead dominates wall time here, expect a minute or two)..."

"$NCU_BIN" \
    --kernel-name-base function \
    --kernel-name "regex:spatial_reduction_kernel" \
    --launch-count "$NCU_FRAMES" \
    --metrics "$METRICS" \
    -o "${OUT_REP%.ncu-rep}" \
    -f \
    ./fsrcnn_gpu_prof "$INPUT_YUV" /tmp/_ncu_l2rw_out.yuv "$BX" "$BY" "$TR" \
    > /tmp/_ncu_l2rw_stdout.log 2>&1
STATUS=$?

if [ $STATUS -ne 0 ]; then
    if grep -qi "ERR_NVGPUCTRPERM\|permission" /tmp/_ncu_l2rw_stdout.log 2>/dev/null; then
        cat /tmp/_ncu_l2rw_stdout.log
        die "ncu was denied access to performance counters. Re-run with 'sudo bash $0'."
    fi
    cat /tmp/_ncu_l2rw_stdout.log
    die "ncu exited with status $STATUS -- see output above."
fi
[ -f "$OUT_REP" ] || die "ncu did not produce $OUT_REP -- see /tmp/_ncu_l2rw_stdout.log"

info "Re-opening $OUT_REP to export CSV..."
"$NCU_BIN" --import "$OUT_REP" --csv --page raw > "$OUT_CSV" 2>/tmp/_ncu_l2rw_import.log
if [ ! -s "$OUT_CSV" ] || ! head -1 "$OUT_CSV" | grep -qi "Kernel Name"; then
    cat /tmp/_ncu_l2rw_import.log
    die "CSV export from $OUT_REP did not look like a metrics table -- see /tmp/_ncu_l2rw_import.log"
fi
rm -f /tmp/_ncu_l2rw_out.yuv

# ---------------------------------------------------------------------------
# Summarize + interpret
# ---------------------------------------------------------------------------
{
echo "=============================================================="
echo " spatial_reduction_kernel -- L2 read/write breakdown -- $TAG"
echo " gpu:       ${GPU_NAME:-unknown}"
echo " hostname:  $(hostname)"
echo " date:      $(date -Is)"
echo " grid:      ${BX}x${BY}_${TR}"
echo " launches:  $NCU_FRAMES (1 per frame)"
echo " algorithmic bytes read per launch: $BYTES_PER_LAUNCH (43.3 MiB private buffer)"
echo "=============================================================="
echo

python3 - "$OUT_CSV" "$BYTES_PER_LAUNCH" <<'PYEOF'
import csv, sys
from collections import defaultdict

path = sys.argv[1]
bytes_per_launch = int(sys.argv[2])
SECTOR_BYTES = 32  # NVIDIA L2 sector size, fixed across architectures

wanted = [
    "lts__t_sector_op_read_hit_rate.pct",
    "lts__t_sector_op_write_hit_rate.pct",
    "lts__t_sectors_srcunit_tex_op_read.sum",
    "lts__t_sectors_srcunit_tex_op_read_lookup_hit.sum",
    "dram__bytes_read.sum",
    "dram__bytes.sum",
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
    n = counts[kname]
    print(f"{kname} (n={n} launches)")
    for name in wanted:
        if name in idx:
            print(f"  {name:<55s} mean={sums[kname][name]/n:.3f}")
        else:
            print(f"  {name:<55s} NOT AVAILABLE on this chip/ncu version")

    read_sec = sums[kname].get("lts__t_sectors_srcunit_tex_op_read.sum")
    hit_sec = sums[kname].get("lts__t_sectors_srcunit_tex_op_read_lookup_hit.sum")
    if read_sec is not None and hit_sec is not None and read_sec > 0:
        read_bytes = read_sec * SECTOR_BYTES / n
        hit_bytes = hit_sec * SECTOR_BYTES / n
        print(f"  -> implied read bytes/launch from sectors: {read_bytes/1e6:.2f} MB "
              f"(algorithmic buffer: {bytes_per_launch/1e6:.2f} MB)")
        print(f"  -> implied L2-hit bytes/launch: {hit_bytes/1e6:.2f} MB "
              f"({100*hit_bytes/read_bytes:.1f}% of read traffic)")

    dram_read = sums[kname].get("dram__bytes_read.sum")
    if dram_read is not None:
        dram_bytes_per_launch = dram_read / n
        print(f"  -> DRAM bytes actually read/launch: {dram_bytes_per_launch/1e6:.2f} MB "
              f"(algorithmic buffer: {bytes_per_launch/1e6:.2f} MB, "
              f"{100*dram_bytes_per_launch/bytes_per_launch:.1f}% of it)")

if missing:
    print()
    print("Metrics not present in this export at all (skipped by ncu for this chip):")
    for name in missing:
        print(f"  - {name}")
PYEOF

echo
echo "Reading this:"
echo "  - If 'DRAM bytes actually read/launch' is much smaller than the 43.3 MB"
echo "    algorithmic buffer size, most of the read traffic never touched DRAM"
echo "    -- direct, hit-rate-percentage-independent proof of caching, and the"
echo "    likely resolution to the GDDR6X-exceeding-peak anomaly (Section VII)."
echo "  - If read hit rate is much higher than the combined (read+write) hit"
echo "    rate collect_ncu_profile.sh reported (2.1% on RTX 4090), the mix of"
echo "    reads and writes in the combined metric was hiding a real read-side"
echo "    caching effect -- this would explain the anomaly without contradicting"
echo "    the earlier, correctly-reported combined number."
echo "  - dram__bytes_read.sum is not available on GB10 (no discrete DRAM/FBPA"
echo "    partition on this unified-memory chip); the sector-based estimate"
echo "    above is the only ground-truth check available there."
echo
echo "Files to send back:"
echo "  $(pwd)/$OUT_TXT"
echo "  $(pwd)/$OUT_CSV"
echo "  $(pwd)/${OUT_REP}"
echo "=============================================================="
} | tee "$OUT_TXT"
