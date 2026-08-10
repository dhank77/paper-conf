#!/bin/bash
###############################################################################
# collect_layer_timing.sh -- per-layer breakdown of CPU Layers 1-7.
#
# RUN ON BOTH MACHINES: ASUS Ascent GX10 (GB10) *and* the RTX 4090 desktop.
# About 4 minutes per machine.
#
# Why: Table III reports Layers 1-7 as a single lump that is 71.4% of wall time
# on the GB10 and 84.5% on the RTX 4090. The paper's Amdahl argument concludes
# that offloading those layers is the only remaining path to sub-second
# reconstruction, but it cannot say WHICH of the seven to start with, because
# they have never been timed separately. This script closes that gap.
#
# The timers are clock_gettime around straight-line CPU code, so overhead is
# nanoseconds against milliseconds of work. Unlike the CUDA-event
# instrumentation of collect_gpu_profile.sh, this does not perturb the run,
# and the script checks that directly by comparing total wall time against the
# production binary.
#
# Usage:  bash collect_layer_timing.sh
#         REPS=10 bash collect_layer_timing.sh
# Output: results_layertiming_<tag>.{txt,csv}  -- send both back.
###############################################################################

set -uo pipefail
cd "$(dirname "$0")"

[ -d /usr/local/cuda/bin ] && export PATH="/usr/local/cuda/bin:${PATH}"
[ -d /usr/lib/aarch64-linux-gnu/tegra ] && \
    export LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu/tegra:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

REPS="${REPS:-6}"
INPUT_YUV="suzie_qcif.yuv"
CFG="32 8 256"          # the winning grid, same as Table III

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
die(){  echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
case "$GPU_NAME" in
    *GB10*) TAG="gb10";    BACKDROP=20 ;;
    *4090*) TAG="rtx4090"; BACKDROP=4  ;;
    *)      TAG="unknown"
            if [ "$(uname -m)" = "x86_64" ]; then BACKDROP=4; else BACKDROP=20; fi
            warn "GPU not recognised ('${GPU_NAME:-none}'); tagging output 'unknown'." ;;
esac
BACKDROP="${GPU_BACKDROP_THREADS:-$BACKDROP}"

OUT_TXT="results_layertiming_${TAG}.txt"
OUT_CSV="results_layertiming_${TAG}.csv"
RAW="results_layertiming_${TAG}.rawlog"
: > "$RAW"

command -v nvcc >/dev/null 2>&1 || die "nvcc not on PATH."
for f in "$INPUT_YUV" fsrcnn_gpu_main.cu fsrcnn_gpu_layertiming.cu; do
    [ -f "$f" ] || die "missing $f (run from plans/)"
done
for i in 1 2 3 4 5 6 7 8; do
    for p in weights_layer biasess_layer; do [ -f "${p}${i}.txt" ] || die "missing ${p}${i}.txt"; done
done

ARM_FLAGS=""
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    ARM_FLAGS="-D_BITS_MATH_VECTOR_H -D__Float32x4_t=void* -D__Float64x2_t=void* -D__SVFloat32_t=void* -D__SVFloat64_t=void* -D__SVBool_t=void*"
fi
build(){
    local src="$1" bin="$2"
    rm -f "$bin"
    for arch in native sm_121 sm_120 sm_90 sm_89 sm_87; do
        if nvcc -arch="$arch" $ARM_FLAGS -O3 -std=c++11 -Xcompiler -fopenmp \
                -Xcompiler -fno-tree-vectorize -o "$bin" "$src" -lm -lcudart 2>/dev/null; then
            info "built $bin (-arch=$arch)"; return 0
        fi
    done
    die "could not compile $src"
}

info "Platform: ${GPU_NAME:-unknown}  tag=$TAG  backdrop=$BACKDROP  reps=$REPS"
build fsrcnn_gpu_layertiming.cu ./fsrcnn_gpu_lt
build fsrcnn_gpu_main.cu        ./fsrcnn_gpu_ref
export OMP_NUM_THREADS="$BACKDROP"

echo "tag,rep,l1_ms,l2_ms,l3_ms,l4_ms,l5_ms,l6_ms,l7_ms,sum_l1_l7,cpu_l17_ms,residual_ms,gpu_l8_ms,wall_ms" > "$OUT_CSV"

field(){ echo "$2" | tr ' ' '\n' | grep "^$1=" | cut -d= -f2; }

declare -a L1 L2 L3 L4 L5 L6 L7 SUM CPU RES WALL
info "=== Per-layer sweep (instrumented binary) ==="
for r in $(seq 1 "$REPS"); do
    tmp="$(mktemp)"
    s=$(date +%s%N)
    ./fsrcnn_gpu_lt "$INPUT_YUV" "/tmp/_lt_${TAG}.yuv" $CFG >"$tmp" 2>&1 || { cat "$tmp"; die "run $r failed"; }
    e=$(date +%s%N); wall=$(( (e-s)/1000000 ))
    { echo "### rep=$r wall_ms=$wall"; cat "$tmp"; echo; } >> "$RAW"

    ls_line="$(grep -F '[LAYERSPLIT]' "$tmp" | tail -1)"
    pr_line="$(grep -F '[PROFILING]'  "$tmp" | tail -1)"
    rm -f "$tmp"
    [ -n "$ls_line" ] || die "no [LAYERSPLIT] line in rep $r -- see $RAW"

    l1=$(field l1_ms "$ls_line"); l2=$(field l2_ms "$ls_line"); l3=$(field l3_ms "$ls_line")
    l4=$(field l4_ms "$ls_line"); l5=$(field l5_ms "$ls_line"); l6=$(field l6_ms "$ls_line")
    l7=$(field l7_ms "$ls_line"); sm=$(field sum_l1_l7 "$ls_line")
    cp_=$(field cpu_l17_ms "$ls_line"); rs=$(field residual_ms "$ls_line")
    g8=$(field gpu_l8_ms "$pr_line")

    L1+=("$l1"); L2+=("$l2"); L3+=("$l3"); L4+=("$l4"); L5+=("$l5"); L6+=("$l6"); L7+=("$l7")
    SUM+=("$sm"); CPU+=("$cp_"); RES+=("$rs"); WALL+=("$wall")
    echo "$TAG,$r,$l1,$l2,$l3,$l4,$l5,$l6,$l7,$sm,$cp_,$rs,$g8,$wall" >> "$OUT_CSV"
    printf "  rep %d/%d  L1=%s L2=%s L3=%s L4=%s L5=%s L6=%s L7=%s | sum=%s cpu_l17=%s resid=%s\n" \
        "$r" "$REPS" "$l1" "$l2" "$l3" "$l4" "$l5" "$l6" "$l7" "$sm" "$cp_" "$rs"
done

# Control: production binary, same config, to show the timers cost nothing.
info "=== Control: production binary, same config ==="
declare -a RWALL
for r in $(seq 1 3); do
    s=$(date +%s%N)
    ./fsrcnn_gpu_ref "$INPUT_YUV" "/tmp/_lt_ref_${TAG}.yuv" $CFG >/dev/null 2>&1 || die "control run failed"
    e=$(date +%s%N); w=$(( (e-s)/1000000 )); RWALL+=("$w")
    echo "  control rep $r: ${w} ms"
done

# Bit-exactness: instrumentation must not change a single output byte.
DIFF=$(cmp -l "/tmp/_lt_${TAG}.yuv" "/tmp/_lt_ref_${TAG}.yuv" 2>/dev/null | wc -l | tr -d ' ')
rm -f "/tmp/_lt_${TAG}.yuv" "/tmp/_lt_ref_${TAG}.yuv"

meansd(){ awk '$0~/^[ \t]*-?[0-9]+(\.[0-9]+)?[ \t]*$/{n++;s+=$1;q+=$1*$1}
  END{if(n==0){printf "%16s","no data";exit} m=s/n; v=(n>1)?(q-n*m*m)/(n-1):0; if(v<0)v=0;
      printf "%9.2f +/- %-5.2f", m, sqrt(v)}'; }
mean(){ awk '{n++;s+=$1} END{if(n)printf "%.2f",s/n; else printf "0"}'; }

CPUMEAN=$(printf '%s\n' "${CPU[@]}" | mean)
pct(){ awk -v a="$1" -v b="$CPUMEAN" 'BEGIN{if(b>0)printf "%5.1f%%", 100*a/b; else printf "  n/a"}'; }

{
echo "=============================================================="
echo " Per-layer CPU breakdown (Layers 1-7) -- $TAG"
echo " gpu:       ${GPU_NAME:-unknown}"
echo " hostname:  $(hostname)"
echo " date:      $(date -Is)"
echo " backdrop:  OMP_NUM_THREADS=$BACKDROP"
echo " reps:      $REPS, grid $CFG, 150 frames"
echo "=============================================================="
echo
echo "All figures milliseconds, totalled across 150 frames, mean +/- SD."
echo
printf "  %-22s %-18s %s\n" "Layer" "Time (ms)" "share of L1-7"
printf "  %s\n" "------------------------------------------------------------"
i=1
for arr in L1 L2 L3 L4 L5 L6 L7; do
    eval "vals=(\"\${$arr[@]}\")"
    m=$(printf '%s\n' "${vals[@]}" | mean)
    printf "  %-22s %-18s %s\n" "Layer $i" "$(printf '%s\n' "${vals[@]}" | meansd)" "$(pct "$m")"
    i=$((i+1))
done
printf "  %s\n" "------------------------------------------------------------"
printf "  %-22s %-18s\n" "sum L1-L7"      "$(printf '%s\n' "${SUM[@]}"  | meansd)"
printf "  %-22s %-18s\n" "cpu_l17_ms"     "$(printf '%s\n' "${CPU[@]}"  | meansd)"
printf "  %-22s %-18s\n" "residual"       "$(printf '%s\n' "${RES[@]}"  | meansd)"
printf "  %-22s %-18s\n" "wall (instr.)"  "$(printf '%s\n' "${WALL[@]}" | meansd)"
printf "  %-22s %-18s\n" "wall (control)" "$(printf '%s\n' "${RWALL[@]}"| meansd)"
echo
echo "Checks:"
echo "  bit-exact vs production binary : $DIFF differing bytes (must be 0)"
echo "  residual = cpu_l17_ms - sum(L1..L7). A large residual means real work"
echo "  sits between the layer blocks and belongs to no single layer; a small"
echo "  one means the split accounts for the lump."
echo "  Compare the two wall lines: if they agree, the timers are free and the"
echo "  per-layer numbers can be quoted as absolute times, not just shares."
echo
echo "Send back:"
echo "  $(pwd)/$OUT_TXT"
echo "  $(pwd)/$OUT_CSV"
echo "  $(pwd)/$RAW"
echo "=============================================================="
} | tee "$OUT_TXT"

[ "$DIFF" = "0" ] || warn "OUTPUT DIFFERS FROM PRODUCTION BINARY ($DIFF bytes). Do not use these numbers; report this."
