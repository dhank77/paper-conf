// Microbenchmark for spatial_reduction_kernel ONLY -- isolates its true
// per-launch execution time from CUDA-event / instrumentation overhead.
//
// WHY THIS EXISTS
// ---------------------------------------------------------------------------
// Table III reports spatial_reduction's total time across 150 frames
// (150 launches) as 2.62 ms on the RTX 4090 -- 17.5 us/launch. Dividing the
// 43.3 MiB buffer it reads by that time gives ~2,597 GB/s, 2.5x the RTX
// 4090's own 1,008 GB/s GDDR6X ceiling (Section VII, open question).
// collect_l2_readwrite_profile.sh already ruled out L2 caching as the cause
// with ground-truth DRAM byte counts (~100% of the buffer really is read
// from DRAM, not served from cache) -- so the 2.5x gap most likely comes
// from the TIMING method, not the GPU: at ~17.5 us, a single CUDA Event
// pair's own recording latency and resolution can be a sizeable fraction of
// what's being measured.
//
// This program removes that risk by bracketing thousands of back-to-back
// launches with ONE cudaEvent pair, so per-launch timer overhead is
// amortized down to a negligible fraction of the total. It reuses the exact
// same kernel body, grid, and buffer sizes as fsrcnn_gpu_main.cu -- only the
// data in d_all_tmp is synthetic (deterministic pseudo-random fill), since
// timing doesn't depend on the values, only on the access pattern and size.
//
// Usage:
//   ./spatial_reduction_microbench [launches] [reps] [threads_reduce]
//   ./spatial_reduction_microbench 10000 6 256
//
// Compile:
//   nvcc -arch=native -O3 -o spatial_reduction_microbench \
//        spatial_reduction_microbench.cu -lcudart

#include <cuda_runtime_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define CHECK_CUDA(call)                                                     \
  do {                                                                       \
    cudaError_t err = call;                                                  \
    if (err != cudaSuccess) {                                                \
      fprintf(stderr, "CUDA error at %s:%d - %s\n", __FILE__, __LINE__,      \
              cudaGetErrorString(err));                                      \
      exit(EXIT_FAILURE);                                                    \
    }                                                                        \
  } while (0)

// Identical kernel body to fsrcnn_gpu_main.cu's spatial_reduction_kernel.
__global__ void spatial_reduction_kernel(const double *__restrict__ d_all_tmp,
                                         double *__restrict__ d_img_hr,
                                         double bias, int num_channels,
                                         int hr_pixels) {
  int p = blockIdx.x * blockDim.x + threadIdx.x;
  if (p < hr_pixels) {
    double sum = 0.0;
    for (int j = 0; j < num_channels; j++) {
      sum += d_all_tmp[j * hr_pixels + p];
    }
    d_img_hr[p] = sum + bias;
  }
}

__global__ void fill_kernel(double *buf, size_t n, unsigned int seed) {
  size_t i = blockIdx.x * (size_t)blockDim.x + threadIdx.x;
  if (i < n) {
    // Deterministic pseudo-random fill; values are irrelevant to timing,
    // only the fact that every element is touched (real allocation, no
    // lazy zero-pages) matters.
    unsigned int x = (unsigned int)i ^ seed;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    buf[i] = (double)(x % 1000) / 1000.0;
  }
}

int main(int argc, char *argv[]) {
  int launches = (argc >= 2) ? atoi(argv[1]) : 10000;
  int reps = (argc >= 3) ? atoi(argv[2]) : 6;
  int threads_reduce = (argc >= 4) ? atoi(argv[3]) : 256;

  const int num_channels = 56;
  const int rows_out = 288, cols_out = 352;
  const int hr_pixels = rows_out * cols_out; // 101376
  const size_t buf_elems = (size_t)num_channels * hr_pixels;
  const size_t buf_bytes = buf_elems * sizeof(double);
  const double bias = 0.01;

  int device = 0;
  CHECK_CUDA(cudaSetDevice(device));
  cudaDeviceProp prop;
  CHECK_CUDA(cudaGetDeviceProperties(&prop, device));
  printf("[GPU] %s (Compute %d.%d)\n", prop.name, prop.major, prop.minor);
  printf("[CFG] launches/rep=%d reps=%d threads_reduce=%d buffer=%.2f MiB "
         "(num_channels=%d hr_pixels=%d)\n",
         launches, reps, threads_reduce, buf_bytes / (1024.0 * 1024.0),
         num_channels, hr_pixels);

  double *d_all_tmp = NULL, *d_img_hr = NULL;
  CHECK_CUDA(cudaMalloc(&d_all_tmp, buf_bytes));
  CHECK_CUDA(cudaMalloc(&d_img_hr, hr_pixels * sizeof(double)));

  {
    int block = 256;
    int grid = (int)((buf_elems + block - 1) / block);
    fill_kernel<<<grid, block>>>(d_all_tmp, buf_elems, 12345u);
    CHECK_CUDA(cudaGetLastError());
    CHECK_CUDA(cudaDeviceSynchronize());
  }

  int blocks_reduce = (hr_pixels + threads_reduce - 1) / threads_reduce;

  // Warm-up: not timed. Lets clocks ramp and the kernel's instructions land
  // in the instruction cache before the timed region starts.
  for (int i = 0; i < 50; i++) {
    spatial_reduction_kernel<<<blocks_reduce, threads_reduce>>>(
        d_all_tmp, d_img_hr, bias, num_channels, hr_pixels);
  }
  CHECK_CUDA(cudaGetLastError());
  CHECK_CUDA(cudaDeviceSynchronize());

  double *rep_ms = (double *)malloc(reps * sizeof(double));
  double *rep_gbps = (double *)malloc(reps * sizeof(double));
  double bytes_read_per_launch = (double)buf_bytes; // one full read of d_all_tmp per launch

  for (int r = 0; r < reps; r++) {
    cudaEvent_t start, stop;
    CHECK_CUDA(cudaEventCreate(&start));
    CHECK_CUDA(cudaEventCreate(&stop));

    CHECK_CUDA(cudaEventRecord(start));
    for (int i = 0; i < launches; i++) {
      spatial_reduction_kernel<<<blocks_reduce, threads_reduce>>>(
          d_all_tmp, d_img_hr, bias, num_channels, hr_pixels);
    }
    CHECK_CUDA(cudaEventRecord(stop));
    CHECK_CUDA(cudaEventSynchronize(stop));
    CHECK_CUDA(cudaGetLastError());

    float ms = 0.0f;
    CHECK_CUDA(cudaEventElapsedTime(&ms, start, stop));
    CHECK_CUDA(cudaEventDestroy(start));
    CHECK_CUDA(cudaEventDestroy(stop));

    double per_launch_us = (double)ms * 1000.0 / launches;
    double total_bytes = bytes_read_per_launch * launches;
    double gbps = (total_bytes / 1.0e9) / ((double)ms / 1000.0);

    rep_ms[r] = ms;
    rep_gbps[r] = gbps;
    fprintf(stderr,
            "[REP %d/%d] total=%.3f ms  per_launch=%.4f us  "
            "effective_bandwidth=%.1f GB/s\n",
            r + 1, reps, ms, per_launch_us, gbps);
  }

  double mean_ms = 0, mean_gbps = 0;
  for (int r = 0; r < reps; r++) { mean_ms += rep_ms[r]; mean_gbps += rep_gbps[r]; }
  mean_ms /= reps; mean_gbps /= reps;

  double sd_ms = 0, sd_gbps = 0;
  for (int r = 0; r < reps; r++) {
    sd_ms += (rep_ms[r] - mean_ms) * (rep_ms[r] - mean_ms);
    sd_gbps += (rep_gbps[r] - mean_gbps) * (rep_gbps[r] - mean_gbps);
  }
  sd_ms = (reps > 1) ? sqrt(sd_ms / (reps - 1)) : 0.0;
  sd_gbps = (reps > 1) ? sqrt(sd_gbps / (reps - 1)) : 0.0;

  double mean_per_launch_us = mean_ms * 1000.0 / launches;

  printf("\n[RESULT] mean_total_ms=%.4f +/- %.4f  (n=%d launches/rep, %d reps)\n",
         mean_ms, sd_ms, launches, reps);
  printf("[RESULT] mean_per_launch_us=%.4f\n", mean_per_launch_us);
  printf("[RESULT] mean_effective_bandwidth_GBps=%.1f +/- %.1f\n", mean_gbps, sd_gbps);

  CHECK_CUDA(cudaFree(d_all_tmp));
  CHECK_CUDA(cudaFree(d_img_hr));
  free(rep_ms);
  free(rep_gbps);
  return 0;
}
