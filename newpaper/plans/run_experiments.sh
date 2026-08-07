#!/bin/bash
###############################################################################
# run_experiments.sh - FSRCNN GPU Experiment Runner
#
# Automatically builds CPU/GPU binaries before each phase, similar to
# comparison_new.sh style. No Python required.
#
# Usage:
#   ./run_experiments.sh --phase0    # Generate ground truth
#   ./run_experiments.sh --validate  # Bit-exact validation (GPU vs ground truth)
#   ./run_experiments.sh --benchmark # Performance scaling (CPU vs GPU)
#   ./run_experiments.sh --build     # Build binaries only, no execution
#
# Prerequisites:
#   - suzie_qcif.yuv, weights_layer*.txt, biasess_layer*.txt in current directory
#   - gcc with OpenMP support
#   - CUDA toolkit with nvcc (for GPU build)
#   - ffmpeg (for PSNR calculation)
###############################################################################

set -e

# ===================== BUILD-ONLY MODE =====================
BUILD_ONLY=0
if [ "${1:-}" = "--build" ] || [ "${1:-}" = "build-only" ]; then
    BUILD_ONLY=1
fi

# ===================== KONFIGURASI =====================
# Auto-set Tegra CUDA library paths for Jetson Orin non-root execution
if [ -d "/usr/lib/aarch64-linux-gnu/tegra" ]; then
    export LD_LIBRARY_PATH="/usr/lib/aarch64-linux-gnu/tegra:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
fi
if [ -d "/usr/local/cuda/bin" ]; then
    export PATH="/usr/local/cuda/bin:${PATH}"
fi

INPUT_YUV="suzie_qcif.yuv"
GROUND_TRUTH="ground_truth.yuv"
CPU_V0_SOURCE="fsrcnn_parallel.c"
CPU_V0_BINARY="./fsrcnn_cpu_v0"
CPU_SOURCE="fsrcnn_parallel_spatial_reduction.c"
CPU_BINARY="./fsrcnn_cpu"
GPU_SOURCE="fsrcnn_gpu.cu fsrcnn_gpu_main.cu"
GPU_BINARY="./fsrcnn_gpu"
OUTPUT_V0="out_v0.yuv"
OUTPUT_CPU="out_cpu.yuv"
OUTPUT_GPU="out_gpu.yuv"
CSV_FILE="raw_results.csv"

# Thread sweep and GPU backdrop are platform-dependent (core topology differs
# across GX10 / RTX4090 desktop / Jetson). Override via env var, e.g.:
#   THREAD_LADDER="1 2 4 8 16 24 32" GPU_BACKDROP_THREADS=4 bash run_experiments.sh --benchmark
THREAD_LADDER="${THREAD_LADDER:-1 2 4 8 10 16 20}"

# Auto-detect GPU backdrop threads: Intel x86_64 P-cores (4t/8t) vs ARM64 GX10 (20t)
if [ -z "$GPU_BACKDROP_THREADS" ]; then
    if [ "$(uname -m)" = "x86_64" ]; then
        GPU_BACKDROP_THREADS=4
    else
        GPU_BACKDROP_THREADS=20
    fi
fi

# Video parameters (CIF, scale=2)
WIDTH=176
HEIGHT=144
SCALE=2
FRAMES=150
OUTPUT_W=$((WIDTH * SCALE))
OUTPUT_H=$((HEIGHT * SCALE))
EXPECTED_OUTPUT_SIZE=$((OUTPUT_W * OUTPUT_H * 3 / 2 * FRAMES))

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ===================== KOMPILASI =====================
build_v0() {
    log_info "Building CPU V0 (Naive OpenMP) binary: $CPU_V0_BINARY from $CPU_V0_SOURCE"
    if [ ! -f "$CPU_V0_SOURCE" ]; then
        log_warn "CPU V0 source not found: $CPU_V0_SOURCE, skipping V0 build."
        return 0
    fi
    gcc -fopenmp -O3 -o "$CPU_V0_BINARY" "$CPU_V0_SOURCE" -lm
    log_info "CPU V0 binary built successfully: $CPU_V0_BINARY"
}

build_cpu() {
    log_info "Building CPU V1 (Spatial Reduction) binary: $CPU_BINARY from $CPU_SOURCE"
    
    if [ ! -f "$CPU_SOURCE" ]; then
        log_error "CPU source not found: $CPU_SOURCE"
        exit 1
    fi
    
    gcc -fopenmp -O3 -o "$CPU_BINARY" "$CPU_SOURCE" -lm
    log_info "CPU binary built successfully: $CPU_BINARY"
}

build_gpu() {
    log_info "Building GPU binary: $GPU_BINARY"
    
    if [ ! -f "fsrcnn_gpu_main.cu" ]; then
        log_error "GPU source not found: fsrcnn_gpu_main.cu"
        exit 1
    fi
    
    if ! command -v nvcc &> /dev/null; then
        log_error "nvcc not found. Install CUDA toolkit first."
        exit 1
    fi
    
    local arm_flags=""
    if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
        arm_flags="-D_BITS_MATH_VECTOR_H -D__Float32x4_t=void* -D__Float64x2_t=void* -D__SVFloat32_t=void* -D__SVFloat64_t=void* -D__SVBool_t=void*"
    fi
    
    local compiled=0
    
    # Step 1: Try -arch=native
    if nvcc -arch=native $arm_flags -O3 -std=c++11 -Xcompiler -fopenmp -Xcompiler -fno-tree-vectorize -o "$GPU_BINARY" fsrcnn_gpu_main.cu -lm -lcudart 2>/dev/null; then
        log_info "GPU binary ready (-arch=native): $GPU_BINARY"
        compiled=1
    fi
    
    # Step 2: Try compute cap from nvidia-smi
    if [ "$compiled" -eq 0 ] && command -v nvidia-smi &>/dev/null; then
        local cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d '.' || true)
        if [ -n "$cap" ]; then
            if nvcc -arch="sm_$cap" $arm_flags -O3 -std=c++11 -Xcompiler -fopenmp -Xcompiler -fno-tree-vectorize -o "$GPU_BINARY" fsrcnn_gpu_main.cu -lm -lcudart 2>/dev/null; then
                log_info "GPU binary ready (-arch=sm_$cap): $GPU_BINARY"
                compiled=1
            fi
        fi
    fi
    
    # Step 3: Loop through common architectures
    if [ "$compiled" -eq 0 ]; then
        for arch in sm_87 sm_89 sm_90 sm_80 sm_75 sm_70 sm_61 sm_53; do
            if nvcc -arch="$arch" $arm_flags -O3 -std=c++11 -Xcompiler -fopenmp -Xcompiler -fno-tree-vectorize -o "$GPU_BINARY" fsrcnn_gpu_main.cu -lm -lcudart 2>/dev/null; then
                log_info "GPU binary ready (-arch=$arch): $GPU_BINARY"
                compiled=1
                break
            fi
        done
    fi
    
    if [ "$compiled" -eq 0 ]; then
        log_error "Failed to compile CUDA binary with any architecture option."
        exit 1
    fi
}

# Auto-build binaries before any phase
build_all() {
    log_info "=== Building binaries ==="
    build_v0
    build_cpu
    build_gpu
    log_info "=== Build complete ==="
    echo ""
}

# ===================== UTILITAS =====================
compute_hash() {
    shasum -a 256 "$1" | cut -d' ' -f1
}

count_diff_bytes() {
    cmp -l "$1" "$2" 2>/dev/null | wc -l
}

compute_psnr() {
    local file1="$1"
    local file2="$2"
    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        echo "N/A"
        return
    fi
    local diff=$(count_diff_bytes "$file1" "$file2")
    if [ "$diff" -eq 0 ]; then
        echo "inf (bit-exact)"
        return
    fi
    if command -v ffmpeg &> /dev/null; then
        local psnr_val=$(ffmpeg -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$file1" \
               -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$file2" \
               -lavfi psnr -f null - 2>&1 | grep -i "average" | tail -1 | sed -E 's/.*average: *([0-9\.]+).*/\1/')
        if [ -n "$psnr_val" ]; then
            echo "$psnr_val"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

compute_ssim() {
    local file1="$1"
    local file2="$2"
    if [ ! -f "$file1" ] || [ ! -f "$file2" ]; then
        echo "N/A"
        return
    fi
    local diff=$(count_diff_bytes "$file1" "$file2")
    if [ "$diff" -eq 0 ]; then
        echo "1.000000"
        return
    fi
    if command -v ffmpeg &> /dev/null; then
        local ssim_val=$(ffmpeg -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$file1" \
               -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$file2" \
               -lavfi ssim -f null - 2>&1 | grep -i "All:" | tail -1 | sed -E 's/.*All: *([0-9\.]+).*/\1/')
        if [ -n "$ssim_val" ]; then
            echo "$ssim_val"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

get_file_size() {
    stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo "0"
}

run_and_time() {
    local label="$1"
    shift
    local cmd="$@"
    
    log_info "Running $label..." >&2
    local start=$(date +%s%N)
    eval "$cmd" >&2
    local status=$?
    local end=$(date +%s%N)
    
    local wall_ms=$(( (end - start) / 1000000 ))
    echo "    Wall time: ${wall_ms} ms" >&2
    
    if [ $status -ne 0 ]; then
        log_error "Command failed: $cmd" >&2
        return 1
    fi
    
    echo "$wall_ms"
}

# ===================== PHASE 0: GROUND TRUTH =====================
phase0_ground_truth() {
    log_info "=== Phase 0: Generate ground truth ==="
    
    if [ ! -f "$INPUT_YUV" ]; then
        log_error "Input YUV not found: $INPUT_YUV"
        exit 1
    fi
    
    if [ ! -f "$CPU_BINARY" ]; then
        log_info "CPU binary not found, building..."
        build_cpu
    fi
    
    log_info "Generating ground truth with CPU single-threaded..."
    OMP_NUM_THREADS=1 "$CPU_BINARY" "$INPUT_YUV" "$GROUND_TRUTH"
    
    if [ -f "$GROUND_TRUTH" ]; then
        local size=$(get_file_size "$GROUND_TRUTH")
        log_info "Ground truth size: $size bytes (expected: $EXPECTED_OUTPUT_SIZE bytes)"
        
        if [ "$size" -eq "$EXPECTED_OUTPUT_SIZE" ]; then
            local gt_hash=$(compute_hash "$GROUND_TRUTH")
            log_info "Ground truth hash: $gt_hash"
            log_info "PASS: Ground truth generated successfully"
        else
            log_error "FAIL: Ground truth size mismatch"
            exit 1
        fi
    else
        log_error "Failed to create ground truth"
        exit 1
    fi
}

# ===================== PHASE 1: BIT-EXACT VALIDATION =====================
phase1_validate() {
    log_info "=== Phase 1: Bit-exact validation ==="
    
    if [ ! -f "$GROUND_TRUTH" ]; then
        log_error "$GROUND_TRUTH not found. Run --phase0 first."
        exit 1
    fi
    
    if [ ! -f "$GPU_BINARY" ]; then
        log_info "GPU binary not found, building..."
        build_gpu
    fi
    
    local gt_hash=$(compute_hash "$GROUND_TRUTH")
    log_info "Ground truth hash: $gt_hash"
    
    log_info "Running GPU version..."
    local gpu_wall=$(run_and_time "GPU version" "$GPU_BINARY $INPUT_YUV $OUTPUT_GPU")
    
    if [ ! -f "$OUTPUT_GPU" ]; then
        log_error "GPU output not created"
        exit 1
    fi
    
    local gpu_hash=$(compute_hash "$OUTPUT_GPU")
    log_info "GPU output hash:   $gpu_hash"
    
    local diff=$(count_diff_bytes "$GROUND_TRUTH" "$OUTPUT_GPU")
    log_info "Diff bytes: $diff"
    
    if [ "$diff" -eq 0 ]; then
        log_info "PASS: GPU output is bit-exact with ground truth"
    else
        log_error "FAIL: GPU output differs from ground truth ($diff bytes)"
        exit 1
    fi
}

# ===================== PHASE 3: PERFORMANCE SCALING & GRID SEARCH =====================
phase3_benchmark() {
    log_info "=== Phase 3: Performance scaling (V0 Naive CPU vs V1 Spatial CPU vs V2 GPU) ==="
    
    if [ ! -f "$GROUND_TRUTH" ]; then
        log_error "$GROUND_TRUTH not found. Run --phase0 first."
        exit 1
    fi
    
    build_v0
    build_cpu
    build_gpu
    
    echo "run_id,variant,threads,device,block_x,block_y,threads_reduce,wall_ms_mean,wall_ms_sd,cpu_l17_ms,h2d_ms,gpu_l8_ms,d2h_ms,diff_bytes,total_bytes,pct_diff,psnr_db,ssim,peak_rss_kb,vram_kb" > "$CSV_FILE"
    
    local run_id=1
    local baseline_mean=""
    local TOTAL_REPS=7
    
    # Helper to calculate Mean and Standard Deviation
    calc_stats() {
        awk 'BEGIN {sum=0; sq=0; n=0} {val=$1; sum+=val; sq+=val*val; n++} END {if (n>0) {m=sum/n; sd=(n>1 && (sq-(sum*sum)/n)>0)?sqrt((sq-(sum*sum)/n)/(n-1)):0; printf "%.2f,%.2f", m, sd} else {printf "0.00,0.00"}}'
    }
    
    # --- V0 CPU Naive OpenMP configurations ---
    if [ -f "$CPU_V0_BINARY" ]; then
        for threads in $THREAD_LADDER; do
            log_info "--- CPU V0 (Naive) with $threads threads ($TOTAL_REPS runs) ---"
            export OMP_NUM_THREADS=$threads
            local run_times=()
            for r in $(seq 1 $TOTAL_REPS); do
                local wall=$(run_and_time "CPU-V0-${threads}t [run $r/$TOTAL_REPS]" "$CPU_V0_BINARY $INPUT_YUV $OUTPUT_V0")
                if [ "$r" -gt 1 ]; then
                    run_times+=("$wall")
                fi
            done
            local stats=$(printf "%s\n" "${run_times[@]}" | calc_stats)
            local mean_ms=$(echo "$stats" | cut -d',' -f1)
            local sd_ms=$(echo "$stats" | cut -d',' -f2)
            
            if [ "$threads" -eq 1 ] && [ -z "$baseline_mean" ]; then
                baseline_mean="$mean_ms"
            fi
            
            local diff=$(count_diff_bytes "$GROUND_TRUTH" "$OUTPUT_V0")
            local total=$(get_file_size "$OUTPUT_V0")
            local pct_diff=0
            if [ "$total" -gt 0 ]; then pct_diff=$((diff * 100 / total)); fi
            local psnr=$(compute_psnr "$GROUND_TRUTH" "$OUTPUT_V0")
            local ssim=$(compute_ssim "$GROUND_TRUTH" "$OUTPUT_V0")
            
            echo "$run_id,CPU-V0,$threads,CPU,N/A,N/A,N/A,$mean_ms,$sd_ms,N/A,N/A,N/A,N/A,$diff,$total,$pct_diff,$psnr,$ssim,N/A,0" >> "$CSV_FILE"
            run_id=$((run_id + 1))
        done
    fi
    
    # --- V1 CPU Spatial Reduction configurations ---
    for threads in $THREAD_LADDER; do
        log_info "--- CPU V1 (Spatial) with $threads threads ($TOTAL_REPS runs) ---"
        export OMP_NUM_THREADS=$threads
        local run_times=()
        for r in $(seq 1 $TOTAL_REPS); do
            local wall=$(run_and_time "CPU-V1-${threads}t [run $r/$TOTAL_REPS]" "$CPU_BINARY $INPUT_YUV $OUTPUT_CPU")
            if [ "$r" -gt 1 ]; then
                run_times+=("$wall")
            fi
        done
        local stats=$(printf "%s\n" "${run_times[@]}" | calc_stats)
        local mean_ms=$(echo "$stats" | cut -d',' -f1)
        local sd_ms=$(echo "$stats" | cut -d',' -f2)
        
        if [ "$threads" -eq 1 ] && [ -z "$baseline_mean" ]; then
            baseline_mean="$mean_ms"
        fi
        
        local diff=$(count_diff_bytes "$GROUND_TRUTH" "$OUTPUT_CPU")
        local total=$(get_file_size "$OUTPUT_CPU")
        local pct_diff=0
        if [ "$total" -gt 0 ]; then pct_diff=$((diff * 100 / total)); fi
        local psnr=$(compute_psnr "$GROUND_TRUTH" "$OUTPUT_CPU")
        local ssim=$(compute_ssim "$GROUND_TRUTH" "$OUTPUT_CPU")
        
        echo "$run_id,CPU-V1,$threads,CPU,N/A,N/A,N/A,$mean_ms,$sd_ms,N/A,N/A,N/A,N/A,$diff,$total,$pct_diff,$psnr,$ssim,N/A,0" >> "$CSV_FILE"
        run_id=$((run_id + 1))
    done
    
    # --- V2 GPU Grid Search configurations (block_x block_y threads_reduce) ---
    export OMP_NUM_THREADS=$GPU_BACKDROP_THREADS
    local gpu_configs=(
        "16 16 256"
        "8 8 256"
        "32 8 256"
        "16 16 128"
        "16 16 512"
    )
    
    for cfg in "${gpu_configs[@]}"; do
        read bx by tr <<< "$cfg"
        log_info "--- GPU V2 (Block: ${bx}x${by}, Reduce: ${tr}) ---"
        
        local run_times=()
        local last_prof=""
        
        for r in $(seq 1 $TOTAL_REPS); do
            local prof_log=$(mktemp)
            local wall=""
            if wall=$(run_and_time "GPU-V2 (${bx}x${by}_${tr}) [run $r/$TOTAL_REPS]" "$GPU_BINARY $INPUT_YUV $OUTPUT_GPU $bx $by $tr 2>$prof_log"); then
                local prof_line=$(grep "\[PROFILING\]" "$prof_log" | tail -1 || true)
                rm -f "$prof_log"
                if [ "$r" -gt 1 ]; then
                    run_times+=("$wall")
                    last_prof="$prof_line"
                fi
            else
                log_error "GPU-V2 execution error output:"
                cat "$prof_log" >&2
                rm -f "$prof_log"
            fi
        done
        
        local stats=$(printf "%s\n" "${run_times[@]}" | calc_stats)
        local mean_ms=$(echo "$stats" | cut -d',' -f1)
        local sd_ms=$(echo "$stats" | cut -d',' -f2)
        
        # Parse breakdown from last profiling line
        local cpu_l17="N/A" h2d="N/A" gpu_l8="N/A" d2h="N/A" vram_kb="0"
        if [ -n "$last_prof" ]; then
            cpu_l17=$(echo "$last_prof" | sed -n 's/.*cpu_l17_ms=\([^ ]*\).*/\1/p')
            h2d=$(echo "$last_prof" | sed -n 's/.*h2d_ms=\([^ ]*\).*/\1/p')
            gpu_l8=$(echo "$last_prof" | sed -n 's/.*gpu_l8_ms=\([^ ]*\).*/\1/p')
            d2h=$(echo "$last_prof" | sed -n 's/.*d2h_ms=\([^ ]*\).*/\1/p')
            vram_kb=$(echo "$last_prof" | sed -n 's/.*vram_kb=\([^ ]*\).*/\1/p')
        fi
        
        local diff=$(count_diff_bytes "$GROUND_TRUTH" "$OUTPUT_GPU")
        local total=$(get_file_size "$OUTPUT_GPU")
        local pct_diff=0
        if [ "$total" -gt 0 ]; then pct_diff=$((diff * 100 / total)); fi
        local psnr=$(compute_psnr "$GROUND_TRUTH" "$OUTPUT_GPU")
        local ssim=$(compute_ssim "$GROUND_TRUTH" "$OUTPUT_GPU")
        
        echo "$run_id,GPU-V2,1,GPU,$bx,$by,$tr,$mean_ms,$sd_ms,$cpu_l17,$h2d,$gpu_l8,$d2h,$diff,$total,$pct_diff,$psnr,$ssim,N/A,$vram_kb" >> "$CSV_FILE"
        run_id=$((run_id + 1))
    done
    
    # Print summary
    log_info "=== Summary (Wall Time Mean ± SD over 6 measured runs, PSNR & SSIM) ==="
    printf "%-9s %-12s %-16s %-9s %-16s %-10s %-12s\n" "Variant" "Config/Th" "Wall (ms)" "Speedup" "PSNR (dB)" "SSIM" "GPU L8 (ms)"
    printf "%-9s %-12s %-16s %-9s %-16s %-10s %-12s\n" "---------" "---------" "----------------" "-------" "----------------" "----------" "-----------"
    
    while IFS=, read -r r_id variant threads device bx by tr mean_ms sd_ms cpu_l17 h2d gpu_l8 d2h diff_b total_b pct_d psnr_db ssim_val rss_kb vram_k; do
        if [ "$r_id" = "run_id" ]; then
            continue
        fi
        
        local cfg_label="$threads t"
        local gpu_l8_display="N/A"
        if [ "$variant" = "GPU-V2" ]; then
            cfg_label="${GPU_BACKDROP_THREADS}t_${bx}x${by}_${tr}"
            if [ -n "$gpu_l8" ] && [ "$gpu_l8" != "N/A" ]; then
                gpu_l8_display="${gpu_l8} ms"
            fi
        fi
        
        local wall_str="${mean_ms} ± ${sd_ms}"
        local speedup="—"
        if [ -n "$baseline_mean" ] && [ "$(echo "$mean_ms > 0" | awk '{print ($1)?1:0}')" -eq 1 ]; then
            speedup=$(awk "BEGIN {printf \"%.2fx\", $baseline_mean / $mean_ms}")
        fi
        
        printf "%-9s %-12s %-16s %-9s %-16s %-10s %-12s\n" "$variant" "$cfg_label" "$wall_str" "$speedup" "$psnr_db" "$ssim_val" "$gpu_l8_display"
    done < "$CSV_FILE"
    
    log_info "Detailed results saved to $CSV_FILE"
}

# ===================== USAGE =====================
usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --phase0       Generate ground truth (auto-builds CPU binary)"
    echo "  --validate     Bit-exact validation (auto-builds CPU+GPU binaries)"
    echo "  --benchmark    Performance scaling (auto-builds CPU+GPU binaries)"
    echo "  --build        Build binaries only, no execution"
    echo "  --help         Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --phase0                  # Generate ground truth"
    echo "  $0 --validate                # Check GPU bit-exactness"
    echo "  $0 --benchmark               # Run performance comparison"
    echo ""
    echo "Input files required in current directory:"
    echo "  - suzie_qcif.yuv"
    echo "  - weights_layer1.txt .. weights_layer8.txt"
    echo "  - biasess_layer1.txt .. biasess_layer8.txt"
}

# ===================== MAIN =====================
main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    case "$1" in
        --build)
            build_all
            ;;
        --phase0)
            build_cpu
            if [ "$BUILD_ONLY" -eq 1 ]; then
                log_info "Build-only mode, skipping execution."
                exit 0
            fi
            phase0_ground_truth
            ;;
        --validate)
            build_cpu
            build_gpu
            if [ "$BUILD_ONLY" -eq 1 ]; then
                log_info "Build-only mode, skipping execution."
                exit 0
            fi
            phase1_validate
            ;;
        --benchmark)
            build_cpu
            build_gpu
            if [ "$BUILD_ONLY" -eq 1 ]; then
                log_info "Build-only mode, skipping execution."
                exit 0
            fi
            phase3_benchmark
            ;;
        --help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
