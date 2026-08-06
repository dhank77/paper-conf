// Complete FSRCNN implementation with GPU-accelerated Layer 8
// Layers 1-7 run on CPU, Layer 8 runs on GPU (ASUS GX10 / GB10)
// Compile with: nvcc -arch=sm_90 -O3 -o fsrcnn_gpu fsrcnn_gpu_main.cu -lm

// Bypass glibc bits/math-vector.h ARM SVE/NEON vector math declarations for NVCC on ARM64
#ifndef _BITS_MATH_VECTOR_H
#define _BITS_MATH_VECTOR_H 1
#endif

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

#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime_api.h>
#include <string.h>

// Weight arrays
double weights_layer1[1400];
double biases_layer1[56];
double weights_layer2[672];
double biases_layer2[12];
double weights_layer3[1296];
double biases_layer3[12];
double weights_layer4[1296];
double biases_layer4[12];
double weights_layer5[1296];
double biases_layer5[12];
double weights_layer6[1296];
double biases_layer6[12];
double weights_layer7[672];
double biases_layer7[56];
double weights_layer8[4536];
double biases_layer8;

// Function declarations
void FSRCNN(double *img_hr, double *img_lr, int rows, int cols, int scale);
void FSRCNN_Layer8_GPU(double *img_hr, double *img_fltr_7, int rows, int cols, int scale);
void imfilter(double *img, double *kernel, double *img_fltr, int rows, int cols, int padsize);
void pad_image(double *img, double *img_pad, int rows, int cols, int padsize);
void PReLU(double *img_fltr, int rows, int cols, double bias, double prelu_coeff);
double Max(double a, double b);
double Min(double a, double b);
void imadd(double *img_fltr_sum, double *img_fltr_crnt, int cols, int rows);
void deconv(double *img_input, double *img_output, double *kernel, int cols, int rows, int stride);
void double_2_uint8(double *double_img, unsigned char *uint8_img, int cols, int rows);
void print_cuda_device_info(void);

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
// CUDA KERNELS
// ============================================================================

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

// ============================================================================
// Host wrapper: FSRCNN Layer 8 on GPU
// ============================================================================
void FSRCNN_Layer8_GPU(double* img_hr, double* img_fltr_7, int rows, int cols, int scale) {
    int filtersize8 = 81;
    int num_channels8 = 56;
    int hr_pixels = (rows * scale) * (cols * scale);
    
    int border = 1;
    int fsize = 9;
    int rows_pad = rows + 2 * border;
    int cols_pad = cols + 2 * border;
    int rows_out = rows * scale;
    int cols_out = cols * scale;
    
    double *d_input_padded = NULL;
    double *d_all_tmp = NULL;
    double *d_kernel8 = NULL;
    double *d_img_hr = NULL;
    
    CHECK_CUDA(cudaMalloc(&d_input_padded, rows_pad * cols_pad * sizeof(double)));
    CHECK_CUDA(cudaMalloc(&d_all_tmp, num_channels8 * hr_pixels * sizeof(double)));
    CHECK_CUDA(cudaMalloc(&d_kernel8, filtersize8 * sizeof(double)));
    CHECK_CUDA(cudaMalloc(&d_img_hr, hr_pixels * sizeof(double)));
    
    CHECK_CUDA(cudaMemcpy(d_kernel8, weights_layer8, filtersize8 * sizeof(double), cudaMemcpyHostToDevice));
    
    dim3 block_deconv(16, 16);
    dim3 grid_deconv((cols_out + block_deconv.x - 1) / block_deconv.x,
                     (rows_out + block_deconv.y - 1) / block_deconv.y);
    
    for (int j = 0; j < num_channels8; j++) {
        double* h_input_padded = (double*)malloc(rows_pad * cols_pad * sizeof(double));
        pad_image(img_fltr_7 + j * rows * cols, h_input_padded, rows, cols, border);
        
        CHECK_CUDA(cudaMemcpy(d_input_padded, h_input_padded, 
                              rows_pad * cols_pad * sizeof(double), 
                              cudaMemcpyHostToDevice));
        free(h_input_padded);
        
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
    
    CHECK_CUDA(cudaDeviceSynchronize());
    
    int threads_reduce = 256;
    int blocks_reduce = (hr_pixels + threads_reduce - 1) / threads_reduce;
    spatial_reduction_kernel<<<blocks_reduce, threads_reduce>>>(
        d_all_tmp, d_img_hr, biases_layer8, num_channels8, hr_pixels
    );
    CHECK_CUDA(cudaGetLastError());
    CHECK_CUDA(cudaDeviceSynchronize());
    
    CHECK_CUDA(cudaMemcpy(img_hr, d_img_hr, hr_pixels * sizeof(double), cudaMemcpyDeviceToHost));
    
    CHECK_CUDA(cudaFree(d_input_padded));
    CHECK_CUDA(cudaFree(d_all_tmp));
    CHECK_CUDA(cudaFree(d_kernel8));
    CHECK_CUDA(cudaFree(d_img_hr));
}

// ============================================================================
// CPU helper functions (unchanged from spatial reduction version)
// ============================================================================

void imfilter(double *img, double *kernel, double *img_fltr, int rows, int cols, int padsize) {
    int cols_pad = cols + 2 * padsize;
    int rows_pad = rows + 2 * padsize;
    int i, j, cnt, cnt_pad, cnt_krnl, k1, k2;
    double sum;
    
    double *img_pad = (double *)malloc(rows_pad * cols_pad * sizeof(double));
    pad_image(img, img_pad, rows, cols, padsize);
    
    for (i = padsize; i < rows_pad - padsize; i++)
    for (j = padsize; j < cols_pad - padsize; j++) {
        cnt = (i - padsize)*cols + (j - padsize);
        sum = 0;
        cnt_krnl = 0;
        for (k1 = -padsize; k1 <= padsize; k1++)
        for (k2 = -padsize; k2 <= padsize; k2++) {
            cnt_pad = (i + k1)*cols_pad + j + k2;
            sum = sum + (*(img_pad + cnt_pad))*(*(kernel + cnt_krnl));
            cnt_krnl++;
        }
        *(img_fltr + cnt) = sum;
    }
    
    free(img_pad);
    img_pad = NULL;
}

void pad_image(double *img, double *img_pad, int rows, int cols, int padsize) {
    int cols_pad = cols + 2 * padsize;
    int rows_pad = rows + 2 * padsize;
    int i, j, k, cnt, cnt_pad, k1, k2;
    
    for (i = padsize; i < rows_pad - padsize; i++)
    for (j = padsize; j < cols_pad - padsize; j++) {
        cnt_pad = i * cols_pad + j;
        cnt = (i - padsize)*(cols) + j - padsize;
        double x = *(img + cnt);
        *(img_pad + cnt_pad) = x;
    }
    
    for (j = padsize; j < cols_pad - padsize; j++)
    for (k = 0; k < padsize; k++) {
        cnt_pad = j + k*cols_pad;
        cnt = j - padsize;
        *(img_pad + cnt_pad) = *(img + cnt);
        cnt_pad = j + (rows_pad - 1 - k)* cols_pad;
        cnt = (j - padsize) + (rows - 1)*cols;
        *(img_pad + cnt_pad) = *(img + cnt);
    }
    
    for (i = padsize; i < rows_pad - padsize; i++)
    for (k = 0; k < padsize; k++) {
        cnt = (i - padsize)*cols;
        cnt_pad = i*cols_pad + k;
        *(img_pad + cnt_pad) = *(img + cnt);
        cnt = (i - padsize)*cols + cols - 1;
        cnt_pad = i*cols_pad + cols_pad - 1 - k;
        *(img_pad + cnt_pad) = *(img + cnt);
    }
    
    for (k1 = 0; k1 < padsize; k1++)
    for (k2 = 0; k2 < padsize; k2++) {
        cnt_pad = k1*cols_pad + k2;
        *(img_pad + cnt_pad) = *(img);
        cnt_pad = k1*cols_pad + cols_pad - 1 - k2;
        *(img_pad + cnt_pad) = *(img + cols - 1);
        cnt_pad = (rows_pad - 1 - k1)*cols_pad + k2;
        *(img_pad + cnt_pad) = *(img + (rows - 1)*cols);
        cnt_pad = (rows_pad - 1 - k1)*cols_pad + cols_pad - 1 - k2;
        *(img_pad + cnt_pad) = *(img + (rows - 1)*cols + cols - 1);
    }
}

void PReLU(double *img_fltr, int rows, int cols, double bias, double prelu_coeff) {
    int cnt = 0;
    for (int i = 0; i < rows; i++)
    for (int j = 0; j < cols; j++) {
        cnt = i*cols + j;
        *(img_fltr + cnt) = Max(*(img_fltr + cnt) + bias, 0) + 
                            prelu_coeff * Min(*(img_fltr + cnt) + bias, 0);
    }
}

double Max(double a, double b) {
    return a > b ? a : b;
}

double Min(double a, double b) {
    return a > b ? b : a;
}

void imadd(double *img_fltr_sum, double *img_fltr_crnt, int cols, int rows) {
    int cnt = 0;
    for (int i = 0; i < rows; i++)
    for (int j = 0; j < cols; j++) {
        cnt = i*cols + j;
        *(img_fltr_sum + cnt) = *(img_fltr_sum + cnt) + *(img_fltr_crnt + cnt);
    }
}

void deconv(double *img_input, double *img_output, double *kernel, int cols, int rows, int stride) {
    int border = 1;
    int fsize = 9;
    int rows_pad = rows + 2 * border;
    int cols_pad = cols + 2 * border;
    double *img_input_padded = (double *)malloc(rows_pad * cols_pad * sizeof(double));
    pad_image(img_input, img_input_padded, rows, cols, border);
    
    int rows_out_pad = rows_pad * stride;
    int cols_out_pad = cols_pad * stride;
    double *img_output_tmp = (double *)calloc((rows_out_pad + fsize - 1)* (cols_out_pad + fsize - 1), sizeof(double));
    double *kernel_modif = (double *)malloc(fsize * fsize * sizeof(double));
    
    int idx, idy;
    for (int i = 0; i < rows_pad; i++)
    for (int j = 0; j < cols_pad; j++) {
        int cnt_img = i*cols_pad + j;
        idx = i*stride;
        idy = j*stride;
        int cnt_img_output = idx*(cols_out_pad + fsize - 1) + idy;
        int cnt_kernel = 0;
        for (int k_r = 0; k_r < fsize; k_r++) {
            for (int k_c = 0; k_c < fsize; k_c++) {
                cnt_kernel = k_r*fsize + k_c;
                *(kernel_modif + cnt_kernel) = (*(kernel + cnt_kernel))*(*(img_input_padded + cnt_img));
                *(img_output_tmp + cnt_img_output + k_c) = *(img_output_tmp + cnt_img_output + k_c) + *(kernel_modif + cnt_kernel);
            }
            cnt_img_output = cnt_img_output + (cols_out_pad + fsize - 1);
        }
    }
    
    int rows_out = rows*stride;
    int cols_out = cols*stride;
    
    for (int i = 0; i < rows_out; i++)
    for (int j = 0; j < cols_out; j++) {
        int i_tmp = i + ((fsize + 1) / 2) + stride*border - 1;
        int j_tmp = j + ((fsize + 1) / 2) + stride*border - 1;
        int cnt_img_out = i*cols_out + j;
        int cnt_img_out_tmp = i_tmp*(cols_out_pad + fsize - 1) + j_tmp;
        *(img_output + cnt_img_out) = *(img_output_tmp + cnt_img_out_tmp);
    }
    
    free(img_input_padded); img_input_padded = NULL;
    free(img_output_tmp); img_output_tmp = NULL;
    free(kernel_modif); kernel_modif = NULL;
}

void double_2_uint8(double *double_img, unsigned char *uint8_img, int cols, int rows) {
    int i, j, cnt;
    for (i = 0; i < rows; i++)
    for (j = 0; j < cols; j++) {
        cnt = i*cols + j;
        double val = *(double_img + cnt);
        if (val < 0) val = 0;
        if (val > 255) val = 255;
        *(uint8_img + cnt) = (unsigned char)(val + 0.5);
    }
}

// ============================================================================
// FSRCNN main function (CPU Layers 1-7, GPU Layer 8)
// ============================================================================
void FSRCNN(double *img_hr, double *img_lr, int rows, int cols, int scale) {
    int num_layers = 8;
    
    // Layer 1
    int filtersize = 25;
    int patchsize = 5;
    int padsize = (patchsize - 1) / 2;
    int num_filters = 56;
    double prelu_coeff_layer1 = -0.8986;
    
    double *img_fltr_1 = (double *)malloc(rows * cols * num_filters * sizeof(double));
    double *kernel = (double *)malloc(filtersize*sizeof(double));
    double *img_fltr_p1 = img_fltr_1;
    
    for (int i = 0; i < num_filters; i++) {
        imfilter(img_lr, weights_layer1+i*filtersize, img_fltr_p1+i*cols*rows, rows, cols, padsize);
        PReLU(img_fltr_p1+i*cols*rows, rows, cols, biases_layer1[i], prelu_coeff_layer1);
    }
    
    // Layer 2
    int filtersize2 = 1;
    int patchsize2 = 1;
    int padsize2 = (patchsize2 - 1) / 2;
    int num_filters2 = 12;
    int num_channels2 = 56;
    double prelu_coeff_layer2 = 0.3236;
    
    double *img_fltr_2 = (double *)calloc(rows * cols * num_filters2, sizeof(double));
    double *kernel2 = (double *)malloc(filtersize2*sizeof(double));
    double *img_fltr_p2 = img_fltr_2;
    
    for (int i = 0; i < num_filters2; i++) {
        double img_fltr_2_tmp[rows*cols];
        for (int j = 0; j < num_channels2; j++) {
            imfilter(img_fltr_1+j*rows*cols, weights_layer2+(i*num_channels2+j)*filtersize2, img_fltr_2_tmp, rows, cols, padsize2);
            imadd(img_fltr_p2+i*cols*rows, img_fltr_2_tmp, cols, rows);
        }
        PReLU(img_fltr_p2+i*rows*cols, rows, cols, biases_layer2[i], prelu_coeff_layer2);
    }
    
    free(img_fltr_1); img_fltr_1 = NULL;
    free(kernel); kernel = NULL;
    
    // Layer 3
    int filtersize3 = 9;
    int patchsize3 = 3;
    int padsize3 = (patchsize3 - 1) / 2;
    int num_filters3 = 12;
    int num_channels3 = 12;
    double prelu_coeff_layer3 = 0.2288;
    
    double *img_fltr_3 = (double *)calloc(rows * cols * num_filters3, sizeof(double));
    double *kernel3 = (double *)malloc(filtersize3*sizeof(double));
    double *img_fltr_p3 = img_fltr_3;
    
    for (int i = 0; i < num_filters3; i++) {
        double img_fltr_3_tmp[rows*cols];
        for (int j = 0; j < num_channels3; j++) {
            imfilter(img_fltr_p2+j*rows*cols, weights_layer3+(i*num_channels3+j)*filtersize3, img_fltr_3_tmp, rows, cols, padsize3);
            imadd(img_fltr_p3+i*rows*cols, img_fltr_3_tmp, cols, rows);
        }
        PReLU(img_fltr_p3+i*rows*cols, rows, cols, biases_layer3[i], prelu_coeff_layer3);
    }
    
    free(img_fltr_2); img_fltr_2 = NULL;
    free(kernel2); kernel2 = NULL;
    free(kernel3); kernel3 = NULL;
    
    // Layer 4
    int filtersize4 = 9;
    int patchsize4 = 3;
    int padsize4 = (patchsize4 - 1) / 2;
    int num_filters4 = 12;
    int num_channels4 = 12;
    double prelu_coeff_layer4 = 0.2476;
    
    double *img_fltr_4 = (double *)calloc(rows * cols * num_filters4, sizeof(double));
    double *kernel4 = (double *)malloc(filtersize4*sizeof(double));
    double *img_fltr_p4 = img_fltr_4;
    
    for (int i = 0; i < num_filters4; i++) {
        double img_fltr_4_tmp[rows*cols];
        for (int j = 0; j < num_channels4; j++) {
            imfilter(img_fltr_p3+j*rows*cols, weights_layer4+(i*num_channels4+j)*filtersize4, img_fltr_4_tmp, rows, cols, padsize4);
            imadd(img_fltr_p4+i*rows*cols, img_fltr_4_tmp, cols, rows);
        }
        PReLU(img_fltr_p4+i*rows*cols, rows, cols, biases_layer4[i], prelu_coeff_layer4);
    }
    
    free(img_fltr_3); img_fltr_3 = NULL;
    free(kernel4); kernel4 = NULL;
    
    // Layer 5
    int filtersize5 = 9;
    int patchsize5 = 3;
    int padsize5 = (patchsize5 - 1) / 2;
    int num_filters5 = 12;
    int num_channels5 = 12;
    double prelu_coeff_layer5 = 0.3495;
    
    double *img_fltr_5 = (double *)calloc(rows * cols * num_filters5, sizeof(double));
    double *kernel5 = (double *)malloc(filtersize5*sizeof(double));
    double *img_fltr_p5 = img_fltr_5;
    
    for (int i = 0; i < num_filters5; i++) {
        double img_fltr_5_tmp[rows*cols];
        for (int j = 0; j < num_channels5; j++) {
            imfilter(img_fltr_p4+j*rows*cols, weights_layer5+(i*num_channels5+j)*filtersize5, img_fltr_5_tmp, rows, cols, padsize5);
            imadd(img_fltr_p5+i*rows*cols, img_fltr_5_tmp, cols, rows);
        }
        PReLU(img_fltr_p5+i*rows*cols, rows, cols, biases_layer5[i], prelu_coeff_layer5);
    }
    
    free(img_fltr_4); img_fltr_4 = NULL;
    free(kernel5); kernel5 = NULL;
    
    // Layer 6
    int filtersize6 = 9;
    int patchsize6 = 3;
    int padsize6 = (patchsize6 - 1) / 2;
    int num_filters6 = 12;
    int num_channels6 = 12;
    double prelu_coeff_layer6 = 0.7806;
    
    double *img_fltr_6 = (double *)calloc(rows * cols * num_filters6, sizeof(double));
    double *kernel6 = (double *)malloc(filtersize6*sizeof(double));
    double *img_fltr_p6 = img_fltr_6;
    
    for (int i = 0; i < num_filters6; i++) {
        double img_fltr_6_tmp[rows*cols];
        for (int j = 0; j < num_channels6; j++) {
            imfilter(img_fltr_p5+j*rows*cols, weights_layer6+(i*num_channels6+j)*filtersize6, img_fltr_6_tmp, rows, cols, padsize6);
            imadd(img_fltr_p6+i*rows*cols, img_fltr_6_tmp, cols, rows);
        }
        PReLU(img_fltr_p6+i*rows*cols, rows, cols, biases_layer6[i], prelu_coeff_layer6);
    }
    
    free(img_fltr_5); img_fltr_5 = NULL;
    free(kernel6); kernel6 = NULL;
    
    // Layer 7
    int filtersize7 = 1;
    int patchsize7 = 1;
    int padsize7 = (patchsize7 - 1) / 2;
    int num_filters7 = 56;
    int num_channels7 = 12;
    double prelu_coeff_layer7 = 0.0087;
    
    double *img_fltr_7 = (double *)calloc(rows * cols * num_filters7, sizeof(double));
    double *kernel7 = (double *)malloc(filtersize7*sizeof(double));
    double *img_fltr_p7 = img_fltr_7;
    
    for (int i = 0; i < num_filters7; i++) {
        double img_fltr_7_tmp[rows*cols];
        for (int j = 0; j < num_channels7; j++) {
            imfilter(img_fltr_p6+j*rows*cols, weights_layer7+(i*num_channels7+j)*filtersize7, img_fltr_7_tmp, rows, cols, padsize7);
            imadd(img_fltr_p7+i*rows*cols, img_fltr_7_tmp, cols, rows);
        }
        PReLU(img_fltr_p7+i*rows*cols, rows, cols, biases_layer7[i], prelu_coeff_layer7);
    }
    
    free(img_fltr_6); img_fltr_6 = NULL;
    free(kernel7); kernel7 = NULL;
    
    // Layer 8: GPU version with spatial reduction
    FSRCNN_Layer8_GPU(img_hr, img_fltr_p7, rows, cols, scale);
    
    free(img_fltr_7); img_fltr_7 = NULL;
}

// ============================================================================
// Main
// ============================================================================
int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input.yuv> <output.yuv>\n", argv[0]);
        return 1;
    }
    
    char *inFile = argv[1];
    char *outFile = argv[2];
    
    int scale = 2;
    int num = 150;
    int inCols = 176;
    int inRows = 144;
    int outCols = inCols * scale;
    int outRows = inRows * scale;
    
    // Initialize CUDA
    CHECK_CUDA(cudaSetDevice(0));
    print_cuda_device_info();
    
    // Read weights (same as CPU version)
    FILE *fp;
    // Read weights (identical to CPU version)
    FILE *weights_layer1_ptr;
    weights_layer1_ptr = fopen("weights_layer1.txt", "r");
    if (weights_layer1_ptr == NULL) { printf("Error reading weights_layer1\n"); return 1; };
    for (int i = 0; i < 1400; i++) fscanf(weights_layer1_ptr, "%lf", &weights_layer1[i]);
    fclose(weights_layer1_ptr);
    
    FILE *biases_layer1_ptr;
    biases_layer1_ptr = fopen("biasess_layer1.txt", "r");
    if (biases_layer1_ptr == NULL) { printf("Error reading biases_layer1\n"); return 1; };
    for (int i = 0; i < 56; i++) fscanf(biases_layer1_ptr, "%lf", &biases_layer1[i]);
    fclose(biases_layer1_ptr);
    
    FILE *weights_layer2_ptr;
    weights_layer2_ptr = fopen("weights_layer2.txt", "r");
    if (weights_layer2_ptr == NULL) { printf("Error reading weights_layer2\n"); return 1; };
    for (int i = 0; i < 672; i++) fscanf(weights_layer2_ptr, "%lf", &weights_layer2[i]);
    fclose(weights_layer2_ptr);
    
    FILE *biases_layer2_ptr;
    biases_layer2_ptr = fopen("biasess_layer2.txt", "r");
    if (biases_layer2_ptr == NULL) { printf("Error reading biases_layer2\n"); return 1; };
    for (int i = 0; i < 12; i++) fscanf(biases_layer2_ptr, "%lf", &biases_layer2[i]);
    fclose(biases_layer2_ptr);
    
    FILE *weights_layer3_ptr;
    weights_layer3_ptr = fopen("weights_layer3.txt", "r");
    if (weights_layer3_ptr == NULL) { printf("Error reading weights_layer3\n"); return 1; };
    for (int i = 0; i < 1296; i++) fscanf(weights_layer3_ptr, "%lf", &weights_layer3[i]);
    fclose(weights_layer3_ptr);
    
    FILE *biases_layer3_ptr;
    biases_layer3_ptr = fopen("biasess_layer3.txt", "r");
    if (biases_layer3_ptr == NULL) { printf("Error reading biases_layer3\n"); return 1; };
    for (int i = 0; i < 12; i++) fscanf(biases_layer3_ptr, "%lf", &biases_layer3[i]);
    fclose(biases_layer3_ptr);
    
    FILE *weights_layer4_ptr;
    weights_layer4_ptr = fopen("weights_layer4.txt", "r");
    if (weights_layer4_ptr == NULL) { printf("Error reading weights_layer4\n"); return 1; };
    for (int i = 0; i < 1296; i++) fscanf(weights_layer4_ptr, "%lf", &weights_layer4[i]);
    fclose(weights_layer4_ptr);
    
    FILE *biases_layer4_ptr;
    biases_layer4_ptr = fopen("biasess_layer4.txt", "r");
    if (biases_layer4_ptr == NULL) { printf("Error reading biases_layer4\n"); return 1; };
    for (int i = 0; i < 12; i++) fscanf(biases_layer4_ptr, "%lf", &biases_layer4[i]);
    fclose(biases_layer4_ptr);
    
    FILE *weights_layer5_ptr;
    weights_layer5_ptr = fopen("weights_layer5.txt", "r");
    if (weights_layer5_ptr == NULL) { printf("Error reading weights_layer5\n"); return 1; };
    for (int i = 0; i < 1296; i++) fscanf(weights_layer5_ptr, "%lf", &weights_layer5[i]);
    fclose(weights_layer5_ptr);
    
    FILE *biases_layer5_ptr;
    biases_layer5_ptr = fopen("biasess_layer5.txt", "r");
    if (biases_layer5_ptr == NULL) { printf("Error reading biases_layer5\n"); return 1; };
    for (int i = 0; i < 12; i++) fscanf(biases_layer5_ptr, "%lf", &biases_layer5[i]);
    fclose(biases_layer5_ptr);
    
    FILE *weights_layer6_ptr;
    weights_layer6_ptr = fopen("weights_layer6.txt", "r");
    if (weights_layer6_ptr == NULL) { printf("Error reading weights_layer6\n"); return 1; };
    for (int i = 0; i < 1296; i++) fscanf(weights_layer6_ptr, "%lf", &weights_layer6[i]);
    fclose(weights_layer6_ptr);
    
    FILE *biases_layer6_ptr;
    biases_layer6_ptr = fopen("biasess_layer6.txt", "r");
    if (biases_layer6_ptr == NULL) { printf("Error reading biases_layer6\n"); return 1; };
    for (int i = 0; i < 12; i++) fscanf(biases_layer6_ptr, "%lf", &biases_layer6[i]);
    fclose(biases_layer6_ptr);
    
    FILE *weights_layer7_ptr;
    weights_layer7_ptr = fopen("weights_layer7.txt", "r");
    if (weights_layer7_ptr == NULL) { printf("Error reading weights_layer7\n"); return 1; };
    for (int i = 0; i < 672; i++) fscanf(weights_layer7_ptr, "%lf", &weights_layer7[i]);
    fclose(weights_layer7_ptr);
    
    FILE *biases_layer7_ptr;
    biases_layer7_ptr = fopen("biasess_layer7.txt", "r");
    if (biases_layer7_ptr == NULL) { printf("Error reading biases_layer7\n"); return 1; };
    for (int i = 0; i < 56; i++) fscanf(biases_layer7_ptr, "%lf", &biases_layer7[i]);
    fclose(biases_layer7_ptr);
    
    FILE *weights_layer8_ptr;
    weights_layer8_ptr = fopen("weights_layer8.txt", "r");
    if (weights_layer8_ptr == NULL) { printf("Error reading weights_layer8\n"); return 1; };
    for (int i = 0; i < 4536; i++) fscanf(weights_layer8_ptr, "%lf", &weights_layer8[i]);
    fclose(weights_layer8_ptr);
    
    FILE *biases_layer8_ptr;
    biases_layer8_ptr = fopen("biasess_layer8.txt", "r");
    if (biases_layer8_ptr == NULL) { printf("Error reading biases_layer8\n"); return 1; };
    fscanf(biases_layer8_ptr, "%lf", &biases_layer8);
    fclose(biases_layer8_ptr);
    
    // For brevity, assume weights are loaded here
    // Same file reading logic as fsrcnn_parallel_spatial_reduction.c
    
    unsigned char *inBuf = (unsigned char *)malloc(inCols*inRows*sizeof(unsigned char));
    unsigned char *outBuf = (unsigned char *)malloc(outCols*outRows*sizeof(unsigned char));
    double *inBuf_tmp = (double *)malloc(inCols*inRows*sizeof(double));
    double *outBuf_tmp = (double *)malloc(outCols*outRows*sizeof(double));
    
    FILE *inFp = fopen(inFile, "rb");
    FILE *outFp = fopen(outFile, "wb");
    
    for (int fcnt = 0; fcnt < num; fcnt++) {
        unsigned char *inP = inBuf;
        double *inP_tmp = inBuf_tmp;
        unsigned char *outP = outBuf;
        double *outP_tmp = outBuf_tmp;
        
        // Y Component
        fread(inBuf, sizeof(unsigned char), inCols*inRows, inFp);
        for (int i = 0; i < inRows; i++)
        for (int j = 0; j < inCols; j++) {
            int cnt = i*inCols + j;
            int x = *inP++;
            *(inP_tmp + cnt) = (double)(x / 255.0);
        }
        
        FSRCNN(outP_tmp, inP_tmp, inRows, inCols, scale);
        
        for (int i = 0; i < inRows*scale; i++)
        for (int j = 0; j < inCols*scale; j++) {
            int cnt = i*inCols*scale + j;
            *(outP_tmp + cnt) = *(outP_tmp + cnt) * 255;
        }
        
        double_2_uint8(outP_tmp, outP, outCols, outRows);
        fwrite(outBuf, sizeof(unsigned char), outCols*outRows, outFp);
        
        // U Component
        fread(inBuf, sizeof(unsigned char), inCols*inRows / 4, inFp);
        inP = inBuf; outP = outBuf;
        for (int i = 0; i < inRows / 2; i++)
        for (int j = 0; j < inCols / 2; j++) {
            int cnt = 2 * (i * outCols / 2 + j);
            unsigned char x = *inP++;
            *(outP + cnt) = x;
            *(outP + cnt + 1) = x;
            *(outP + cnt + outCols / 2) = x;
            *(outP + cnt + outCols / 2 + 1) = x;
        }
        fwrite(outBuf, sizeof(unsigned char), outCols*outRows / 4, outFp);
        
        // V Component
        fread(inBuf, sizeof(unsigned char), inCols*inRows / 4, inFp);
        inP = inBuf; outP = outBuf;
        for (int i = 0; i < inRows / 2; i++)
        for (int j = 0; j < inCols / 2; j++) {
            int cnt = 2 * (i*outCols / 2 + j);
            unsigned char x = *inP++;
            *(outP + cnt) = x;
            *(outP + cnt + 1) = x;
            *(outP + cnt + outCols / 2) = x;
            *(outP + cnt + outCols / 2 + 1) = x;
        }
        fwrite(outBuf, sizeof(unsigned char), outCols*outRows / 4, outFp);
    }
    
    free(inBuf); free(inBuf_tmp); free(outBuf); free(outBuf_tmp);
    fclose(inFp); fclose(outFp);
    
    return 0;
}
