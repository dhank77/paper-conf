# FSRCNN GPU Implementation for ASUS Ascent GX10

## Overview

This directory contains CUDA implementations of FSRCNN Layer 8 with spatial reduction, targeting the ASUS Ascent GX10 (GB10 Grace Blackwell Superchip).

### Files

| File | Description |
|------|-------------|
| `fsrcnn_gpu.cu` | CUDA kernels + host wrapper (`FSRCNN_Layer8_GPU`). Include this in your project. |
| `fsrcnn_gpu_main.cu` | Standalone complete program (CPU Layers 1-7 + GPU Layer 8). Compile with nvcc. |
| `compile_gpu.sh` | Compilation script for GX10 |
| `run_experiments.py` | Python script for running validation and benchmarks |
| `preparation.md` | Detailed experimental plan |

### Variants

- **V0 (CPU naive)**: `fsrcnn_parallel.c` — baseline with race condition
- **V1 (CPU spatial)**: `fsrcnn_parallel_spatial_reduction.c` — deterministic CPU baseline  
- **V2 (GPU spatial)**: `fsrcnn_gpu_main.cu` — GPU-accelerated Layer 8 (this work)

## Compilation (GX10)

```bash
# Make script executable
chmod +x compile_gpu.sh

# Compile
./compile_gpu.sh
```

Or compile manually:
```bash
nvcc -arch=sm_90 -O3 -std=c++11 -o fsrcnn_gpu fsrcnn_gpu_main.cu -lm -lcudart
```

### Notes for GX10
- **Architecture**: ARM64 (aarch64) — ensure CUDA toolkit for ARM64 is installed
- **Compute Capability**: sm_90 (Blackwell GB10)
- **Unified Memory**: 128GB LPDDR5x shared between CPU and GPU
- **OS**: NVIDIA DGX OS (Ubuntu-based)

## Usage

```bash
./fsrcnn_gpu <input.yuv> <output.yuv>
```

Input/output format: YUV 4:2:0, 150 frames, 176×144 (CIF) → 352×288 (2x upscale)

## Experiment Workflow

### Input Data
- `suzie.yuv` must exist in the current directory (CIF 176×144, 150 frames, YUV 4:2:0)
- This file is used for all validation and benchmarking

### Phase 0: Prerequisites
```bash
# 1. Compile CPU binary (if not already done)
gcc -fopenmp -O3 -o fsrcnn_cpu fsrcnn_parallel_spatial_reduction.c -lm

# 2. Compile GPU binary
chmod +x compile_gpu.sh
./compile_gpu.sh

# 3. Generate ground truth (CPU, single-threaded)
./run_experiments.sh --phase0
```

This creates `ground_truth.yuv` and verifies its size (22,809,600 bytes).

### Phase 1: Bit-exact Validation
```bash
./run_experiments.sh --validate
```

This runs the GPU version and compares output against ground truth. Must show `diff_bytes == 0`.

### Phase 3: Performance Scaling
```bash
./run_experiments.sh --benchmark
```

This runs CPU versions at 1, 2, 4, 8, 16 threads and GPU version, saving results to `raw_results.csv`.

### CSV Output Format
```
run_id,variant,threads,device,wall_ms,diff_bytes,total_bytes,pct_diff,psnr_db,peak_rss_kb
```

### Notes
- Bash runner is used instead of Python to avoid dependency on Python interpreter
- PSNR calculation requires `ffmpeg` installed
- Peak RSS measurement uses `/usr/bin/time -v` on Linux/Mac
- GPU memory usage uses `nvidia-smi` if available

## CUDA Kernel Details

### Deconvolution Kernel
- Grid: 2D (cols_out × rows_out)
- Block: 16×16 threads
- Each thread computes one output pixel by summing contributions from input pixels
- Kernel launched per channel (56 channels total)

### Spatial Reduction Kernel
- Grid: 1D (hr_pixels)
- Block: 256 threads
- Each thread sums across 56 channels and adds bias
- Single kernel launch for entire image

## Memory Layout

```
d_all_tmp: [channel0_pixels | channel1_pixels | ... | channel55_pixels]
           |--- hr_pixels ---|  (contiguous per channel)

d_img_hr: [pixel0, pixel1, ..., pixel(hr_pixels-1)]
```

This layout enables coalesced memory access in the reduction kernel.

## Expected Performance

On GX10 (1 PFLOPS FP4, 128GB unified memory):
- Layer 8 deconv is memory-bound (~56 × 576 × 352 × 9×9 operations)
- Spatial reduction is compute-light (56 accumulations per pixel)
- Expected speedup vs CPU: 5-20× depending on thread count

## Troubleshooting

### "CUDA error: no kernel image is available for execution"
Check compute capability: `deviceQuery` from CUDA samples. Update `-arch=sm_XX` flag.

### "CUDA error: out of memory"
Reduce batch size or check that `hr_pixels` calculation is correct.

### Output differs from CPU version
1. Verify `double_2_uint8` is identical between CPU and GPU versions
2. Check floating point precision (CPU uses double, GPU also uses double)
3. Ensure weights are loaded identically
