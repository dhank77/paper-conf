// CUDA implementation of FSRCNN Layer 8 with spatial reduction
// Targets: ASUS Ascent GX10 (GB10, ARM64, CUDA 12.1+, sm_90)
// This file replaces Layer 8 in fsrcnn_parallel_spatial_reduction.c with GPU version
// Layers 1-7 remain on CPU

#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>
#include <string.h>

// Weight arrays (shared with CPU code, defined in main compilation unit)
extern double weights_layer8[4536];
extern double biases_layer8;
extern void pad_image(double *img, double *img_pad, int rows, int cols, int padsize);

// CUDA error checking
#define CHECK_CUDA(call) \
    do { \
        cudaError_t err = call; \
        if (err != cudaSuccess) { \
            fprintf(stderr, "CUDA error at %s:%d - %s\n", __FILE__, __LINE__, cudaGetErrorString(err)); \
            exit(EXIT_FAILURE); \
        } \
    } while(0)

// ============================================================================
// CUDA KERNEL: Deconvolution (Transposed Convolution)
// ============================================================================
// Each thread computes one output pixel for one channel
// Input: padded image of size rows_pad x cols_pad
// Kernel: 9x9
// Output: rows_out x cols_out (where rows_out = rows * scale, cols_out = cols * scale)

__global__ void deconv_kernel(
    const double* __restrict__ d_input_padded,
    double* __restrict__ d_output,
    const double* __restrict__ d_kernel,
    int rows_pad,
    int cols_pad,
    int rows_out,
    int cols_out,
    int stride,
    int border,
    int fsize
) {
    int out_y = blockIdx.y * blockDim.y + threadIdx.y;
    int out_x = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (out_y >= rows_out || out_x >= cols_out) return;
    
    // Calculate offset to map output pixel to position in intermediate buffer
    // This matches the original CPU deconv logic:
    // i_tmp = i + ((fsize + 1) / 2) + stride*border - 1
    int offset = (fsize + 1) / 2 + stride * border - 1;
    int tmp_y = out_y + offset;
    int tmp_x = out_x + offset;
    
    double sum = 0.0;
    
    // For each kernel element, find which input pixel contributes to this output position
    // Input pixel (i, j) places its kernel element (kr, kc) at position:
    //   (i*stride + kr, j*stride + kc) in the intermediate buffer
    // We need: i*stride + kr = tmp_y and j*stride + kc = tmp_x
    // => i = (tmp_y - kr) / stride, j = (tmp_x - kc) / stride
    for (int kr = 0; kr < fsize; kr++) {
        for (int kc = 0; kc < fsize; kc++) {
            int i_candidate = tmp_y - kr;
            int j_candidate = tmp_x - kc;
            
            // Check if this maps to a valid, stride-aligned input pixel
            if (i_candidate >= 0 && i_candidate < rows_pad &&
                j_candidate >= 0 && j_candidate < cols_pad &&
                i_candidate % stride == 0 && j_candidate % stride == 0) {
                
                int i = i_candidate / stride;
                int j = j_candidate / stride;
                int in_idx = i * cols_pad + j;
                int k_idx = kr * fsize + kc;
                sum += d_input_padded[in_idx] * d_kernel[k_idx];
            }
        }
    }
    
    d_output[out_y * cols_out + out_x] = sum;
}

// ============================================================================
// CUDA KERNEL: Spatial Reduction
// ============================================================================
// Reduces across channels: for each pixel p, sum all channels and add bias
// Grid: 1D, one thread per output pixel

__global__ void spatial_reduction_kernel(
    const double* __restrict__ d_all_tmp,
    double* __restrict__ d_img_hr,
    double bias,
    int num_channels,
    int hr_pixels
) {
    int p = blockIdx.x * blockDim.x + threadIdx.x;
    if (p < hr_pixels) {
        double sum = 0.0;
        for (int j = 0; j < num_channels; j++) {
            sum += d_all_tmp[j * hr_pixels + p];
        }
        d_img_hr[p] = sum + bias;
    }
}

// ============================================================================
// CUDA KERNEL: Pad Image (for GPU path)
// ============================================================================
__global__ void pad_image_kernel(
    const double* __restrict__ d_img,
    double* __restrict__ d_img_pad,
    int rows,
    int cols,
    int padsize
) {
    int cols_pad = cols + 2 * padsize;
    int rows_pad = rows + 2 * padsize;
    
    int i = blockIdx.y * blockDim.y + threadIdx.y;
    int j = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (i >= rows_pad || j >= cols_pad) return;
    
    int cnt_pad = i * cols_pad + j;
    
    if (i >= padsize && i < rows_pad - padsize &&
        j >= padsize && j < cols_pad - padsize) {
        // Central pixels
        int cnt = (i - padsize) * cols + (j - padsize);
        d_img_pad[cnt_pad] = d_img[cnt];
    } else if (i < padsize && j >= padsize && j < cols_pad - padsize) {
        // Top rows
        int src_i = 0;
        int cnt = src_i * cols + (j - padsize);
        d_img_pad[cnt_pad] = d_img[cnt];
    } else if (i >= rows_pad - padsize && j >= padsize && j < cols_pad - padsize) {
        // Bottom rows
        int src_i = rows - 1;
        int cnt = src_i * cols + (j - padsize);
        d_img_pad[cnt_pad] = d_img[cnt];
    } else if (i >= padsize && i < rows_pad - padsize && j < padsize) {
        // Left columns
        int src_j = 0;
        int cnt = (i - padsize) * cols + src_j;
        d_img_pad[cnt_pad] = d_img[cnt];
    } else if (i >= padsize && i < rows_pad - padsize && j >= cols_pad - padsize) {
        // Right columns
        int src_j = cols - 1;
        int cnt = (i - padsize) * cols + src_j;
        d_img_pad[cnt_pad] = d_img[cnt];
    } else {
        // Corner pixels
        int src_i, src_j;
        if (i < padsize) src_i = 0;
        else if (i >= rows_pad - padsize) src_i = rows - 1;
        else src_i = (i - padsize);
        
        if (j < padsize) src_j = 0;
        else if (j >= cols_pad - padsize) src_j = cols - 1;
        else src_j = (j - padsize);
        
        int cnt = src_i * cols + src_j;
        d_img_pad[cnt_pad] = d_img[cnt];
    }
}

// ============================================================================
// Host wrapper: FSRCNN Layer 8 on GPU
// ============================================================================
void FSRCNN_Layer8_GPU(double* img_hr, double* img_fltr_7, int rows, int cols, int scale) {
    int filtersize8 = 81; // 9x9
    int num_filters8 = 1;
    int num_channels8 = 56;
    int hr_pixels = (rows * scale) * (cols * scale);
    
    int border = 1;
    int fsize = 9;
    int rows_pad = rows + 2 * border;
    int cols_pad = cols + 2 * border;
    int rows_out = rows * scale;
    int cols_out = cols * scale;
    
    // Device pointers
    double *d_input_padded = NULL;
    double *d_all_tmp = NULL;
    double *d_kernel8 = NULL;
    double *d_img_hr = NULL;
    
    // Allocate device memory
    CHECK_CUDA(cudaMalloc(&d_input_padded, rows_pad * cols_pad * sizeof(double)));
    CHECK_CUDA(cudaMalloc(&d_all_tmp, num_channels8 * hr_pixels * sizeof(double)));
    CHECK_CUDA(cudaMalloc(&d_kernel8, filtersize8 * sizeof(double)));
    CHECK_CUDA(cudaMalloc(&d_img_hr, hr_pixels * sizeof(double)));
    
    // Copy kernel weights to device (biases are used in host reduction)
    CHECK_CUDA(cudaMemcpy(d_kernel8, weights_layer8, filtersize8 * sizeof(double), cudaMemcpyHostToDevice));
    
    // Process each channel: pad input, run deconv on GPU
    dim3 block_deconv(16, 16);
    dim3 grid_deconv((cols_out + block_deconv.x - 1) / block_deconv.x,
                     (rows_out + block_deconv.y - 1) / block_deconv.y);
    
    for (int j = 0; j < num_channels8; j++) {
        // Pad input on CPU (small buffer, negligible cost)
        double* h_input_padded = (double*)malloc(rows_pad * cols_pad * sizeof(double));
        pad_image(img_fltr_7 + j * rows * cols, h_input_padded, rows, cols, border);
        
        // Copy padded input to GPU
        CHECK_CUDA(cudaMemcpy(d_input_padded, h_input_padded, 
                              rows_pad * cols_pad * sizeof(double), 
                              cudaMemcpyHostToDevice));
        free(h_input_padded);
        
        // Launch deconv kernel for this channel
        // Output goes to d_all_tmp[j * hr_pixels]
        deconv_kernel<<<grid_deconv, block_deconv>>>(
            d_input_padded,
            d_all_tmp + j * hr_pixels,
            d_kernel8,
            rows_pad, cols_pad,
            rows_out, cols_out,
            scale, border, fsize
        );
        CHECK_CUDA(cudaGetLastError());
    }
    
    // Synchronize to ensure all deconv kernels complete before reduction
    CHECK_CUDA(cudaDeviceSynchronize());
    
    // Launch spatial reduction kernel
    int threads_reduce = 256;
    int blocks_reduce = (hr_pixels + threads_reduce - 1) / threads_reduce;
    spatial_reduction_kernel<<<blocks_reduce, threads_reduce>>>(
        d_all_tmp,
        d_img_hr,
        biases_layer8,
        num_channels8,
        hr_pixels
    );
    CHECK_CUDA(cudaGetLastError());
    CHECK_CUDA(cudaDeviceSynchronize());
    
    // Copy result back to host
    CHECK_CUDA(cudaMemcpy(img_hr, d_img_hr, hr_pixels * sizeof(double), cudaMemcpyDeviceToHost));
    
    // Cleanup device memory
    CHECK_CUDA(cudaFree(d_input_padded));
    CHECK_CUDA(cudaFree(d_all_tmp));
    CHECK_CUDA(cudaFree(d_kernel8));
    CHECK_CUDA(cudaFree(d_img_hr));
}

// ============================================================================
// Utility: Check CUDA device properties
// ============================================================================
void print_cuda_device_info() {
    int device_count = 0;
    CHECK_CUDA(cudaGetDeviceCount(&device_count));
    
    if (device_count == 0) {
        fprintf(stderr, "No CUDA device found!\n");
        exit(EXIT_FAILURE);
    }
    
    cudaDeviceProp prop;
    CHECK_CUDA(cudaGetDeviceProperties(&prop, 0));
    
    printf("CUDA Device: %s\n", prop.name);
    printf("  Compute Capability: %d.%d\n", prop.major, prop.minor);
    printf("  Total Global Memory: %.2f GB\n", prop.totalGlobalMem / (1024.0 * 1024.0 * 1024.0));
    printf("  Multiprocessors: %d\n", prop.multiProcessorCount);
    printf("  Max Threads per Block: %d\n", prop.maxThreadsPerBlock);
    printf("  Max Threads per MP: %d\n", prop.maxThreadsPerMultiProcessor);
    printf("  Warp Size: %d\n", prop.warpSize);
    printf("  Unified Addressing: %s\n", prop.unifiedAddressing ? "Yes" : "No");
}
