#!/bin/bash
###############################################################################
# collect_v0_frame26.sh -- settle the provenance of Fig. 1 panel (b).
#
# RUN ON THE RTX 4090 DESKTOP ONLY. Takes about 4 minutes.
#
# Why this exists:
#   Fig. 1 panel (b) is labelled "32 threads" and carries 23.0 dB / SSIM
#   0.845. The GB10 thread ladder in results/gpu-4.txt stops at 20, and those
#   exact numbers appear at results/76-rtx4090v3.txt:333 -- the RTX 4090's
#   32-thread row. Meanwhile the paper's Section IV-A used to say the figure
#   "shows the GB10 case". One of the two is wrong, and there is no record of
#   which machine produced v0_frame26.png.
#
#   Rather than guess, regenerate the panel on a host whose identity is
#   stamped into the output file. That replaces an unverifiable claim with a
#   measured one.
#
# One caveat you should expect and not be alarmed by: V0 is the racy variant.
# Its output is nondeterministic by construction -- that is the whole point of
# the figure -- so the PSNR will not come back as exactly 23.005696 dB. It
# should land in the same neighbourhood. The script runs it three times so the
# spread is visible, and the paper can then honestly say "representative run"
# with a range instead of implying a single reproducible value.
#
# Usage:  bash collect_v0_frame26.sh
# Output: results_v0frame_<tag>.txt  + v0_frames_<tag>/*.png -- send both back.
###############################################################################

set -uo pipefail
cd "$(dirname "$0")"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found."
command -v gcc    >/dev/null 2>&1 || die "gcc not found."
[ -f suzie_qcif.yuv ]                        || die "missing suzie_qcif.yuv (run from plans/)"
[ -f fsrcnn_parallel.c ]                     || die "missing fsrcnn_parallel.c (V0)"
[ -f fsrcnn_parallel_spatial_reduction.c ]   || die "missing fsrcnn_parallel_spatial_reduction.c (V1)"

GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
case "$GPU_NAME" in
    *GB10*) TAG="gb10" ;;
    *4090*) TAG="rtx4090" ;;
    *)      TAG="$(uname -m)" ;;
esac

THREADS="${V0_THREADS:-32}"
NRUNS=3
W=352; H=288; FRAME_PICK=26
OUT="results_v0frame_${TAG}.txt"
FRAMEDIR="v0_frames_${TAG}"
mkdir -p "$FRAMEDIR"

NPROC="$(nproc 2>/dev/null || echo '?')"
if [ "$NPROC" != "?" ] && [ "$THREADS" -gt "$NPROC" ] 2>/dev/null; then
    info "note: asking for $THREADS threads on a $NPROC-thread host (oversubscribed)."
    info "      That is fine -- oversubscription makes the race easier to see."
fi

# ---------------------------------------------------------------------------
# Build both variants fresh.
# ---------------------------------------------------------------------------
info "Building V0 (naive, racy) and V1 (spatial reduction, reference)..."
rm -f ./fsrcnn_v0_frame ./fsrcnn_v1_frame
gcc -fopenmp -O3 -o fsrcnn_v0_frame fsrcnn_parallel.c -lm || die "V0 build failed"
gcc -fopenmp -O3 -o fsrcnn_v1_frame fsrcnn_parallel_spatial_reduction.c -lm || die "V1 build failed"

# ---------------------------------------------------------------------------
# The deterministic reference: V1 at one thread. Same definition the
# bit-exactness scripts use, so the numbers stay comparable.
# ---------------------------------------------------------------------------
REF="v0check_reference.yuv"
info "Generating deterministic reference (V1, 1 thread)..."
rm -f "$REF"
OMP_NUM_THREADS=1 ./fsrcnn_v1_frame suzie_qcif.yuv "$REF" >/dev/null 2>&1 \
    || die "reference generation failed"

score_y() {
    # Y-plane PSNR and SSIM of $1 against the reference.
    local cand="$1"
    local p s
    p="$(ffmpeg -hide_banner -loglevel info \
          -s ${W}x${H} -pix_fmt yuv420p -i "$cand" \
          -s ${W}x${H} -pix_fmt yuv420p -i "$REF" \
          -lavfi "[0:v][1:v]psnr" -f null - 2>&1 | grep -i "PSNR" | tail -1)"
    s="$(ffmpeg -hide_banner -loglevel info \
          -s ${W}x${H} -pix_fmt yuv420p -i "$cand" \
          -s ${W}x${H} -pix_fmt yuv420p -i "$REF" \
          -lavfi "[0:v][1:v]ssim" -f null - 2>&1 | grep -i "SSIM" | tail -1)"
    echo "$p"
    echo "$s"
}

declare -a RESULTS
info "Running V0 at $THREADS threads, $NRUNS times..."
for r in $(seq 1 $NRUNS); do
    CAND="v0check_out_run${r}.yuv"
    rm -f "$CAND"
    OMP_NUM_THREADS=$THREADS ./fsrcnn_v0_frame suzie_qcif.yuv "$CAND" >/dev/null 2>&1 \
        || die "V0 run $r failed"

    DIFF="$(cmp -l "$REF" "$CAND" 2>/dev/null | wc -l | tr -d ' ')"
    TOTAL="$(stat -c%s "$CAND" 2>/dev/null || stat -f%z "$CAND")"
    SC="$(score_y "$CAND")"

    ffmpeg -hide_banner -loglevel error -y \
        -s ${W}x${H} -pix_fmt yuv420p -i "$CAND" \
        -vf "select=eq(n\,${FRAME_PICK})" -vsync 0 -frames:v 1 \
        "$FRAMEDIR/v0_${TAG}_${THREADS}t_run${r}_frame${FRAME_PICK}.png" 2>/dev/null

    RESULTS+=("run $r: diff_bytes=$DIFF / $TOTAL
$(echo "$SC" | sed 's/^/    /')")
    info "run $r done (diff_bytes=$DIFF)"
done

# The reference frame too, so the panel pair comes from one script.
ffmpeg -hide_banner -loglevel error -y \
    -s ${W}x${H} -pix_fmt yuv420p -i "$REF" \
    -vf "select=eq(n\,${FRAME_PICK})" -vsync 0 -frames:v 1 \
    "$FRAMEDIR/reference_frame${FRAME_PICK}.png" 2>/dev/null

rm -f v0check_out_run*.yuv "$REF"

{
echo "=============================================================="
echo " Fig. 1 panel (b) provenance -- V0 race at $THREADS threads"
echo " gpu:      ${GPU_NAME:-unknown}"
echo " hostname: $(hostname)"
echo " cpu:      $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ *//')"
echo " nproc:    $NPROC"
echo " date:     $(date -Is)"
echo "=============================================================="
echo
echo "Reference: V1 spatial reduction, OMP_NUM_THREADS=1, $W x $H."
echo "Candidate: V0 naive OpenMP, OMP_NUM_THREADS=$THREADS, $NRUNS runs."
echo
for r in "${RESULTS[@]}"; do echo "$r"; echo; done
echo "Expect the three runs to disagree with each other as well as with the"
echo "reference. That is the race, and it is the figure's whole argument."
echo "Take the y: PSNR/SSIM from whichever run you use for the panel and"
echo "quote it as a representative run, with the observed range alongside."
echo
echo "Files to send back:"
echo "  $(pwd)/$OUT"
echo "  $(pwd)/$FRAMEDIR/  ($((NRUNS + 1)) PNGs)"
echo "=============================================================="
} | tee "$OUT"
