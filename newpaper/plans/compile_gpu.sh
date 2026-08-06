#!/bin/bash
# Compile FSRCNN GPU version for ASUS GX10 (ARM64, GB10, sm_90)
# Usage: ./compile_gpu.sh

set -e

echo "=== FSRCNN GPU Compilation for ASUS GX10 ==="
echo ""

# Check for nvcc
if ! command -v nvcc &> /dev/null; then
    echo "ERROR: nvcc not found. Please install CUDA toolkit."
    echo "  On GX10: sudo apt install nvidia-cuda-toolkit"
    exit 1
fi

echo "nvcc version:"
nvcc --version | grep "release"
echo ""

# Compile both .cu files together
echo "Compiling fsrcnn_gpu_main.cu..."
nvcc \
    -arch=sm_90 \
    -O3 \
    -std=c++11 \
    -D_BITS_MATH_VECTOR_H \
    -D__Float32x4_t=void* \
    -D__Float64x2_t=void* \
    -D__SVFloat32_t=void* \
    -D__SVFloat64_t=void* \
    -D__SVBool_t=void* \
    -Xcompiler -fno-tree-vectorize \
    -o fsrcnn_gpu \
    fsrcnn_gpu_main.cu \
    -lm \
    -lcudart

echo ""
echo "=== Compilation successful ==="
echo "Binary: fsrcnn_gpu"
echo ""
echo "Run with: ./fsrcnn_gpu <input.yuv> <output.yuv>"
