#!/bin/bash
# Experiment runner for FSRCNN GPU validation (Bash version)
# Replaces run_experiments.py for environments where Python is not preferred
# Usage: ./run_experiments.sh [--validate|--benchmark|--phase1|--phase3]

set -e

# Configuration
GROUND_TRUTH="ground_truth.yuv"
INPUT_YUV="suzie.yuv"
CPU_BINARY="./fsrcnn_cpu"
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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Compute SHA-256 hash of a file
compute_hash() {
    shasum -a 256 "$1" | cut -d' ' -f1
}

# Count differing bytes between two files
count_diff_bytes() {
    cmp -l "$1" "$2" 2>/dev/null | wc -l
}

# Compute PSNR using ffmpeg
compute_psnr() {
    local file1="$1"
    local file2="$2"
    ffmpeg -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$file1" \
           -s "${OUTPUT_W}x${OUTPUT_H}" -pix_fmt yuv420p -i "$file2" \
           -lavfi psnr -f null - 2>&1 | grep "average" | tail -1 | sed 's/.*average://' | awk '{print $1}'
}

# Run a command and measure wall time
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

# Phase 1: Bit-exact validation
phase1_validate() {
    log_info "=== Phase 1: Bit-exact validation ==="
    
    if [ ! -f "$GROUND_TRUTH" ]; then
        log_error "$GROUND_TRUTH not found. Generate it first with CPU binary."
        log_info "Run: OMP_NUM_THREADS=1 $CPU_BINARY $INPUT_YUV $GROUND_TRUTH"
        exit 1
    fi
    
    local gt_hash=$(compute_hash "$GROUND_TRUTH")
    log_info "Ground truth hash: $gt_hash"
    
    # Run GPU version
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

# Phase 3: Performance scaling
phase3_benchmark() {
    log_info "=== Phase 3: Performance scaling ==="
    
    if [ ! -f "$GROUND_TRUTH" ]; then
        log_error "$GROUND_TRUTH not found. Generate it first."
        exit 1
    fi
    
    # Create CSV header
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
            local total=$(stat -f%z "$OUTPUT_CPU" 2>/dev/null || stat -c%s "$OUTPUT_CPU")
            local pct_diff=0
            if [ "$total" -gt 0 ]; then
                pct_diff=$((diff * 100 / total))
            fi
            local psnr=$(compute_psnr "$GROUND_TRUTH" "$OUTPUT_CPU")
            
            # Get peak RSS (Linux/Mac compatible)
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
        local total=$(stat -f%z "$OUTPUT_GPU" 2>/dev/null || stat -c%s "$OUTPUT_GPU")
        local pct_diff=0
        if [ "$total" -gt 0 ]; then
            pct_diff=$((diff * 100 / total))
        fi
        local psnr=$(compute_psnr "$GROUND_TRUTH" "$OUTPUT_GPU")
        
        # GPU memory usage (if nvidia-smi available)
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
            continue  # Skip header
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

# Phase 0: Generate ground truth
phase0_ground_truth() {
    log_info "=== Phase 0: Generate ground truth ==="
    
    if [ ! -f "$CPU_BINARY" ]; then
        log_error "CPU binary not found: $CPU_BINARY"
        exit 1
    fi
    
    if [ ! -f "$INPUT_YUV" ]; then
        log_error "Input YUV not found: $INPUT_YUV"
        exit 1
    fi
    
    log_info "Generating ground truth with CPU single-threaded..."
    OMP_NUM_THREADS=1 $CPU_BINARY "$INPUT_YUV" "$GROUND_TRUTH"
    
    if [ -f "$GROUND_TRUTH" ]; then
        local size=$(stat -f%z "$GROUND_TRUTH" 2>/dev/null || stat -c%s "$GROUND_TRUTH")
        local expected=$((WIDTH * HEIGHT * SCALE * SCALE * FRAMES * 3 / 2))
        log_info "Ground truth size: $size bytes (expected: $expected bytes)"
        
        if [ "$size" -eq "$expected" ]; then
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

# Print usage
usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --phase0        Generate ground truth (CPU single-threaded)"
    echo "  --validate      Phase 1: Bit-exact validation (GPU vs ground truth)"
    echo "  --benchmark     Phase 3: Performance scaling (CPU vs GPU)"
    echo "  --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --phase0                  # Generate ground truth first"
    echo "  $0 --validate                # Check GPU bit-exactness"
    echo "  $0 --benchmark               # Run performance comparison"
    echo ""
    echo "Prerequisites:"
    echo "  - suzie.yuv must exist in current directory"
    echo "  - fsrcnn_cpu binary must be compiled"
    echo "  - fsrcnn_gpu binary must be compiled (for GPU tests)"
    echo "  - ffmpeg must be installed (for PSNR calculation)"
}

# Main
main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    case "$1" in
        --phase0)
            phase0_ground_truth
            ;;
        --validate)
            phase1_validate
            ;;
        --benchmark)
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
