// CUDA kernels for FSRCNN Layer 8 spatial reduction
// Pure device code - no system headers that cause ARM64 math-vector.h conflicts
// Targets: ASUS Ascent GX10 (GB10, ARM64, CUDA 12.1+, sm_90)

// Workaround for glibc bits/math-vector.h on ARM64 NVCC compilation
#if defined(__aarch64__)
  #ifndef __Float32x4_t
    typedef void* __Float32x4_t;
  #endif
  #ifndef __Float64x2_t
    typedef void* __Float64x2_t;
  #endif
  #ifndef __SVFloat32_t
    typedef void* __SVFloat32_t;
  #endif
  #ifndef __SVFloat64_t
    typedef void* __SVFloat64_t;
  #endif
  #ifndef __SVBool_t
    typedef void* __SVBool_t;
  #endif
#endif

#ifndef __FSRCNN_GPU_KERNELS_CU__
#define __FSRCNN_GPU_KERNELS_CU__

// CUDA kernel: Deconvolution (Transposed Convolution)
// Each thread computes one output pixel for one channel
__global__ void deconv_kernel(
    const double* __restrict__ d_input_padded,
    double* __restrict__ d_output,
    const double* __restrict__ d_kernel,
    int rows_pad, int cols_pad,
    int rows_out, int cols_out,
    int stride, int border, int fsize
) {
    int out_y = blockIdx.y * blockDim.y + threadIdx.y;
    int out_x = blockIdx.x * blockDim.x + threadIdx.x;

    if (out_y >= rows_out || out_x >= cols_out) return;

    int offset = (fsize + 1) / 2 + stride * border - 1;
    int tmp_y = out_y + offset;
    int tmp_x = out_x + offset;

    double sum = 0.0;

    for (int kr = 0; kr < fsize; kr++) {
        for (int kc = 0; kc < fsize; kc++) {
            int i_candidate = tmp_y - kr;
            int j_candidate = tmp_x - kc;

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

// CUDA kernel: Spatial Reduction across channels
// One thread per output pixel
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
        for (int ch = 0; ch < num_channels; ch++) {
            sum += d_all_tmp[ch * hr_pixels + p];
        }
        d_img_hr[p] = sum + bias;
    }
}

// CUDA kernel: Pad Image (for GPU path)
__global__ void pad_image_kernel(
    const double* __restrict__ d_img,
    double* __restrict__ d_img_pad,
    int rows, int cols, int padsize
) {
    int cols_pad = cols + 2 * padsize;
    int rows_pad = rows + 2 * padsize;

    int i = blockIdx.y * blockDim.y + threadIdx.y;
    int j = blockIdx.x * blockDim.x + threadIdx.x;

    if (i >= rows_pad || j >= cols_pad) return;

    int cnt_pad = i * cols_pad + j;

    if (i >= padsize && i < rows_pad - padsize &&
        j >= padsize && j < cols_pad - padsize) {
        int cnt = (i - padsize) * cols + (j - padsize);
        d_img_pad[cnt_pad] = d_img[cnt];
    } else if (i < padsize && j >= padsize && j < cols_pad - padsize) {
        int cnt = (j - padsize);
        d_img_pad[cnt_pad] = d_img[cnt];
    } else if (i >= rows_pad - padsize && j >= padsize && j < cols_pad - padsize) {
        int cnt = (rows - 1) * cols + (j - padsize);
        d_img_pad[cnt_pad] = d_img[cnt];
    } else if (i >= padsize && i < rows_pad - padsize && j < padsize) {
        int cnt = (i - padsize) * cols;
        d_img_pad[cnt_pad] = d_img[cnt];
    } else if (i >= padsize && i < rows_pad - padsize && j >= cols_pad - padsize) {
        int cnt = (i - padsize) * cols + (cols - 1);
        d_img_pad[cnt_pad] = d_img[cnt];
    } else {
        int src_i = (i < padsize) ? 0 : (i >= rows_pad - padsize) ? (rows - 1) : (i - padsize);
        int src_j = (j < padsize) ? 0 : (j >= cols_pad - padsize) ? (cols - 1) : (j - padsize);
        int cnt = src_i * cols + src_j;
        d_img_pad[cnt_pad] = d_img[cnt];
    }
}

#endif // __FSRCNN_GPU_KERNELS_CU__