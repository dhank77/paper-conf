#!/bin/bash
# Quick verification script for FSRCNN GPU code
# Checks file existence and basic structure

set -e

echo "=== FSRCNN GPU Code Verification ==="
echo ""

# Check files exist
echo "Checking file existence..."
for f in fsrcnn_gpu.cu fsrcnn_gpu_main.cu compile_gpu.sh run_experiments.sh; do
    if [ -f "$f" ]; then
        echo "  [OK] $f"
    else
        echo "  [MISSING] $f"
    fi
done

echo ""
echo "Checking CUDA kernel structure in fsrcnn_gpu.cu..."
grep -c "__global__" fsrcnn_gpu.cu || echo "  0 __global__ kernels found"
grep -c "deconv_kernel" fsrcnn_gpu.cu || echo "  0 deconv_kernel references"
grep -c "spatial_reduction_kernel" fsrcnn_gpu.cu || echo "  0 spatial_reduction_kernel references"

echo ""
echo "Checking main program structure in fsrcnn_gpu_main.cu..."
grep -c "FSRCNN_Layer8_GPU" fsrcnn_gpu_main.cu || echo "  0 FSRCNN_Layer8_GPU calls"
grep -c "cudaMalloc" fsrcnn_gpu_main.cu || echo "  0 cudaMalloc calls"
grep -c "cudaMemcpy" fsrcnn_gpu_main.cu || echo "  0 cudaMemcpy calls"

echo ""
echo "Checking compilation flags in compile_gpu.sh..."
grep "sm_90" compile_gpu.sh || echo "  WARNING: sm_90 not found in compile script"

echo ""
echo "=== Verification complete ==="
echo ""
echo "To compile on GX10:"
echo "  chmod +x compile_gpu.sh"
echo "  ./compile_gpu.sh"
echo ""
echo "To run validation:"
echo "  bash run_experiments.sh --validate"
