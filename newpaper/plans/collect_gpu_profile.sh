#!/bin/bash
###############################################################################
# collect_gpu_profile.sh -- GPU timing breakdown with dispersion.
#
# RUN ON BOTH MACHINES: ASUS Ascent GX10 (GB10) *and* the RTX 4090 desktop.
# Roughly 5-8 minutes per machine. Nothing to photograph, nothing to babysit.
#
# Covers three separate asks from reviews/03.md in one pass:
#
#   (a) H2D/D2H breakdown on the RTX 4090. Table III only has the GB10 column,
#       which leaves the unified-vs-discrete comparison in the paper's own
#       title unevidenced. The production binary already emits h2d_ms/d2h_ms
#       on stderr; nobody had collected it on the discrete side.
#
#   (b) Standard deviation for the GPU kernel time. results/gpu-4.txt reports
#       gpu_l8_ms as a bare point estimate (541.59 ms) with no spread, while
#       wall time gets a +/-. Fig. 3's warp-alignment bars inherit that gap:
#       the 541.59-vs-701.51 claim has no error bar behind it.
#
#   (c) Splitting deconv_kernel from spatial_reduction_kernel in Table III.
#       Phase B uses fsrcnn_gpu_instrumented.cu for this -- see the note at
#       the bottom about why it is a second binary and not the same one.
#
# All five grid configurations from the original sweep are re-run, so (b) and
# (c) land on every bar in Fig. 3 rather than just the winner.
#
# Usage:  bash collect_gpu_profile.sh
#         REPS=10 bash collect_gpu_profile.sh     # more reps if you have time
# Output: results_gpuprofile_<tag>.txt   (human-readable summary + raw log)
#         results_gpuprofile_<tag>.csv   (one row per rep, for plotting)
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

# The five configurations from the original sweep, in the order Fig. 3 plots
# them: "block_x block_y threads_reduce".
CONFIGS=(
    "16 16 256"
    "8  8  256"
    "32 8  256"
    "16 16 128"
    "16 16 512"
)

# ---------------------------------------------------------------------------
# Platform identification. The backdrop thread count for layers 1-7 has to
# match what the published runs used, or the wall-clock column stops being
# comparable: 20 on the GB10, 4 on the RTX 4090 (Intel P-cores only).
# ---------------------------------------------------------------------------
GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
case "$GPU_NAME" in
    *GB10*) TAG="gb10";    DEFAULT_BACKDROP=20 ;;
    *4090*) TAG="rtx4090"; DEFAULT_BACKDROP=4  ;;
    *)      TAG="unknown"
            if [ "$(uname -m)" = "x86_64" ]; then DEFAULT_BACKDROP=4; else DEFAULT_BACKDROP=20; fi ;;
esac
BACKDROP="${GPU_BACKDROP_THREADS:-$DEFAULT_BACKDROP}"

OUT_TXT="results_gpuprofile_${TAG}.txt"
OUT_CSV="results_gpuprofile_${TAG}.csv"
RAW_LOG="results_gpuprofile_${TAG}.rawlog"
: > "$RAW_LOG"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
command -v nvcc >/dev/null 2>&1 || die "nvcc not on PATH."
[ -f "$INPUT_YUV" ] || die "missing $INPUT_YUV (run from plans/)"
for f in fsrcnn_gpu_main.cu fsrcnn_gpu_instrumented.cu; do
    [ -f "$f" ] || die "missing $f"
done
for i in 1 2 3 4 5 6 7 8; do
    for p in weights_layer biasess_layer; do
        [ -f "${p}${i}.txt" ] || die "missing ${p}${i}.txt"
    done
done

if [ "$TAG" = "unknown" ]; then
    warn "Could not identify the GPU from nvidia-smi (got '${GPU_NAME:-nothing}')."
    warn "Output will be tagged 'unknown'; rename it before sending it back."
fi

# ---------------------------------------------------------------------------
# Build. Always fresh: plans/ is synced between an aarch64 box and an x86_64
# box, so a leftover binary is either the wrong architecture or -- worse --
# silently the wrong build.
# ---------------------------------------------------------------------------
ARM_FLAGS=""
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    ARM_FLAGS="-D_BITS_MATH_VECTOR_H -D__Float32x4_t=void* -D__Float64x2_t=void* -D__SVFloat32_t=void* -D__SVFloat64_t=void* -D__SVBool_t=void*"
fi

build_cu() {
    local src="$1" bin="$2"
    rm -f "$bin"
    for arch in native sm_121 sm_120 sm_90 sm_89 sm_87; do
        if nvcc -arch="$arch" $ARM_FLAGS -O3 -std=c++11 -Xcompiler -fopenmp \
                -Xcompiler -fno-tree-vectorize -o "$bin" "$src" -lm -lcudart 2>/dev/null; then
            # Progress goes to stderr; stdout carries only the arch, because
            # the caller captures it.
            info "built $bin from $src (-arch=$arch)" >&2
            echo "$arch"
            return 0
        fi
    done
    die "could not compile $src with any -arch option"
}

info "Platform: ${GPU_NAME:-unknown}  tag=$TAG  backdrop threads=$BACKDROP  reps=$REPS"
ARCH_USED="$(build_cu fsrcnn_gpu_main.cu ./fsrcnn_gpu_prof)"
build_cu fsrcnn_gpu_instrumented.cu ./fsrcnn_gpu_instr >/dev/null

export OMP_NUM_THREADS="$BACKDROP"

echo "tag,phase,block_x,block_y,threads_reduce,rep,wall_ms,cpu_l17_ms,h2d_ms,gpu_l8_ms,d2h_ms,deconv_ms,reduce_ms,in_window_other_ms,vram_kb" > "$OUT_CSV"

# ---------------------------------------------------------------------------
# One measured run. Returns the parsed fields on stdout, appends everything
# the binary said to the raw log so nothing is lost if parsing goes wrong.
# ---------------------------------------------------------------------------
run_once() {
    local bin="$1" bx="$2" by="$3" tr="$4" rep="$5" phase="$6"
    local tmp; tmp="$(mktemp)"
    local start end wall

    start=$(date +%s%N)
    "$bin" "$INPUT_YUV" "/tmp/_prof_out_${TAG}.yuv" "$bx" "$by" "$tr" >"$tmp" 2>&1
    local status=$?
    end=$(date +%s%N)
    wall=$(( (end - start) / 1000000 ))

    {
        echo "### phase=$phase config=${bx}x${by}_${tr} rep=$rep wall_ms=$wall status=$status"
        cat "$tmp"
        echo
    } >> "$RAW_LOG"

    # This runs inside a command substitution, so a bare exit here would only
    # kill the subshell and the message would be swallowed into the caller's
    # variable. Signal failure in-band and let the caller stop the script.
    if [ $status -ne 0 ]; then
        rm -f "$tmp"
        echo "FAIL"
        return 1
    fi

    local prof split
    prof="$(grep -F '[PROFILING]' "$tmp" | tail -1)"
    split="$(grep -F '[KERNELSPLIT]' "$tmp" | tail -1)"
    rm -f "$tmp"

    if [ -z "$prof" ]; then
        echo "FAIL"
        return 1
    fi

    field() { echo "$2" | tr ' ' '\n' | grep "^$1=" | cut -d= -f2; }

    echo "$wall|$(field cpu_l17_ms "$prof")|$(field h2d_ms "$prof")|$(field gpu_l8_ms "$prof")|$(field d2h_ms "$prof")|$(field deconv_ms "$split")|$(field reduce_ms "$split")|$(field in_window_other_ms "$split")|$(field vram_kb "$prof")"
}

# "mean +/- sample SD" of the numbers arriving on stdin, one per line.
# Sample SD (n-1), not population: these are repeated draws, not the universe.
# Blank or non-numeric lines are skipped rather than silently counted as zero,
# and the count is printed so a partial parse cannot masquerade as a result.
meansd() {
    awk '$0 ~ /^[ \t]*-?[0-9]+(\.[0-9]+)?[ \t]*$/ { n++; s+=$1; q+=$1*$1 }
         END { if (n==0) { printf "%17s", "no data"; exit }
               m=s/n;
               v=(n>1) ? (q - n*m*m)/(n-1) : 0;
               if (v<0) v=0;
               printf "%8.2f +/- %-6.2f", m, sqrt(v) }'
}

declare -a SUMMARY_A SUMMARY_B

# ---------------------------------------------------------------------------
# Phase A -- production binary. These are the numbers that belong in the paper.
# ---------------------------------------------------------------------------
info "=== Phase A: production binary (fsrcnn_gpu_main.cu) ==="
for cfg in "${CONFIGS[@]}"; do
    read -r bx by tr <<< "$cfg"
    info "--- config ${bx}x${by}, reduce=${tr} : $REPS reps ---"
    walls=(); l17=(); h2d=(); l8=(); d2h=(); vram=""
    for r in $(seq 1 "$REPS"); do
        line="$(run_once ./fsrcnn_gpu_prof "$bx" "$by" "$tr" "$r" A)"
        [ "$line" = "FAIL" ] && die "run failed (A, ${bx}x${by}_${tr}, rep $r) -- see $RAW_LOG"
        IFS='|' read -r w c h g d _dc _rd _iw vk <<< "$line"
        walls+=("$w"); l17+=("$c"); h2d+=("$h"); l8+=("$g"); d2h+=("$d"); vram="$vk"
        echo "$TAG,A,$bx,$by,$tr,$r,$w,$c,$h,$g,$d,,,,$vk" >> "$OUT_CSV"
        printf "    rep %d/%d  wall=%s ms  gpu_l8=%s ms  h2d=%s ms  d2h=%s ms\n" "$r" "$REPS" "$w" "$g" "$h" "$d"
    done
    SUMMARY_A+=("$(printf '%-14s %s | %s | %s | %s | %s | %s' \
        "${bx}x${by}_${tr}" \
        "$(printf '%s\n' "${walls[@]}" | meansd)" \
        "$(printf '%s\n' "${l8[@]}"   | meansd)" \
        "$(printf '%s\n' "${h2d[@]}"  | meansd)" \
        "$(printf '%s\n' "${d2h[@]}"  | meansd)" \
        "$(printf '%s\n' "${l17[@]}"  | meansd)" \
        "$vram")")
done

# ---------------------------------------------------------------------------
# Phase B -- instrumented binary, per-kernel split.
#
# Read the numbers this produces as a decomposition of gpu_l8_ms, not as a
# replacement for it. gpu_l8_ms brackets the entire launch sequence, and the
# 56 per-channel H2D copies are issued *inside* that bracket, so
# deconv + reduce will come out below gpu_l8_ms. The gap is reported as
# in_window_other_ms rather than quietly folded into one of the kernels.
# ---------------------------------------------------------------------------
info "=== Phase B: instrumented binary (per-kernel split) ==="
for cfg in "${CONFIGS[@]}"; do
    read -r bx by tr <<< "$cfg"
    info "--- config ${bx}x${by}, reduce=${tr} : $REPS reps ---"
    dc=(); rd=(); iw=(); l8b=()
    for r in $(seq 1 "$REPS"); do
        line="$(run_once ./fsrcnn_gpu_instr "$bx" "$by" "$tr" "$r" B)"
        [ "$line" = "FAIL" ] && die "run failed (B, ${bx}x${by}_${tr}, rep $r) -- see $RAW_LOG"
        IFS='|' read -r w c h g d dcv rdv iwv vk <<< "$line"
        dc+=("$dcv"); rd+=("$rdv"); iw+=("$iwv"); l8b+=("$g")
        echo "$TAG,B,$bx,$by,$tr,$r,$w,$c,$h,$g,$d,$dcv,$rdv,$iwv,$vk" >> "$OUT_CSV"
        printf "    rep %d/%d  deconv=%s ms  reduce=%s ms  in-window other=%s ms  (gpu_l8=%s ms)\n" \
            "$r" "$REPS" "$dcv" "$rdv" "$iwv" "$g"
    done
    SUMMARY_B+=("$(printf '%-14s %s | %s | %s | %s' \
        "${bx}x${by}_${tr}" \
        "$(printf '%s\n' "${dc[@]}"  | meansd)" \
        "$(printf '%s\n' "${rd[@]}"  | meansd)" \
        "$(printf '%s\n' "${iw[@]}"  | meansd)" \
        "$(printf '%s\n' "${l8b[@]}" | meansd)")")
done

rm -f "/tmp/_prof_out_${TAG}.yuv"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
{
echo "=============================================================="
echo " FSRCNN GPU profile -- $TAG"
echo " gpu:       ${GPU_NAME:-unknown}"
echo " hostname:  $(hostname)"
echo " date:      $(date -Is)"
echo " arch used: -arch=$ARCH_USED"
echo " backdrop:  OMP_NUM_THREADS=$BACKDROP (layers 1-7)"
echo " reps:      $REPS per configuration"
echo " frames:    150, 176x144 -> 352x288"
echo "=============================================================="
echo
echo "PHASE A -- production binary. Use these for the paper."
echo "All figures are mean +/- sample SD over $REPS reps, milliseconds,"
echo "totalled across all 150 frames."
echo
printf "%-14s %-19s | %-19s | %-19s | %-19s | %-19s | %s\n" \
    "config" "wall" "gpu_l8" "h2d" "d2h" "cpu_l17" "vram_kb"
printf "%s\n" "----------------------------------------------------------------------------------------------------------------------------------"
for row in "${SUMMARY_A[@]}"; do echo "$row"; done
echo
echo "PHASE B -- instrumented binary. Decomposition of gpu_l8 only;"
echo "do not quote these as standalone timings."
echo
printf "%-14s %-19s | %-19s | %-19s | %s\n" \
    "config" "deconv (56x)" "reduction (1x)" "in-window other" "gpu_l8 (instr.)"
printf "%s\n" "--------------------------------------------------------------------------------------"
for row in "${SUMMARY_B[@]}"; do echo "$row"; done
echo
echo "Reading Phase B: 'in-window other' is the 56 per-channel H2D copies"
echo "issued inside the event bracket, plus launch gaps. deconv + reduction +"
echo "in-window other = gpu_l8. If Phase B's gpu_l8 differs noticeably from"
echo "Phase A's, the instrumentation is perturbing the run and the split"
echo "should be reported as indicative rather than exact."
echo
echo "Files to send back:"
echo "  $(pwd)/$OUT_TXT"
echo "  $(pwd)/$OUT_CSV"
echo "  $(pwd)/$RAW_LOG"
echo "=============================================================="
} | tee "$OUT_TXT"
