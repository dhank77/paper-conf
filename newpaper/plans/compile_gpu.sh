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

compiled=0

# Step 1: Try -arch=native
if nvcc -arch=native $ARM_FLAGS -O3 -std=c++11 -Xcompiler -fopenmp -Xcompiler -fno-tree-vectorize -o fsrcnn_gpu fsrcnn_gpu_main.cu -lm -lcudart 2>/dev/null; then
    echo "Successfully compiled with -arch=native"
    compiled=1
fi

# Step 2: Try compute cap from nvidia-smi
if [ "$compiled" -eq 0 ] && command -v nvidia-smi &>/dev/null; then
    cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.' || true)
    if [ -n "$cap" ]; then
        if nvcc -arch="sm_$cap" $ARM_FLAGS -O3 -std=c++11 -Xcompiler -fopenmp -Xcompiler -fno-tree-vectorize -o fsrcnn_gpu fsrcnn_gpu_main.cu -lm -lcudart 2>/dev/null; then
            echo "Successfully compiled with -arch=sm_$cap"
            compiled=1
        fi
    fi
fi

# Step 3: Loop through common architectures
if [ "$compiled" -eq 0 ]; then
    for arch in sm_87 sm_89 sm_90 sm_80 sm_75 sm_70 sm_61 sm_53; do
        if nvcc -arch="$arch" $ARM_FLAGS -O3 -std=c++11 -Xcompiler -fopenmp -Xcompiler -fno-tree-vectorize -o fsrcnn_gpu fsrcnn_gpu_main.cu -lm -lcudart 2>/dev/null; then
            echo "Successfully compiled with -arch=$arch"
            compiled=1
            break
        fi
    done
fi

if [ "$compiled" -eq 0 ]; then
    echo "ERROR: Failed to compile CUDA binary with any architecture option."
    exit 1
fi

echo ""
echo "=== Compilation successful ==="
echo "Binary: fsrcnn_gpu"
echo ""
echo "Run with: ./fsrcnn_gpu <input.yuv> <output.yuv>"
