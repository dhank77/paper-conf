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
#   - suzie.yuv, weights_layer*.txt, biasess_layer*.txt in current directory
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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

INPUT_YUV="suzie.yuv"
GROUND_TRUTH="ground_truth.yuv"
CPU_SOURCE="fsrcnn_parallel_spatial_reduction.c"
CPU_BINARY="./fsrcnn_cpu"
GPU_SOURCE="fsrcnn_gpu_main.cu"
GPU_BINARY="./fsrcnn_gpu"
OUTPUT_CPU="out_cpu.yuv"
OUTPUT_GPU="out_gpu.yuv"
CSV_FILE="raw_results.csv"

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
build_cpu() {
    log_info "Building CPU binary: $CPU_BINARY from $CPU_SOURCE"
    
    if [ ! -f "$CPU_SOURCE" ]; then
        log_error "CPU source not found: $CPU_SOURCE"
        exit 1
    fi
    
    gcc -fopenmp -O3 -o "$CPU_BINARY" "$CPU_SOURCE" -lm
    log_info "CPU binary built successfully: $CPU_BINARY"
}

build_gpu() {
    log_info "Building GPU binary: $GPU_BINARY from $GPU_SOURCE"
    
    if [ ! -f "$GPU_SOURCE" ]; then
        log_error "GPU source not found: $GPU_SOURCE"
        exit 1
    fi
    
    if ! command -v nvcc &> /dev/null; then
        log_error "nvcc not found. Install CUDA toolkit first."
        exit 1
    fi
    
    nvcc -arch=sm_90 -O3 -std=c++11 -o "$GPU_BINARY" "$GPU_SOURCE" -lm -lcudart
    log_info "GPU binary built successfully: $GPU_BINARY"
}

# Auto-build binaries before any phase
build_all() {
    log_info "=== Building binaries ==="
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
    if command -v ffmpeg &> /dev/null; then
        ffmpeg -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$file1" \
               -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$file2" \
               -lavfi psnr -f null - 2>&1 | grep "average" | tail -1 | sed 's/.*average://' | awk '{print $1}'
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
    
    log_info "Running $label..."
    local start=$(date +%s%N)
    eval "$cmd"
    local status=$?
    local end=$(date +%s%N)
    
    local wall_ms=$(( (end - start) / 1000000 ))
    echo "    Wall time: ${wall_ms} ms"
    
    if [ $status -ne 0 ]; then
        log_error "Command failed: $cmd"
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

# ===================== PHASE 3: PERFORMANCE SCALING =====================
phase3_benchmark() {
    log_info "=== Phase 3: Performance scaling ==="
    
    if [ ! -f "$GROUND_TRUTH" ]; then
        log_error "$GROUND_TRUTH not found. Run --phase0 first."
        exit 1
    fi
    
    if [ ! -f "$CPU_BINARY" ]; then
        log_info "CPU binary not found, building..."
        build_cpu
    fi
    
    if [ ! -f "$GPU_BINARY" ]; then
        log_info "GPU binary not found, building..."
        build_gpu
    fi
    
    echo "run_id,variant,threads,device,wall_ms,diff_bytes,total_bytes,pct_diff,psnr_db,peak_rss_kb" > "$CSV_FILE"
    
    local run_id=1
    local baseline_wall=""
    
    # CPU configurations
    for threads in 1 2 4 8 16; do
        log_info "--- CPU with $threads threads ---"
        
        export OMP_NUM_THREADS=$threads
        
        local cpu_wall=$(run_and_time "CPU-${threads}t" "$CPU_BINARY $INPUT_YUV $OUTPUT_CPU")
        
        if [ -f "$OUTPUT_CPU" ]; then
            local diff=$(count_diff_bytes "$GROUND_TRUTH" "$OUTPUT_CPU")
            local total=$(get_file_size "$OUTPUT_CPU")
            local pct_diff=0
            if [ "$total" -gt 0 ]; then
                pct_diff=$((diff * 100 / total))
            fi
            local psnr=$(compute_psnr "$GROUND_TRUTH" "$OUTPUT_CPU")
            
            local peak_rss="N/A"
            if command -v /usr/bin/time &> /dev/null; then
                local time_output=$(/usr/bin/time -v "$CPU_BINARY" "$INPUT_YUV" "$OUTPUT_CPU" 2>&1 | grep "Maximum resident" | awk '{print $6}')
                if [ -n "$time_output" ]; then
                    peak_rss="$time_output"
                fi
            fi
            
            echo "$run_id,CPU,$threads,CPU,$cpu_wall,$diff,$total,$pct_diff,$psnr,$peak_rss" >> "$CSV_FILE"
            
            if [ "$threads" -eq 1 ]; then
                baseline_wall="$cpu_wall"
            fi
            
            run_id=$((run_id + 1))
        fi
    done
    
    # GPU configuration
    log_info "--- GPU ---"
    local gpu_wall=$(run_and_time "GPU" "$GPU_BINARY $INPUT_YUV $OUTPUT_GPU")
    
    if [ -f "$OUTPUT_GPU" ]; then
        local diff=$(count_diff_bytes "$GROUND_TRUTH" "$OUTPUT_GPU")
        local total=$(get_file_size "$OUTPUT_GPU")
        local pct_diff=0
        if [ "$total" -gt 0 ]; then
            pct_diff=$((diff * 100 / total))
        fi
        local psnr=$(compute_psnr "$GROUND_TRUTH" "$OUTPUT_GPU")
        
        local peak_rss="N/A"
        if command -v nvidia-smi &> /dev/null; then
            local mem_usage=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | head -1)
            if [ -n "$mem_usage" ]; then
                peak_rss=$(echo "$mem_usage" | cut -d',' -f1 | tr -d ' ')
            fi
        fi
        
        echo "$run_id,GPU,1,GPU,$gpu_wall,$diff,$total,$pct_diff,$psnr,$peak_rss" >> "$CSV_FILE"
    fi
    
    # Print summary
    log_info "=== Summary ==="
    printf "%-10s %-10s %-15s %-10s\n" "Variant" "Threads" "Wall (ms)" "Speedup"
    printf "%-10s %-10s %-15s %-10s\n" "-------" "-------" "----------" "-------"
    
    while IFS=, read -r run_id variant threads device wall_ms diff_bytes total_bytes pct_diff psnr_db peak_rss_kb; do
        if [ "$run_id" = "run_id" ]; then
            continue
        fi
        if [ -z "$baseline_wall" ] || [ "$baseline_wall" -eq 0 ]; then
            speedup="—"
        else
            speedup=$(awk "BEGIN {printf \"%.2fx\", $baseline_wall / $wall_ms}")
        fi
        printf "%-10s %-10s %-15s %-10s\n" "$variant" "$threads" "$wall_ms" "$speedup"
    done < "$CSV_FILE"
    
    log_info "Results saved to $CSV_FILE"
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
    echo "  - suzie.yuv"
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
