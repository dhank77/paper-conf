#!/bin/bash
###############################################################################
# collect_fp16_comparison.sh -- what bit-exact determinism costs in throughput.
#
# RUN ON BOTH MACHINES: ASUS Ascent GX10 (GB10) *and* the RTX 4090 desktop.
#
# Reviewer 2 asked for an FP32/FP16/BF16 trade-off study; the Limitations
# section (Section VII) names this as the natural next experiment but does
# not run it. This script builds fsrcnn_gpu_fp16.cu in both fp16 and bf16
# modes, runs each against the paper's winning grid (32x8_256), and reports:
#   - wall time and GPU Layer-8 kernel time, next to the double-precision
#     production binary (fsrcnn_gpu_main.cu) as the baseline
#   - diff_bytes / PSNR-Y / SSIM against ground_truth.yuv (the V1 serial
#     double-precision reference), since fp16/bf16 will NOT be bit-exact --
#     that is the whole point of the comparison, not a bug
#
# Requires ground_truth.yuv in this directory. If missing, generate it first
# with:  ./run_experiments.sh --phase0
#
# Usage:  bash collect_fp16_comparison.sh
#         REPS=6 bash collect_fp16_comparison.sh
# Output: results_fp16_<tag>.txt   (human-readable summary)
#         results_fp16_<tag>.csv   (one row per rep x variant)
#         Send both back.
###############################################################################

set -uo pipefail
cd "$(dirname "$0")"

if [ -d "/usr/local/cuda/bin" ]; then
    export PATH="/usr/local/cuda/bin:${PATH}"
fi
if [ -d "/usr/lib/aarch64-linux-gnu/tegra" ]; then
    export LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu/tegra:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
fi

REPS="${REPS:-6}"
INPUT_YUV="suzie_qcif.yuv"
GROUND_TRUTH="ground_truth.yuv"
GRID="32 8 256"     # the paper's winning grid (Section V-A)
WIDTH=176; HEIGHT=144; SCALE=2
OUTPUT_W=$((WIDTH * SCALE))
OUTPUT_H=$((HEIGHT * SCALE))

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
command -v nvcc >/dev/null 2>&1 || die "nvcc not on PATH."
command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found -- required for PSNR/SSIM."
[ -f "$INPUT_YUV" ] || die "missing $INPUT_YUV (run from plans/)"
[ -f "$GROUND_TRUTH" ] || die "missing $GROUND_TRUTH -- generate it first with: ./run_experiments.sh --phase0"
for f in fsrcnn_gpu_main.cu fsrcnn_gpu_fp16.cu; do
    [ -f "$f" ] || die "missing $f"
done
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

OUT_TXT="results_fp16_${TAG}.txt"
OUT_CSV="results_fp16_${TAG}.csv"
RAW_LOG="results_fp16_${TAG}.rawlog"
: > "$RAW_LOG"

# ---------------------------------------------------------------------------
# Build. Double-precision baseline + fp16 + bf16, same fallback -arch ladder
# used elsewhere in plans/.
# ---------------------------------------------------------------------------
ARM_FLAGS=""
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    ARM_FLAGS="-D_BITS_MATH_VECTOR_H -D__Float32x4_t=void* -D__Float64x2_t=void* -D__SVFloat32_t=void* -D__SVFloat64_t=void* -D__SVBool_t=void*"
fi

build_cu() {
    local src="$1" bin="$2"; shift 2
    local extra_flags="$*"
    rm -f "$bin"
    for arch in native sm_121 sm_120 sm_90 sm_89 sm_87; do
        if nvcc -arch="$arch" $ARM_FLAGS $extra_flags -O3 -std=c++11 -Xcompiler -fopenmp \
                -Xcompiler -fno-tree-vectorize -o "$bin" "$src" -lm -lcudart 2>/dev/null; then
            info "built $bin from $src (-arch=$arch${extra_flags:+, $extra_flags})"
            return 0
        fi
    done
    die "could not compile $src -> $bin with any -arch option"
}

build_cu fsrcnn_gpu_main.cu ./fsrcnn_gpu_fp64ref
build_cu fsrcnn_gpu_fp16.cu ./fsrcnn_gpu_fp16
build_cu fsrcnn_gpu_fp16.cu ./fsrcnn_gpu_bf16 -DUSE_BF16

read -r BX BY TR <<< "$GRID"
info "Platform: ${GPU_NAME:-unknown}  tag=$TAG  grid=${BX}x${BY}_${TR}  reps=$REPS"

# ---------------------------------------------------------------------------
# Helpers (same conventions as run_experiments.sh)
# ---------------------------------------------------------------------------
count_diff_bytes() { cmp -l "$1" "$2" 2>/dev/null | wc -l; }

psnr_full_line() {
    ffmpeg -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$1" \
           -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$2" \
           -lavfi "psnr" -f null - 2>&1 | grep -i "PSNR y:" | tail -1
}

psnr_y() {
    local line; line="$(psnr_full_line "$1" "$2")"
    echo "$line" | sed -E 's/.*y:([0-9.]+|inf).*/\1/'
}

ssim_all() {
    ffmpeg -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$1" \
           -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$2" \
           -lavfi "ssim" -f null - 2>&1 | grep -i "All:" | tail -1 | sed -E 's/.*All:([0-9.]+).*/\1/'
}

meansd() {
    awk '$0 ~ /^[ \t]*-?[0-9]+(\.[0-9]+)?[ \t]*$/ { n++; s+=$1; q+=$1*$1 }
         END { if (n==0) { printf "%17s", "no data"; exit }
               m=s/n;
               v=(n>1) ? (q - n*m*m)/(n-1) : 0;
               if (v<0) v=0;
               printf "%8.2f +/- %-6.2f", m, sqrt(v) }'
}

echo "tag,variant,rep,wall_ms,cpu_l17_ms,h2d_ms,gpu_l8_ms,d2h_ms,diff_bytes,psnr_y_db,ssim,vram_kb" > "$OUT_CSV"

declare -a SUMMARY

run_variant() {
    local bin="$1" variant="$2"
    local out_yuv="/tmp/_fp16cmp_${variant}.yuv"
    info "--- $variant : $REPS reps ---"
    local walls=() l17=() h2d=() l8=() d2h=() vram="" diffs=() psnrs=() ssims=()
    for r in $(seq 1 "$REPS"); do
        local tmp; tmp="$(mktemp)"
        local start end wall
        start=$(date +%s%N)
        "$bin" "$INPUT_YUV" "$out_yuv" "$BX" "$BY" "$TR" >"$tmp" 2>&1
        local status=$?
        end=$(date +%s%N)
        wall=$(( (end - start) / 1000000 ))
        { echo "### variant=$variant rep=$r wall_ms=$wall status=$status"; cat "$tmp"; echo; } >> "$RAW_LOG"
        if [ $status -ne 0 ]; then
            rm -f "$tmp"
            die "run failed ($variant, rep $r) -- see $RAW_LOG"
        fi
        local prof; prof="$(grep -F '[PROFILING]' "$tmp" | tail -1)"
        rm -f "$tmp"
        field() { echo "$2" | tr ' ' '\n' | grep "^$1=" | cut -d= -f2; }
        local c h g d vk
        c="$(field cpu_l17_ms "$prof")"; h="$(field h2d_ms "$prof")"
        g="$(field gpu_l8_ms "$prof")"; d="$(field d2h_ms "$prof")"
        vk="$(field vram_kb "$prof")"
        walls+=("$wall"); l17+=("$c"); h2d+=("$h"); l8+=("$g"); d2h+=("$d"); vram="$vk"

        local diff psnr ssim
        diff="$(count_diff_bytes "$GROUND_TRUTH" "$out_yuv")"
        if [ "$diff" -eq 0 ]; then
            psnr="inf"; ssim="1.000000"
        else
            psnr="$(psnr_y "$GROUND_TRUTH" "$out_yuv")"
            ssim="$(ssim_all "$GROUND_TRUTH" "$out_yuv")"
        fi
        diffs+=("$diff")

        echo "$TAG,$variant,$r,$wall,$c,$h,$g,$d,$diff,$psnr,$ssim,$vk" >> "$OUT_CSV"
        printf "    rep %d/%d  wall=%s ms  gpu_l8=%s ms  diff_bytes=%s  psnr_y=%s dB  ssim=%s\n" \
            "$r" "$REPS" "$wall" "$g" "$diff" "$psnr" "$ssim"
    done
    rm -f "$out_yuv"

    SUMMARY+=("$(printf '%-12s %s | %s | %s | last_diff=%-10s last_psnr_y=%-10s last_ssim=%s' \
        "$variant" \
        "$(printf '%s\n' "${walls[@]}" | meansd)" \
        "$(printf '%s\n' "${l8[@]}"    | meansd)" \
        "$(printf '%s\n' "${l17[@]}"   | meansd)" \
        "${diffs[-1]}" "$psnr" "$ssim")")
}

info "=== fp64 (production binary, the paper's bit-exact reference) ==="
run_variant ./fsrcnn_gpu_fp64ref fp64
info "=== fp16 ==="
run_variant ./fsrcnn_gpu_fp16 fp16
info "=== bf16 ==="
run_variant ./fsrcnn_gpu_bf16 bf16

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
{
echo "=============================================================="
echo " FSRCNN Layer 8 -- precision trade-off -- $TAG"
echo " gpu:       ${GPU_NAME:-unknown}"
echo " hostname:  $(hostname)"
echo " date:      $(date -Is)"
echo " grid:      ${BX}x${BY}_${TR} (paper's winning configuration)"
echo " reps:      $REPS per variant"
echo " frames:    150, 176x144 -> 352x288"
echo " reference: $GROUND_TRUTH (V1 serial, double precision)"
echo "=============================================================="
echo
printf "%-12s %-19s | %-19s | %-19s | %s\n" "variant" "wall (ms)" "gpu_l8 (ms)" "cpu_l17 (ms)" "last-rep correctness"
printf "%s\n" "-------------------------------------------------------------------------------------------------------"
for row in "${SUMMARY[@]}"; do echo "$row"; done
echo
echo "Reading this: fp64 should show diff_bytes=0 (bit-exact) -- if it does"
echo "not, something in this environment differs from the paper's build and"
echo "the fp16/bf16 numbers below are not trustworthy either. fp16/bf16 are"
echo "expected to have diff_bytes > 0; the PSNR-Y/SSIM columns quantify how"
echo "much accuracy was traded for whatever speedup gpu_l8 shows."
echo
echo "Files to send back:"
echo "  $(pwd)/$OUT_TXT"
echo "  $(pwd)/$OUT_CSV"
echo "  $(pwd)/$RAW_LOG"
echo "=============================================================="
} | tee "$OUT_TXT"
