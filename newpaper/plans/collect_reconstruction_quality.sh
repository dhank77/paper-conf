#!/bin/bash
###############################################################################
# collect_reconstruction_quality.sh -- self-contained super-resolution quality.
#
# RUN ON THE RTX 4090 DESKTOP ONLY. (It would give identical numbers on the
# GB10 -- V2 is bit-exact across both -- so there is no reason to run it
# twice. The RTX box is the one with ffmpeg already in the path.)
# Takes about 3-4 minutes.
#
# Why this exists (reviews/03.md, section C):
#   Every quality number in the paper today is a *self-consistency* check:
#   V2 output vs. V1 output, which is why it reads "inf (bit-exact)". That
#   proves the GPU port is faithful. It says nothing about whether the
#   network reconstructs anything, because there is no ground-truth
#   high-resolution frame anywhere in the pipeline -- suzie_qcif.yuv is the
#   input, not a downsampled version of something larger.
#
#   The fix is to manufacture the missing ground truth. Bicubic-downsample
#   Suzie 176x144 -> 88x72, feed that to FSRCNN at scale 2 to get back to
#   176x144, and score the result against the original 176x144. Bicubic
#   upscaling of the same 88x72 is the comparator: it is what you get for
#   free, so FSRCNN has to beat it or the network is not earning its runtime.
#
#   Only the Y plane goes through FSRCNN -- the chroma path in the source is
#   plain 2x pixel replication -- so the script reports Y-plane PSNR/SSIM
#   separately. Quoting the all-component average would dilute the result
#   with a chroma path that has nothing to do with the network.
#
# Requires: ffmpeg, nvcc. Uses fsrcnn_gpu_instrumented.cu, whose only
# behavioural difference from the production source is that input geometry is
# env-settable (the production binary hardcodes 176x144).
#
# Usage:  bash collect_reconstruction_quality.sh
# Output: results_quality_<tag>.txt  -- send this back.
#         quality_frames/*.png       -- send these too if the figure needs them.
###############################################################################

set -uo pipefail
cd "$(dirname "$0")"

if [ -d "/usr/local/cuda/bin" ]; then
    export PATH="/usr/local/cuda/bin:${PATH}"
fi

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found -- it is required for PSNR/SSIM."
command -v nvcc   >/dev/null 2>&1 || die "nvcc not on PATH."
[ -f suzie_qcif.yuv ] || die "missing suzie_qcif.yuv (run from plans/)"
[ -f fsrcnn_gpu_instrumented.cu ] || die "missing fsrcnn_gpu_instrumented.cu"

GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
case "$GPU_NAME" in
    *GB10*) TAG="gb10" ;;
    *4090*) TAG="rtx4090" ;;
    *)      TAG="$(uname -m)" ;;
esac
OUT="results_quality_${TAG}.txt"

# Geometry. HR is the original Suzie; LR is what we manufacture from it.
HR_W=176; HR_H=144
LR_W=88;  LR_H=72
FRAMES=150
FRAME_PICK=26          # the frame Fig. 1 already uses

LR_YUV="quality_lr_${LR_W}x${LR_H}.yuv"
SR_YUV="quality_sr_fsrcnn.yuv"
BIC_YUV="quality_sr_bicubic.yuv"
FRAMEDIR="quality_frames"
mkdir -p "$FRAMEDIR"

# ---------------------------------------------------------------------------
# Build (fresh -- plans/ is synced across two different architectures)
# ---------------------------------------------------------------------------
ARM_FLAGS=""
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    ARM_FLAGS="-D_BITS_MATH_VECTOR_H -D__Float32x4_t=void* -D__Float64x2_t=void* -D__SVFloat32_t=void* -D__SVFloat64_t=void* -D__SVBool_t=void*"
fi
info "Building fsrcnn_gpu_instr..."
rm -f ./fsrcnn_gpu_instr
built=0
for arch in native sm_121 sm_120 sm_90 sm_89 sm_87; do
    if nvcc -arch="$arch" $ARM_FLAGS -O3 -std=c++11 -Xcompiler -fopenmp \
            -Xcompiler -fno-tree-vectorize -o fsrcnn_gpu_instr \
            fsrcnn_gpu_instrumented.cu -lm -lcudart 2>/dev/null; then
        info "built with -arch=$arch"; built=1; break
    fi
done
[ "$built" = "1" ] || die "compilation failed"

# ---------------------------------------------------------------------------
# 1. Manufacture the low-resolution input by bicubic downsampling.
# ---------------------------------------------------------------------------
info "Downsampling ${HR_W}x${HR_H} -> ${LR_W}x${LR_H} (bicubic)..."
rm -f "$LR_YUV"
ffmpeg -hide_banner -loglevel error -y \
    -s ${HR_W}x${HR_H} -pix_fmt yuv420p -i suzie_qcif.yuv \
    -vf "scale=${LR_W}:${LR_H}:flags=bicubic" -pix_fmt yuv420p \
    -f rawvideo "$LR_YUV" || die "downsample failed"

exp_lr=$(( LR_W * LR_H * 3 / 2 * FRAMES ))
got_lr=$(stat -c%s "$LR_YUV" 2>/dev/null || stat -f%z "$LR_YUV")
[ "$got_lr" = "$exp_lr" ] || die "LR file is $got_lr bytes, expected $exp_lr"
info "LR sequence OK ($got_lr bytes)"

# ---------------------------------------------------------------------------
# 2. FSRCNN 2x reconstruction: 88x72 -> 176x144
# ---------------------------------------------------------------------------
info "Running FSRCNN (scale 2) on the LR sequence..."
rm -f "$SR_YUV"
FSRCNN_COLS=$LR_W FSRCNN_ROWS=$LR_H FSRCNN_FRAMES=$FRAMES \
    ./fsrcnn_gpu_instr "$LR_YUV" "$SR_YUV" 32 8 256 > /dev/null 2>&1 \
    || die "FSRCNN run failed"

exp_sr=$(( HR_W * HR_H * 3 / 2 * FRAMES ))
got_sr=$(stat -c%s "$SR_YUV" 2>/dev/null || stat -f%z "$SR_YUV")
[ "$got_sr" = "$exp_sr" ] || die "SR file is $got_sr bytes, expected $exp_sr"
info "SR sequence OK ($got_sr bytes)"

# ---------------------------------------------------------------------------
# 3. Bicubic comparator: the same LR input, upscaled the cheap way.
# ---------------------------------------------------------------------------
info "Bicubic upscale ${LR_W}x${LR_H} -> ${HR_W}x${HR_H} (comparator)..."
rm -f "$BIC_YUV"
ffmpeg -hide_banner -loglevel error -y \
    -s ${LR_W}x${LR_H} -pix_fmt yuv420p -i "$LR_YUV" \
    -vf "scale=${HR_W}:${HR_H}:flags=bicubic" -pix_fmt yuv420p \
    -f rawvideo "$BIC_YUV" || die "bicubic upscale failed"

# ---------------------------------------------------------------------------
# 4. Score both against the original. Y plane is what matters.
# ---------------------------------------------------------------------------
score() {
    local cand="$1" label="$2"
    local raw
    raw="$(ffmpeg -hide_banner -loglevel info \
            -s ${HR_W}x${HR_H} -pix_fmt yuv420p -i "$cand" \
            -s ${HR_W}x${HR_H} -pix_fmt yuv420p -i suzie_qcif.yuv \
            -lavfi "[0:v][1:v]psnr" -f null - 2>&1 | grep -i "PSNR" | tail -1)"
    local sraw
    sraw="$(ffmpeg -hide_banner -loglevel info \
            -s ${HR_W}x${HR_H} -pix_fmt yuv420p -i "$cand" \
            -s ${HR_W}x${HR_H} -pix_fmt yuv420p -i suzie_qcif.yuv \
            -lavfi "[0:v][1:v]ssim" -f null - 2>&1 | grep -i "SSIM" | tail -1)"
    echo "  $label"
    echo "    psnr: $raw"
    echo "    ssim: $sraw"
}

info "Scoring FSRCNN and bicubic against the original ${HR_W}x${HR_H}..."
SCORE_FSRCNN="$(score "$SR_YUV" "FSRCNN 2x (V2, GPU spatial reduction)")"
SCORE_BICUBIC="$(score "$BIC_YUV" "Bicubic 2x (comparator)")"

# ---------------------------------------------------------------------------
# 5. Frame extraction, in case the paper wants a visual panel.
# ---------------------------------------------------------------------------
info "Extracting frame $FRAME_PICK from each sequence..."
extract() {
    ffmpeg -hide_banner -loglevel error -y \
        -s "$2"x"$3" -pix_fmt yuv420p -i "$1" \
        -vf "select=eq(n\,${FRAME_PICK})" -vsync 0 -frames:v 1 "$4" 2>/dev/null
}
extract suzie_qcif.yuv $HR_W $HR_H "$FRAMEDIR/original_frame${FRAME_PICK}.png"
extract "$LR_YUV"      $LR_W $LR_H "$FRAMEDIR/lr_frame${FRAME_PICK}.png"
extract "$SR_YUV"      $HR_W $HR_H "$FRAMEDIR/fsrcnn_frame${FRAME_PICK}.png"
extract "$BIC_YUV"     $HR_W $HR_H "$FRAMEDIR/bicubic_frame${FRAME_PICK}.png"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
{
echo "=============================================================="
echo " FSRCNN reconstruction quality (self-contained SR experiment)"
echo " gpu:      ${GPU_NAME:-unknown}"
echo " hostname: $(hostname)"
echo " date:     $(date -Is)"
echo "=============================================================="
echo
echo "Protocol"
echo "  ground truth : suzie_qcif.yuv, ${HR_W}x${HR_H}, $FRAMES frames"
echo "  LR input     : bicubic downsample to ${LR_W}x${LR_H}"
echo "  candidate 1  : FSRCNN scale 2, ${LR_W}x${LR_H} -> ${HR_W}x${HR_H}"
echo "  candidate 2  : bicubic upscale, ${LR_W}x${LR_H} -> ${HR_W}x${HR_H}"
echo "  scored with  : ffmpeg psnr / ssim, both against the ground truth"
echo
echo "Read the y: component, not the 'average'. Only the Y plane passes"
echo "through the network; U and V are 2x pixel replication in the source,"
echo "so including them measures the replication, not FSRCNN."
echo
echo "$SCORE_FSRCNN"
echo
echo "$SCORE_BICUBIC"
echo
echo "Interpretation: FSRCNN's Y-plane PSNR must exceed bicubic's for the"
echo "network to be worth its runtime. If it does not, say so in the paper"
echo "rather than dropping the experiment -- the speedup claims stand on"
echo "their own either way, and a negative result here is honest and"
echo "publishable. Do not tune the protocol until the number improves."
echo
echo "ffmpeg: $(ffmpeg -version 2>/dev/null | head -1)"
echo
echo "Files to send back:"
echo "  $(pwd)/$OUT"
echo "  $(pwd)/$FRAMEDIR/  (4 PNGs, frame $FRAME_PICK)"
echo "=============================================================="
} | tee "$OUT"
