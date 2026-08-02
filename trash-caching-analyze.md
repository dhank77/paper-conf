## Solusi untuk Cache Thrashing di SyncPilot-20W

Ada beberapa pendekatan, dari yang paling praktis sampai yang paling fundamental:

---

### 🥇 1. Cache-Aware Task Grouping (paling relevan untuk SyncPilot)

**Problem root**: Worker menarik task dari frame yang berbeda-beda secara acak → tidak ada data locality.

**Solusinya**: Pastikan satu worker menyelesaikan **semua 8 layer untuk 1 frame** sebelum pindah ke frame lain.

```c
// Sekarang (random):
Worker 0: Layer1_Frame1 → Layer3_Frame5 → Layer8_Frame2  ← 3 working set berbeda

// Dengan task grouping:
Worker 0: Layer1_Frame1 → Layer2_Frame1 → ... → Layer8_Frame1  ← 1 working set
```

**Efeknya**: Data frame yang sudah di L1/L2 dipakai sampai habis sebelum digusur. Tapi ini trade-off: mengorbankan load balancing (layer 8 bisa jadi bottleneck kalau di-assign ke satu worker terus).

---

### 🥈 2. Frame Buffer Partitioning per Core Cluster

**Prinsip**: Pisahkan frame buffer antara Big cluster dan LITTLE cluster agar tidak saling menggusur cache.

```
Big cores  (CPU 4-11): proses frame 1-10  → data di L2 Big cluster
LITTLE cores (CPU 0-3): proses frame 11-20 → data di L2 LITTLE cluster
```

IC-RCE sudah ada kapasitas untuk ini karena dia tau mana Big/LITTLE. Yang perlu ditambah: **affinity hint di task queue** agar task dari frame yang sama cenderung ditarik dari cluster yang sama.

---

### 🥉 3. Reduce Frame Buffer Precision (double → float)

Data aktual working set sekarang memakai `double` (8 bytes) untuk feature maps. Ganti ke `float` (4 bytes):

```
Sekarang : feature map = 176 × 144 × 56 filters × 8 bytes = ~11 MB per frame
Dengan float: feature map = 176 × 144 × 56 filters × 4 bytes = ~5.5 MB per frame
```

Working set per frame turun 50% → lebih banyak frame yang muat di L2 bersamaan → L2D refill turun drastis. Kualitas output FSRCNN sedikit turun tapi biasanya masih acceptable untuk video upscaling.

---

### 4. Tiling / Loop Blocking

**Untuk Layer 8 (deconv, penyumbang 51%)**: Proses output dalam tile kecil yang muat di L1:

```
Sekarang: proses seluruh output 352×288 sekaligus → 352×288×8 bytes ~800 KB
Tiling  : proses 32×32 tile → 32×32×8 bytes ~8 KB → muat di L1 (32-64 KB)
```

Ini teknik klasik dari BLAS/LAPACK. Tapi perlu modifikasi signifikan di `deconv` implementation.

---

### 5. Prefetching Manual

Instruksi `__builtin_prefetch()` untuk memberitahu hardware "data ini akan dibutuhkan 200 cycle lagi":

```c
// Di deconv loop:
for (int i = 0; i < output_size; i++) {
    __builtin_prefetch(&weight[i + PREFETCH_DISTANCE], 0, 1);
    result += input[i] * weight[i]; // sambil GPU fetch weight berikutnya
}
```

**Efek**: Mengurangi stall cycle karena hardware mulai fetch data sebelum dibutuhkan. L2D refill tetap terjadi tapi tidak blocking pipeline.

---

## Prioritas untuk Context Thesis

Untuk **future work** di paper, urutan yang paling realistis:

| Solusi                                          | Effort | Dampak | Cocok untuk paper?       |
| ----------------------------------------------- | ------ | ------ | ------------------------ |
| Frame buffer partitioning (affiniti Big/LITTLE) | Medium | Tinggi | ✅ ekstensi alami IC-RCE |
| double → float                                  | Rendah | Medium | ✅ mudah diukur          |
| Cache-aware task grouping                       | Medium | Tinggi | ✅ modifikasi scheduler  |
| Tiling di layer 8                               | Tinggi | Tinggi | ⚠️ perlu reimplementasi  |
| Prefetching manual                              | Medium | Medium | ⚠️ hardware-specific     |

**Yang paling "on-brand" dengan SyncPilot**: Frame buffer partitioning + IC-RCE awareness, karena IC-RCE sudah tau biaya tiap layer per core type — bisa diperluas untuk tau juga _cache locality budget_ tiap worker, dan assign task yang data-nya sudah hangat di cache cluster tersebut. Ini bisa jadi **motivasi future work** di paper tanpa perlu implementasi sekarang.
