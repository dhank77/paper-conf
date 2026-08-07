#!/bin/bash
# Cross-platform bit-exactness check for GPU Spatial Reduction (Issue #5a, reviews/02.md).
# RTX 4090 desktop variant. Run the matching GB10 script
# (crossplatform_bitexact_check_gb10.sh) on the other machine.
#
# Run from the same directory as fsrcnn_gpu_main.cu / fsrcnn_gpu.cu /
# fsrcnn_parallel_spatial_reduction.c / suzie_qcif.yuv / weights_*.txt
# (i.e. plans/). After it finishes, push the two files it prints at the end
# back into this repo (results/crossplatform/) and let me know.

set -euo pipefail
cd "$(dirname "$0")"

TAG="rtx4090"
EXPECTED_GPU_PATTERN="4090"

echo "=== Cross-Platform Bit-Exactness Check ($TAG) ==="

# ---- 1. Sanity-check we're on the expected GPU (warn only, don't block) ----
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    echo "Detected GPU: ${GPU_NAME:-unknown}"
    if ! echo "$GPU_NAME" | grep -qE "$EXPECTED_GPU_PATTERN"; then
        echo "WARNING: expected an RTX 4090 GPU but detected '$GPU_NAME'."
        echo "         Continuing anyway since TAG is hardcoded to '$TAG'."
    fi
else
    echo "WARNING: nvidia-smi not found, skipping GPU identity check."
fi
echo ""

# ---- 2. Sanity-check required inputs ----
for f in suzie_qcif.yuv fsrcnn_gpu_main.cu fsrcnn_parallel_spatial_reduction.c; do
    if [ ! -f "$f" ]; then
        echo "ERROR: required file '$f' not found in $(pwd)"
        exit 1
    fi
done
for i in 1 2 3 4 5 6 7 8; do
    for prefix in weights_layer biasess_layer; do
        if [ ! -f "${prefix}${i}.txt" ]; then
            echo "ERROR: missing ${prefix}${i}.txt"
            exit 1
        fi
    done
done

# ---- 3. Build GPU binary from source, always fresh ----
# Never reuse a pre-existing ./fsrcnn_gpu: this repo's plans/ directory is
# shared/synced across machines with different architectures, and a stale
# binary built elsewhere will fail with "Exec format error" (or worse,
# silently be the wrong build). Rebuilding is a few seconds; a silent
# arch mismatch would invalidate the whole comparison.
echo "Building fsrcnn_gpu from source (forcing fresh build)..."
rm -f ./fsrcnn_gpu
if [ -x ./compile_gpu.sh ]; then
    ./compile_gpu.sh
else
    nvcc -arch=native -O3 -std=c++11 -Xcompiler -fopenmp \
        -o fsrcnn_gpu fsrcnn_gpu_main.cu -lm -lcudart
fi
if [ ! -x ./fsrcnn_gpu ]; then
    echo "ERROR: fsrcnn_gpu build failed."
    exit 1
fi
file ./fsrcnn_gpu 2>/dev/null || true

# ---- 4. Build CPU V1 (race-free) binary from source, always fresh ----
echo "Building CPU V1 reference binary from source (forcing fresh build)..."
rm -f ./fsrcnn_cpu_v1_ref
gcc -fopenmp -O3 -o fsrcnn_cpu_v1_ref fsrcnn_parallel_spatial_reduction.c -lm
if [ ! -x ./fsrcnn_cpu_v1_ref ]; then
    echo "ERROR: fsrcnn_cpu_v1_ref build failed."
    exit 1
fi

# ---- 5. Generate the in-platform deterministic reference, always fresh ----
REF_FILE="${TAG}_reference.yuv"
echo "Generating in-platform reference ($REF_FILE), forcing fresh regeneration..."
rm -f "$REF_FILE"
OMP_NUM_THREADS=1 ./fsrcnn_cpu_v1_ref suzie_qcif.yuv "$REF_FILE"

# ---- 6. Run GPU V2 with the winning grid config (32x8, reduce=256) ----
OUT_FILE="${TAG}_v2_output.yuv"
echo "Running GPU V2 (block=32x8, threads_reduce=256) -> $OUT_FILE ..."
./fsrcnn_gpu suzie_qcif.yuv "$OUT_FILE" 32 8 256

# ---- 7. In-platform sanity check: GPU V2 must still be bit-exact locally ----
DIFF_BYTES=$(cmp -l "$REF_FILE" "$OUT_FILE" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "In-platform cmp -l diff bytes (must be 0): $DIFF_BYTES"
if [ "$DIFF_BYTES" != "0" ]; then
    echo "ERROR: GPU V2 output is NOT bit-exact against the local reference on this"
    echo "       machine. Something regressed since the paper's results were captured;"
    echo "       do not send this file, investigate locally first."
    exit 1
fi
echo "OK: in-platform bit-exactness confirmed, as expected."

# ---- 8. Checksum for a quick eyeball compare before any file transfer ----
if command -v sha256sum &>/dev/null; then
    sha256sum "$OUT_FILE" | tee "${OUT_FILE}.sha256"
else
    shasum -a 256 "$OUT_FILE" | tee "${OUT_FILE}.sha256"
fi

echo ""
echo "=== Done ==="
echo "Send these two files back:"
echo "  plans/${OUT_FILE}"
echo "  plans/${OUT_FILE}.sha256"
echo ""
echo "(Once I have both platforms' files I'll diff them directly with cmp -l"
echo " and also compare the two .sha256 hashes as a first quick check.)"
