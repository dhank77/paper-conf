# Panduan Referensi `itis.tex`

Anotasi 21 referensi: apa isinya, **kenapa** dikutip di paper Anda dan di bagian mana,
serta apa yang layak didalami. Tautan diambil dari `references.md` dan
`plans/new_references.md` yang sudah diverifikasi, bukan dari ingatan.

Tanda **(terbuka)** = bisa diakses tanpa langganan.

Dikelompokkan menurut peran di paper, bukan urutan nomor, supaya jelas
mana yang menopang klaim mana.

---

## A. Fondasi: model FSRCNN itu sendiri

Tiga referensi ini menjelaskan *apa* yang Anda percepat. Kalau waktu terbatas,
dahulukan kelompok ini.

### [2] Dong, Loy, Tang — "Accelerating the Super-Resolution CNN" (ECCV 2016)
`dong2016fsrcnn` · dikutip di Pendahuluan, Penelitian Terkait, §IV-C
https://link.springer.com/chapter/10.1007/978-3-319-46475-6_25

Makalah FSRCNN aslinya. Inilah sumber arsitektur delapan lapis yang Anda pakai
(Feature Extraction → Shrinking → 4× Mapping → Expanding → Deconvolution) beserta
alasan desainnya: ekstraksi fitur ditahan di ruang resolusi rendah, upscaling
ditunda ke lapisan terakhir. Itu persis yang membuat Layer 8 jadi bottleneck
Anda, jadi makalah ini menjelaskan *mengapa* masalah Anda ada.

**Dalami:** kenapa lapisan shrinking (56→12) dan expanding (12→56) diperlukan.
Ini langsung relevan dengan temuan Anda bahwa Layer 2 dan 7 termahal.

### [10] Dong, Loy, He, Tang — "Learning a Deep CNN for Image Super-Resolution" (ECCV 2014)
`dong2014srcnn` · dikutip di Pendahuluan, Penelitian Terkait
https://doi.org/10.1007/978-3-319-10593-2_13

SRCNN, pendahulu FSRCNN dari kelompok yang sama. Di paper Anda ia berfungsi
sebagai penanda garis waktu ("formulasi awal digantikan FSRCNN"). Bacanya
berguna untuk memahami apa yang diperbaiki FSRCNN: SRCNN meng-upscale di awal
dengan bicubic lalu bekerja di resolusi tinggi — mahal, dan justru itu yang
dihindari FSRCNN.

### [16] Dumoulin & Visin — "A Guide to Convolution Arithmetic for Deep Learning" (arXiv 2016)
`dumoulin2016convolution` · dikutip di §II-B **(terbuka)**
https://arxiv.org/pdf/1603.07285

Bukan makalah riset, melainkan panduan bergambar tentang aritmetika konvolusi
dan **transposed convolution** — operasi inti Layer 8 Anda. Kalau ada satu
dokumen yang paling membantu memahami kenapa dekonvolusi stride-2 menulis ke
lokasi yang tumpang tindih (dan karenanya menimbulkan race), ini dia.

**Dalami:** bagian transposed convolution. Ini menjelaskan akar masalah race
yang jadi motivasi seluruh paper Anda.

---

## B. Karya terdekat dan keabsahan baseline

### [1] Annisa, Adnan, Zainuddin — FSRCNN serial→paralel pada arsitektur AMP (IEEE AIMS 2025)
`annisa2025` · dikutip di Pendahuluan, Penelitian Terkait
https://doi.org/10.1109/AIMS66189.2025.11229650

**Referensi terpenting untuk posisi paper Anda.** Satu grup dengan Anda, sekuens
Suzie yang sama, race Layer 8 yang sama, tapi di Orange Pi 5 (RK3588S). Mereka
*mengarakterisasi* korupsinya lintas afinitas inti; Anda *memperbaikinya* secara
algoritmik lalu memindahkannya ke GPU. Reviewer hampir pasti membuka ini untuk
mengecek apakah kontribusi Anda benar-benar berbeda.

**Dalami:** temuan mereka bahwa korupsi lebih parah pada inti LITTLE. Bandingkan
dengan temuan Anda tentang 68.6 dB yang nyaris tak terdeteksi di RTX 4090 — dua
sisi dari argumen yang sama, bahwa keparahan race tidak bisa dijadikan ukuran.

### [4] Wang dkk. — "High-Throughput CNN Inference on Embedded ARM big.LITTLE" (IEEE TCAD 2020)
`wang2020pipeit` · dikutip di Penelitian Terkait, §V-A **(preprint terbuka)**
https://arxiv.org/abs/1903.05898 · IEEE: https://ieeexplore.ieee.org/document/8852739

Dikenal sebagai PipeIt. Perannya di paper Anda spesifik dan penting: menjadi
bukti bahwa inferensi CNN **bisa** menskala baik di ARM big.LITTLE kalau
dijadwalkan benar. Itulah yang membuat kalimat "baseline GB10 kami bukan
strawman" punya dasar. Tanpa referensi ini, klaim tersebut hanya asersi.

**Dalami:** relevan sekali dengan temuan Anda tentang kunci paralelisme
12-filter. PipeIt memakai penjadwalan pipeline lintas klaster; implementasi
referensi Anda memparalelkan atas filter saja. Ini pembanding langsung untuk
diskusi Anda.

---

## C. Determinisme dan race

### [14] Serebryany & Iskhodzhanov — "ThreadSanitizer" (WBIA 2009)
`serebryany2009threadsanitizer` · dikutip di §II-C
https://doi.org/10.1145/1791194.1791203

Detektor race dinamis dari Google. Di paper Anda ia dipakai sekali, untuk
menamai kelas bug yang dialami V0. Nilainya bagi Anda bukan pada alatnya,
melainkan pada kerangka berpikirnya: race terdeteksi secara probabilistik,
bergantung pada penjadwalan yang kebetulan terjadi.

**Dalami:** justru ini yang memperkuat argumen inti Anda. Deteksi dinamis hanya
menemukan race yang *kebetulan* terpicu pada run itu — persis alasan kenapa
determinisme secara konstruktif (V1/V2) lebih kuat daripada pengujian.

---

## D. CUDA, warp, dan pustaka

### [7] NVIDIA — CUDA C++ Programming Guide
`nvidiacudaguide` · dikutip di §III-B, §VII-C **(terbuka)**
https://docs.nvidia.com/cuda/cuda-c-programming-guide/

Rujukan normatif untuk granularitas warp 32 thread dan aturan memory coalescing
— dasar argumen grid $32{\times}8$ Anda.

**Dalami:** bab *Device Memory Accesses* / coalescing. Di situ dijelaskan kenapa
blok selebar 32 membuat satu warp jatuh ke satu transaksi memori, sementara
blok selebar 16 memecahnya. Ini penjelasan mekanis di balik perolehan 23.4%.

### [15] Lashgar, Baniasadi, Khonsari — "Warp Size Impact in GPUs: Large or Small?" (GPGPU-5, 2012)
`lashgar2012warpresize` · dikutip di §III-B **(terbuka)**
https://arxiv.org/abs/1208.2374

Menopang premis Kontribusi 2: penentuan ukuran warp/blok berpengaruh orde
pertama pada throughput SIMT. Reviewer sempat menandai kalimat ini ketika
sitasinya hilang, jadi ia memang menanggung beban argumen.

**Dalami:** trade-off warp besar vs kecil (efisiensi SIMD lawan divergensi).
Berguna kalau nanti Anda menguji lebar blok tak selaras seperti $64{\times}4$,
yang tercatat sebagai pekerjaan lanjutan.

### [13] Chetlur dkk. — "cuDNN: Efficient Primitives for Deep Learning" (arXiv 2014)
`chetlur2014cudnn` · dikutip di Penelitian Terkait, §III-B **(terbuka)**
https://arxiv.org/abs/1410.0759

Pustaka primitif konvolusi standar dari NVIDIA. Di paper Anda ia muncul sebagai
pembatas klaim: Anda tidak mengklaim mengalahkan cuDNN, hanya menguasai tata
letak memorinya. Ketiadaan pembanding cuDNN adalah **celah terbesar** yang
diakui Limitations.

**Dalami:** bagaimana cuDNN mengimplementasikan konvolusi (GEMM, FFT, Winograd).
Ini menjelaskan kenapa pustaka umum sulit memberi jaminan bit-exact yang Anda
butuhkan — algoritmanya memilih urutan penjumlahan yang berbeda-beda.

---

## E. Memori terpadu vs diskret

Kelompok ini menopang Kontribusi 4 dan judul paper.

### [21] Wahlgren dkk. — "Dissecting CPU-GPU Unified Physical Memory on AMD MI300A" (IEEE IISWC 2025)
`wahlgren2025upm` · dikutip di Penelitian Terkait, §VII-D
https://doi.org/10.1109/IISWC66894.2025.00038 · arXiv: https://arxiv.org/abs/2508.12743 **(terbuka)**

**Karya paling sebanding metodologinya dengan Anda.** Mereka membedah memori
fisik terpadu pada APU MI300A; Anda melakukan hal setara pada GB10 versus RTX
4090. Kalau ada satu referensi untuk dibaca serius sebelum menulis versi jurnal,
ini pilihannya.

**Dalami:** metrik dan metodologi yang mereka pakai untuk memisahkan efek memori
terpadu. Anda bisa meminjamnya untuk memperkuat argumen L2/bandwidth yang saat
ini masih inferensi.

### [8] Go dkk. — "APUNet: Revitalizing GPU as Packet Processing Accelerator" (USENIX NSDI 2017)
`go2017apunet` · dikutip di Penelitian Terkait, §VII-D **(terbuka)**
https://www.usenix.org/conference/nsdi17/technical-sessions/presentation/go

Menunjukkan overhead PCIe/DMA pada GPU diskret bisa memakan seluruh keuntungan
akselerasi untuk payload kecil, dan berargumen APU dengan memori terpadu lebih
unggul di kelas beban itu. Di paper Anda ia melatarbelakangi perbandingan
terpadu vs diskret.

**Dalami:** menarik karena hasil Anda **sebagian bertentangan** dengan mereka.
Payload Anda kecil (44 MiB), tetapi GPU diskret tetap menang karena keunggulan
komputasi dan L2. Ketegangan ini bahan diskusi yang bagus untuk versi jurnal.

### [20] NVIDIA — Grace Hopper Superchip Architecture In-Depth (2022)
`nvidiagracehopper2022` · dikutip di §VII-D **(terbuka)**
https://developer.nvidia.com/blog/nvidia-grace-hopper-superchip-architecture-in-depth/

Penjelasan resmi NVLink-C2C dan koherensi memori CPU-GPU. Rujukan teknis untuk
"kolam terpadu" yang Anda bandingkan.

### [17] NVIDIA — pengumuman GB10 / Grace Blackwell (Newsroom, Jan 2025)
`nvidiagb10_2025` · dikutip di §III-A **(terbuka)**
https://nvidianews.nvidia.com/news/nvidia-puts-grace-blackwell-on-every-desk-and-at-every-ai-developers-fingertips

Siaran pers, bukan dokumen teknis. Dipakai semata sebagai rujukan resmi
keberadaan dan spesifikasi platform utama Anda.

### [19] NVIDIA — Ada GPU Architecture Whitepaper (2022)
`nvidiaada2022` · dikutip 2× di §III-A **(terbuka)**
https://images.nvidia.com/aem-dam/Solutions/geforce/ada/nvidia-ada-gpu-architecture.pdf

Sumber angka 16.384 CUDA core / 128 SM di Tabel I. **Di sini juga sumber
kapasitas L2 72 MB** yang menopang penjelasan cache Anda.

**Dalami:** bagian hierarki cache. Ada 72 MB L2 pada AD102 — lompatan besar dari
generasi sebelumnya, dan justru itulah yang membuat buffer privat 43.31 MiB Anda
muat. Ini penjelasan paling langsung untuk celah 10× pada kernel reduksi.

---

## F. Penjadwalan CPU asimetris

Menopang §VII-A (keruntuhan RTX 4090) dan konteks big.LITTLE.

### [5] Bilbao, Saez, Prieto-Matías — PMCSched, kasus Intel Alder Lake (CCPE 2023)
`bilbao2023pmcsched` · dikutip di Penelitian Terkait
https://doi.org/10.1002/cpe.7814

Penjadwalan perangkat lunak sistem untuk multicore asimetris, dengan Alder Lake
(pembagian P-core/E-core yang sama seperti i9-14900K Anda) sebagai studi kasus.
Landasan pustaka untuk keruntuhan thread yang Anda amati.

### [6] Eichenberger dkk. — "The Design of OpenMP Thread Affinity" (IWOMP 2012)
`eichenberger2012ompaffinity` · dikutip di Penelitian Terkait, §VII-A
https://doi.org/10.1007/978-3-642-30961-8_2

Rancangan `OMP_PLACES` dan `OMP_PROC_BIND`. Relevan karena kolam OpenMP generik
Anda **tidak** memakai kendali afinitas ini — itulah dugaan penyebab keruntuhan
past 8 thread, dan eksperimen kendalinya tercatat di Limitations.

**Dalami:** semantik `OMP_PROC_BIND`. Kalau nanti Anda menutup limitation itu,
di sinilah rancangan eksperimennya.

### [18] Arm — DynamIQ technology
`armdynamiq` · dikutip di §III-A **(terbuka)**
https://www.arm.com/technologies/dynamiq

Halaman teknologi resmi untuk klaster big.LITTLE pada CPU GB10 (10× X925 +
10× A725).

---

## G. Model kinerja klasik

### [11] Amdahl — "Validity of the Single Processor Approach" (AFIPS 1967)
`amdahl1967` · dikutip di §VI-B
https://doi.org/10.1145/1465482.1465560

Makalah asli Hukum Amdahl, hanya tiga halaman. Menopang argumen sentral §VI-B:
setelah Layer 8 dipercepat, bagian yang tidak dipindahkan (71.4% / 84.5%) yang
menentukan langit-langitnya.

**Dalami:** pendek dan layak dibaca utuh. Argumennya justru lebih tajam daripada
kutipan turunan yang biasa beredar.

### [12] Williams, Waterman, Patterson — "Roofline" (CACM 2009)
`williams2009roofline` · dikutip di §VI-B
https://doi.org/10.1145/1498765.1498785

Model visual yang memetakan kinerja terhadap intensitas aritmetika untuk
menentukan apakah sebuah kernel terikat komputasi atau memori. Di paper Anda ia
disebut sebagai alat yang *akan* dipakai untuk memutuskan strategi pemindahan
Layer 1–7.

**Dalami:** ini yang paling operasional untuk langkah Anda berikutnya. Analisis
Roofline akan memberi jawaban yang saat ini masih Anda simpulkan dari bandwidth
efektif saja — termasuk klaim bahwa reduksi terikat bandwidth.

---

## H. Metrik kualitas

### [9] Wang, Bovik, Sheikh, Simoncelli — "Image Quality Assessment: SSIM" (IEEE TIP 2004)
`wang2004ssim` · dikutip di §IV-A **(terbuka)**
https://ece.uwaterloo.ca/~z70wang/publications/ssim.html

Makalah SSIM asli, salah satu yang paling banyak disitasi di pengolahan citra.
Anda memakainya berdampingan dengan PSNR.

**Dalami:** justru argumen pembukanya yang relevan bagi Anda — kenapa PSNR buruk
sebagai ukuran kualitas persepsi. Ini menguatkan keputusan Anda melaporkan
*bit-exact* alih-alih PSNR untuk V1/V2, dan menjelaskan kenapa race 68.6 dB bisa
lolos dari ambang PSNR.

---

## I. Konteks penerapan

### [3] Shi, Cao, Zhang, Li, Xu — "Edge Computing: Vision and Challenges" (IEEE IoT J. 2016)
`shi2016edge` · dikutip di Pendahuluan, Penelitian Terkait
https://doi.org/10.1109/JIOT.2016.2579198

Makalah survei yang membingkai komputasi edge. Perannya di paper Anda murni
kontekstual: kalimat pembuka tentang SoC yang menyatukan CPU dan GPU. Paling
tidak sentral di antara 21 referensi — bacalah abstrak dan pendahuluannya saja
kecuali Anda memang ingin memperluas motivasi edge.

---

## Urutan baca yang saya sarankan

Kalau waktunya terbatas, empat ini dulu:

1. **[16] Dumoulin** — memahami transposed convolution, akar masalah race Anda
2. **[2] FSRCNN** — model yang Anda percepat
3. **[1] Annisa dkk.** — karya terdekat, satu grup, akan dicek reviewer
4. **[21] Wahlgren dkk.** — metodologi paling sebanding, paling berguna untuk versi jurnal

Lalu, kalau ingin menutup Limitations: **[12] Roofline** dan **[19] whitepaper Ada**
(bab cache) adalah dua yang paling langsung menopang Kontribusi 4.
