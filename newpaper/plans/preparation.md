# Rencana Pengambilan Data Awal — Spatial Reduction FSRCNN on GPU

## Paper konferensi: percepatan FSRCNN Layer 8 dengan spatial reduction pada GPU

Dokumen ini menentukan data yang harus dikumpulkan sebelum kerangka paper
dikunci. Fase 0 memperbaiki hal-hal yang membuat pengukuran tidak valid.
Fase 2 berisi _decision gate_ yang menentukan poros paper.

Jangan menulis abstract atau kontribusi sebelum Fase 2 selesai.

---

## Target Hardware: ASUS Ascent GX10

**Platform**: ASUS Ascent GX10 Desktop AI Supercomputer
- **SoC**: NVIDIA GB10 Grace Blackwell Superchip
- **CPU**: 20-core ARM v9.2-A (10× Cortex-X925 + 10× Cortex-A725)
- **GPU**: NVIDIA Blackwell (GB10), 384 CUDA cores, Tensor Cores Gen 5
- **Memory**: 128 GB LPDDR5x unified system memory (CPU + GPU share)
- **Interconnect**: NVLink-C2C (5× PCIe 5.0 bandwidth between CPU and GPU)
- **CUDA**: 12.1+, Compute Capability sm_90
- **OS**: NVIDIA DGX OS (Ubuntu-based, aarch64/ARM64)

**Implications for implementation:**
- Must compile with `-arch=sm_90` and run on ARM64 (aarch64)
- Unified memory means `cudaMallocManaged` works, but explicit `cudaMemcpy` also works
- No PCIe bottleneck for CPU-GPU transfers (NVLink-C2C)
- Stack size on GPU may be limited; avoid large local arrays in kernels

---

## Konteks dan kode baseline

| Varian | File | Deskripsi |
|--------|------|-----------|
| V0 — naive CPU | `fsrcnn_parallel.c` | Layer 8: deconv per channel ke buffer bersama `img_fltr_8`, akumulasi dengan `imadd`. Ada race condition jika dijalankan dengan thread >1. |
| V1 — spatial reduction CPU | `fsrcnn_parallel_spatial_reduction.c` | Layer 8: deconv per channel ke buffer privat `all_tmp[j * hr_pixels]`, lalu reduksi spasial per piksel (`sum += all_tmp[j * hr_pixels + p]`). Tidak ada race, output deterministik. |
| V2 — spatial reduction GPU | `fsrcnn_gpu_main.cu` | V1 yang Layer 8 dijalankan di GPU (CUDA, sm_90, GX10). Kontribusi paper. |

**Pertanyaan riset:** apakah pemindahan sumbu paralelisme Layer 8 ke GPU
menggunakan spatial reduction memberikan kecepatan signifikan tanpa
mengorbankan ketepatan, dan apakah pendekatan ini menawarkan batas memori
yang lebih baik daripada reduction `omp` pada CPU?

---

## Fase 0 — Prasyarat (wajib, sebelum mengukur apa pun)

### 0.1 Kompilasi CPU baseline

Kompilasi V0 (naive) dan V1 (spatial reduction CPU) untuk baseline:

```bash
gcc -fopenmp -O3 -o fsrcnn_cpu fsrcnn_parallel_spatial_reduction.c -lm
```

Verifikasi binary berjalan:
```bash
./fsrcnn_cpu suzie.yuv test_output.yuv
ls -lh test_output.yuv  # Harus 22,809,600 byte
```

V0 dan V1 punya `double_2_uint8` yang berbeda. V0 memakai loop 255 iterasi
per piksel; V1 sudah O(1). Untuk perbandingan yang adil, V0 harus
digunakan versi O(1) yang sama.

**Tindakan:** ganti `double_2_uint8` di V0 dengan versi O(1). Rebuild V0
dan V1. Verifikasi kedua binary menghasilkan output identik pada
single-thread.

### 0.2 Ground truth dari eksekusi serial

Ground truth harus dihasilkan oleh binary single-thread yang deterministik.

**Tindakan:** hasilkan `ground_truth.yuv` dari V0 dengan `OMP_NUM_THREADS=1`.
Verifikasi ukuran 22.809.600 byte, simpan SHA-256 hash-nya.

### 0.3 Siapkan pencatatan mentah

Semua run harus tercatat per-run.

**Format CSV** (`raw_results.csv`):

```
run_id,variant,threads,device,wall_ms,diff_bytes,total_bytes,pct_diff,psnr_db,peak_rss_kb
```

Perintah pengambilan per run:

```bash
DIFF=$(cmp -l ground_truth.yuv out.yuv 2>/dev/null | wc -l)
PSNR=$(ffmpeg -s 352x288 -pix_fmt yuv420p -i ground_truth.yuv \
              -s 352x288 -pix_fmt yuv420p -i out.yuv \
              -lavfi psnr -f null - 2>&1 | grep average | tail -1)
```

Peak RSS: `/usr/bin/time -v` untuk CPU, `nvidia-smi` atau `cuMemGetInfo`
untuk GPU.

### 0.4 Siapkan lingkungan GPU (GX10)

- Instal CUDA toolkit untuk ARM64: `sudo apt install nvidia-cuda-toolkit`
- Verifikasi dengan `deviceQuery` (dari CUDA samples) atau `nvidia-smi`
- Compile V2 dengan: `nvcc -arch=sm_90 -O3 -o fsrcnn_gpu fsrcnn_gpu_main.cu -lm -lcudart`
- Pastikan executable berjalan: `./fsrcnn_gpu --help` atau test dengan sample input

### 0.5 Verifikasi bit-exactness

Pastikan V2 menghasilkan output identik dengan ground truth:
```bash
# Generate ground truth dengan CPU single-thread
OMP_NUM_THREADS=1 ./fsrcnn_cpu input_test.yuv ground_truth.yuv

# Run GPU version
./fsrcnn_gpu input_test.yuv out_gpu.yuv

# Compare
cmp ground_truth.yuv out_gpu.yuv
# atau hitung diff_bytes
DIFF=$(cmp -l ground_truth.yuv out_gpu.yuv 2>/dev/null | wc -l)
echo "Diff bytes: $DIFF"
```

**Checklist Fase 0**

- [x] `double_2_uint8` disamakan, V0 dan V1 di-rebuild
- [x] Ground truth serial dibuat dan di-hash
- [x] CSV logging siap (termasuk 7-run repetition Mean ± SD & breakdown profiling)
- [x] Lingkungan GPU terverifikasi (NVIDIA GB10 sm_90)
- [x] V2 diimplementasikan dan menghasilkan output identik dengan ground truth (100% bit-exact)

---

## Fase 1 — Validasi kebenaran (E1)

**Tujuan:** membuktikan bahwa V1 dan V2 menghasilkan output identik dengan
ground truth, dan bahwa V1 setidaknya tidak lebih buruk dari V0.

**Prosedur:**

1. Jalankan V0, V1, V2 masing-masing 5 run dengan `OMP_NUM_THREADS=1` (untuk
   V2: tidak ada thread, hanya 1 block GPU).
2. Hitung `diff_bytes` dan PSNR terhadap ground truth.

**Yang dicatat:**

| Varian | diff_bytes | pct_diff | PSNR (dB) | Wall (ms) |
|--------|-----------|----------|-----------|-----------|
| V0 naive | | | | |
| V1 spatial CPU | | | | |
| V2 spatial GPU | | | | |

**Kriteria lulus:**
- V1: `diff_bytes == 0` (bit-exact dengan ground truth)
- V2: `diff_bytes == 0` (bit-exact dengan ground truth)
- V2 wall time harus lebih cepat dari V0 (setidaknya pada thread >1)

**Decision gate Fase 1:**

| Kondisi | Kesimpulan | Aksi |
|---------|-----------|------|
| V1 dan V2 keduanya bit-exact | Lulus, lanjut ke Fase 2 | — |
| V1 bit-exact, V2 tidak | Debug transfer memori GPU, presisi floating point | Perbaiki V2 sebelum lanjut |
| V1 tidak bit-exact | Ada bug di spatial reduction | Perbaiki V1 terlebih dahulu |

---

## Fase 2 — Karakterisasi performa CPU (E2)

**Tujuan:** memahami baseline CPU sebelum mengukur GPU.

**Prosedur:** jalankan V0 dan V1 pada 1, 2, 4, 8, 16 thread — **7 run per
konfigurasi** (70 run total). Run 1 dibuang sebagai warmup, laporkan mean ±
SD dari 6 run tersisa.

**Yang dicatat per run:** `wall_ms`, `peak_rss_kb`.

**Yang dilaporkan:**
- Speedup V1 relatif V0 per jumlah thread
- Apakah V1 menskala sebaik V0
- Apakah ada overhead V1 akibat alokasi `all_tmp`

---

## Fase 3 — Karakterisasi performa GPU (E3, inti kontribusi)

**Tujuan:** mengukur seberapa cepat V2 dibanding V0 dan V1, dan
mengidentifikasi batasan.

**Prosedur:** jalankan V2 pada GPU dengan konfigurasi berikut:
- 1 block, 256 thread
- 1 block, 512 thread
- 2 block, 256 thread
- 4 block, 256 thread
- 8 block, 256 thread

**7 run per konfigurasi**, run 1 dibuang.

**Yang dicatat per run:** `wall_ms`, `peak_rss_kb` (GPU memory via
`cuMemGetInfo`).

**Yang dilaporkan:**
- Throughput V2 vs V0 vs V1 (frame/detik)
- Speedup V2 relatif V0 dan V1
- GPU memory usage V2
- Apakah ada konfigurasi yang optimal

---

## Fase 4 — Analisis memori dan backpressure (E4)

**Tujuan:** membuktikan bahwa pendekatan spatial reduction memiliki batas
memori yang lebih manageable daripada reduction `omp` pada CPU.

**Perbandingan arsitektur:**

| Varian | Batas memori | Catatan |
|--------|-------------|---------|
| V0 naive CPU | 0 (race, tidak bisa diandalkan) | — |
| V1 spatial CPU | `rows × cols × 8 byte` (buffer `all_tmp`) | Tetap di heap, kecil |
| V2 spatial GPU | `hr_pixels × 8 byte × 56 channel` di VRAM | Dikelola oleh CUDA runtime |
| V2 reduction omp (teoritis) | `hr_pixels × 8 byte × num_threads` | Tidak bisa disetel tanpa mengurangi paralelisme |

**Prosedur:** ukur peak RSS V0, V1, V2 pada konfigurasi optimal masing-masing.
Hitung memory bandwidth V2 (data transferred / wall time).

---

## Fase 5 — Skala resolusi (E5)

**Tujuan:** membuktikan bahwa kecepatan relatif V2 tetap menguntungkan
pada resolusi berbeda.

**Prosedur:** jalankan ketiga varian pada resolusi berikut:
- CIF: 352×288 (baseline)
- HD: 640×480
- FHD: 1280×720

**Yang dicatat:** speedup V2/V0 per resolusi, scaling efficiency.

**Yang dicari:** apakah V2 tetap lebih cepat secara mutlak saat ukuran
output membesar, dan apakah transfer CPU–GPU menjadi bottleneck.

---

## Fase 6 — Opsional

### 6.1 ThreadSanitizer pada V0 (E6)

```bash
gcc -fsanitize=thread -fopenmp -g -O1 -o fsrcnn_naive_tsan fsrcnn_parallel.c -lm
```

Jalankan pada 5 frame. Dokumentasikan apakah race di `imadd` terdeteksi.

### 6.2 Precisi floating point (E7)

Bandingkan V2 dengan `float` vs `double` di CUDA. Apakah `float` cukup
tanpa kehilangan PSNR? Jika ya, ini jadi poin optimasi memori tambahan.

### 6.3 Integrasi full GPU (E8)

Pindahkan Layer 1–7 ke GPU juga, ukur end-to-end speedup. Tentukan apakah
spatial reduction Layer 8 masih menjadi bottleneck atau tidak.

---

## Ringkasan beban eksperimen

| Fase                 | Jumlah run              | Perkiraan waktu                   |
| -------------------- | ----------------------- | --------------------------------- |
| 0 — prasyarat        | ~10 (verifikasi)        | 2–3 jam (termasuk implementasi V2) |
| 1 — validasi kebenaran | 15 (3 varian × 5 run)  | 30 menit                          |
| 2 — CPU scaling      | 70 (2 varian × 7 konfig × 7 run) | ~2 jam |
| 3 — GPU konfigurasi  | 42 (6 konfig × 7 run)   | ~1 jam                            |
| 4 — analisis memori  | 21 (3 varian × 7 run)   | 30 menit                          |
| 5 — skala resolusi   | 63 (3 varian × 3 resolusi × 7 run) | ~1 jam |
| **Total inti**       | **211**                 | **~1 hari kerja**                 |
| 6 — opsional         | —                       | 0,5–2 hari                        |

---

## Kriteria penerimaan paper

Paper layak disubmit kalau terpenuhi minimal:
1. V2 bit-exact dengan ground truth
2. V2 lebih cepat dari V0 dan V1 pada setidaknya satu konfigurasi
3. Ada analisis yang menjelaskan mengapa spatial reduction cocok untuk GPU
   (memori terisolasi per channel, reduksi spasial = reduction yang GPU
   lakukan dengan baik)
4. Ada perbandingan dengan baseline CPU yang adil (double_2_uint8 sama,
   preprocessing sama)
