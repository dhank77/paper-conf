#!/bin/bash
# Compile FSRCNN GPU version for any NVIDIA GPU (Jetson Orin sm_87, RTX 4090 sm_89, GB10 sm_90)
# Usage: ./compile_gpu.sh

set -e

echo "=== FSRCNN GPU Compilation ==="
echo ""

# Check for nvcc
if ! command -v nvcc &> /dev/null; then
    echo "ERROR: nvcc not found. Please install CUDA toolkit."
    exit 1
fi

echo "nvcc version:"
nvcc --version | grep "release"
echo ""

ARM_FLAGS=""
if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
    ARM_FLAGS="-D_BITS_MATH_VECTOR_H -D__Float32x4_t=void* -D__Float64x2_t=void* -D__SVFloat32_t=void* -D__SVFloat64_t=void* -D__SVBool_t=void*"
fi

echo "Compiling fsrcnn_gpu_main.cu..."
if nvcc -arch=native $ARM_FLAGS -O3 -std=c++11 -Xcompiler -fopenmp -Xcompiler -fno-tree-vectorize -o fsrcnn_gpu fsrcnn_gpu_main.cu -lm -lcudart 2>/dev/null; then
    echo "Compiled successfully with -arch=native"
else
    echo "Falling back to multi-architecture compilation..."
    nvcc -gencode arch=compute_87,code=sm_87 -gencode arch=compute_89,code=sm_89 -gencode arch=compute_90,code=sm_90 $ARM_FLAGS -O3 -std=c++11 -Xcompiler -fopenmp -Xcompiler -fno-tree-vectorize -o fsrcnn_gpu fsrcnn_gpu_main.cu -lm -lcudart
fi

echo ""
echo "=== Compilation successful ==="
echo "Binary: fsrcnn_gpu"
echo ""
echo "Run with: ./fsrcnn_gpu <input.yuv> <output.yuv>"
