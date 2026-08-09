# Pengambilan data yang masih kurang — `reviews/03.md`

Empat skrip. Semua dijalankan dari dalam direktori `plans/`. Tidak ada yang
perlu difoto, tidak ada power meter, tidak ada yang perlu ditunggui.

| Skrip | Jalankan di | Durasi | Menjawab |
|---|---|---|---|
| `collect_env.sh` | **GX10 (GB10) DAN RTX 4090** | ~2 detik | Review #1 — versi CUDA, Tabel I |
| `collect_gpu_profile.sh` | **GX10 (GB10) DAN RTX 4090** | ~5–8 menit | H2D/D2H di RTX, SD kernel time, split dua kernel di Tabel III |
| `collect_reconstruction_quality.sh` | **RTX 4090 saja** | ~4 menit | Uji kualitas rekonstruksi self-contained (section C) |
| `collect_v0_frame26.sh` | **RTX 4090 saja** | ~4 menit | Provenance Fig. 1 panel (b) |

Urutan yang disarankan: `collect_env.sh` dulu di kedua mesin (dua detik, dan
hasilnya menentukan apakah klaim perbedaan toolkit di §VI-A boleh berdiri).
Sisanya bebas.

---

## 1. `collect_env.sh` — kedua mesin

```bash
cd plans
bash collect_env.sh
```

Ini yang paling penting dan paling murah. **Harus dijalankan di host yang
benar-benar mem-build dan menjalankan eksperimen GB10**, bukan di login node.

Alasannya: `results/spesifikasi/75-gcc-nvcc.txt` melaporkan CUDA 12.0, tapi
dump itu diambil di host bernama `node6`. Sementara `results/gpu-4.txt`
melaporkan GB10 sebagai Compute 12.1 dengan `-arch=native`. Tidak mungkin
keduanya benar — sm_121 itu target Blackwell yang tidak bisa di-emit toolkit
mana pun sebelum CUDA 12.8. Jadi `node6` bukan mesin GB10-nya.

Skrip ini mencetak hostname ke dalam output supaya provenance-nya tercatat
sendiri, dan mengetes apakah `-arch=native` benar-benar jalan.

Kirim balik: `results_env_gb10.txt` dan `results_env_rtx4090.txt`.

## 2. `collect_gpu_profile.sh` — kedua mesin

```bash
cd plans
bash collect_gpu_profile.sh
# REPS=10 bash collect_gpu_profile.sh   # kalau mau lebih banyak repetisi
```

Menyapu kelima konfigurasi grid dari sweep asli (16x16_256, 8x8_256,
32x8_256, 16x16_128, 16x16_512), 6 repetisi masing-masing, dua fase:

- **Fase A** pakai binary produksi (`fsrcnn_gpu_main.cu`) — ini angka yang
  masuk paper. Memberi mean ± SD untuk wall, `gpu_l8`, `h2d`, `d2h`,
  `cpu_l17`. Sekaligus menutup kolom RTX di Tabel III yang selama ini kosong,
  dan memberi error bar untuk Fig. 3 yang sekarang cuma titik telanjang.
- **Fase B** pakai `fsrcnn_gpu_instrumented.cu` — memisahkan `deconv_kernel`
  dari `spatial_reduction_kernel`.

Thread backdrop untuk layer 1–7 di-set otomatis mengikuti run yang sudah
dipublikasi: 20 di GB10, 4 di RTX 4090. Jangan diubah kecuali sengaja.

Kirim balik: `results_gpuprofile_<tag>.{txt,csv,rawlog}` dari kedua mesin.

### Soal Fase B

Baca hasilnya sebagai dekomposisi `gpu_l8`, bukan pengganti. Window
`gpu_l8_ms` membungkus seluruh urutan launch, dan 56 copy H2D per-channel
di-issue **di dalam** window itu — jadi `deconv + reduce` akan keluar lebih
kecil dari `gpu_l8`. Selisihnya dilaporkan apa adanya sebagai
`in_window_other_ms`, tidak diam-diam dilebur ke salah satu kernel.

Perekaman event menambah ~112 event record per frame. Kalau `gpu_l8` di Fase B
meleset jauh dari Fase A, berarti instrumentasinya mengganggu dan angka split
harus disebut indikatif, bukan eksak. Skripnya mencetak kedua angka
berdampingan supaya ini kelihatan.

## 3. `collect_reconstruction_quality.sh` — RTX 4090 saja

```bash
cd plans
bash collect_reconstruction_quality.sh
```

Butuh `ffmpeg`. Tidak perlu dijalankan dua kali — V2 bit-exact di kedua
platform, jadi hasilnya identik.

Semua angka kualitas di paper sekarang sebetulnya cuma uji **konsistensi
diri**: V2 vs V1, makanya berbunyi "inf (bit-exact)". Itu membuktikan port
GPU-nya setia, tapi sama sekali tidak membuktikan jaringannya merekonstruksi
apa pun — tidak ada frame high-resolution ground truth di mana pun, karena
`suzie_qcif.yuv` itu inputnya, bukan versi downsample dari sesuatu yang lebih
besar.

Skrip ini membuat ground truth yang hilang itu: Suzie 176×144 di-downsample
bicubic ke 88×72, dimasukkan ke FSRCNN scale 2 untuk kembali ke 176×144, lalu
dinilai terhadap 176×144 aslinya. Pembandingnya bicubic upscale dari 88×72
yang sama.

Ambil komponen `y:`, bukan `average` — hanya plane Y yang lewat jaringan, U
dan V cuma replikasi piksel 2× di source.

**Kalau FSRCNN kalah dari bicubic, tulis apa adanya di paper.** Klaim speedup
berdiri sendiri terlepas dari hasil ini, dan hasil negatif di sini jujur dan
tetap layak publikasi. Jangan diutak-atik protokolnya sampai angkanya bagus.

Kirim balik: `results_quality_rtx4090.txt` + folder `quality_frames/`.

## 4. `collect_v0_frame26.sh` — RTX 4090 saja

```bash
cd plans
bash collect_v0_frame26.sh
```

Fig. 1 panel (b) berlabel "32 threads" dengan 23.0 dB / SSIM 0.845. Tapi
thread ladder GB10 di `results/gpu-4.txt` berhenti di 20, dan angka itu persis
ada di `results/76-rtx4090v3.txt:333` — baris 32-thread RTX 4090. Sementara
§IV-A dulu menulis gambar itu "shows the GB10 case". Salah satu pasti keliru,
dan tidak ada catatan mesin mana yang menghasilkan `v0_frame26.png`.

Daripada menebak, regenerate di host yang identitasnya tercetak di output.

Satu hal yang harus diantisipasi: V0 itu varian yang racy. Outputnya
nondeterministik — justru itu isi gambarnya — jadi PSNR-nya **tidak akan**
kembali persis 23.005696 dB. Skripnya jalan tiga kali supaya sebarannya
kelihatan, dan paper bisa menyebut "representative run" dengan rentang, bukan
berpura-pura satu nilai yang reproducible.

Kirim balik: `results_v0frame_rtx4090.txt` + folder `v0_frames_rtx4090/`.

---

## `fsrcnn_gpu_instrumented.cu`

Diturunkan mekanis dari `fsrcnn_gpu_main.cu`. Numeriknya identik byte-for-byte
— dua kernel launch tidak disentuh. Yang ditambahkan cuma:

1. Event CUDA per-launch untuk memisahkan `deconv_kernel` dari
   `spatial_reduction_kernel`, di-drain setelah `cudaEventSynchronize`
   terakhir supaya tidak menambah serialisasi.
2. Geometri input bisa di-override lewat environment (`FSRCNN_ROWS`,
   `FSRCNN_COLS`, `FSRCNN_FRAMES`), karena binary produksi hardcode 176×144
   dan eksperimen kualitas butuh 88×72. Default-nya nilai lama, jadi tanpa
   env var perilakunya persis sama.

Jangan pakai binary ini untuk angka headline.
