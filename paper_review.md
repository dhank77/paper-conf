Berikut review saya. Saya baca cukup teliti termasuk memeriksa konsistensi angka antar tabel — dan di situ ada beberapa temuan yang perlu Anda perbaiki sebelum submit.

**Penilaian umum:** ide dan eksekusi eksperimennya solid, tulisannya rapi dan enak dibaca. Tapi kalau saya jadi reviewer, ini *major revision* — bukan karena hasilnya lemah, melainkan karena (a) kontribusi yang Anda klaim sebagai novelty tidak divalidasi, dan (b) ada beberapa inkonsistensi numerik yang akan langsung dipakai reviewer untuk mempertanyakan reliabilitas data.

---

## Masalah kritis

**1. Tabel V tidak konsisten secara internal**

Jumlah kolom "Time (s)" = 0.09432 s, bukan 0.09032 s seperti yang tertulis di baris Total. Dan kolom "% Total" berjumlah **104.4%**. Persentase per baris konsisten kalau dibagi 0.09032, jadi kemungkinan ada satu nilai layer yang salah ketik (selisihnya tepat 0.004 s — periksa Layer 3 atau Layer 7). Ini harus dibetulkan; reviewer yang menjumlahkan kolom akan langsung menemukannya.

Masalah kedua yang lebih substansial: 0.09032 s/frame × 150 frame = **13.5 s**, sementara serial baseline Anda 10.445 s. Ada gap ~30% yang tidak dijelaskan. Kalau tabel kalibrasi tidak bisa direkonsiliasi dengan baseline serial, asumsi determinisme IC-RCE jadi dipertanyakan. Beri penjelasan eksplisit (cold cache saat run kalibrasi? overhead `clock_gettime` per-stage? frame pertama saja?).

**2. Baseline yang tidak konsisten di Tabel VII**

Baris Idle memakai serial 10452 ms (10452/1133 = 9.23✓, 10452/1046 = 9.99✓). Tapi baris noise tidak: 10452/1216 = 8.60, bukan 8.37 seperti yang tertulis. Semua angka speedup pada baris noise konsisten dengan baseline ≈**10175 ms** (10175/1216 = 8.37✓, 10175/1314 = 7.74✓, 10175/1402 = 7.26✓, 10175/1689 = 6.02✓). Jadi dalam satu tabel Anda memakai dua baseline serial berbeda tanpa penjelasan — dan yang lebih aneh, baseline pada kondisi noise justru lebih *cepat*. Ini harus diperbaiki atau dijelaskan.

**3. Tidak ada ablasi untuk IC-RCE — padahal ini novelty utama**

Anda mengklaim IC-RCE + capacity-aware pulling sebagai kontribusi inti, tapi tidak ada satu pun eksperimen yang mengisolasinya. Yang dibandingkan hanya SyncPilot vs serial dan SyncPilot vs CFS. Yang wajib ada:

- SyncPilot-20W dengan pulling FIFO/acak (pinned, tapi *capacity-agnostic*) → ini yang mengukur nilai IC-RCE
- SyncPilot dengan continuous profiling → ini yang membuktikan klaim "overhead near-zero" secara empiris, bukan retoris

Tanpa dua baris ini, seluruh argumen novelty bertumpu pada asersi. Ini gap paling merusak dalam paper.

**4. Section VI-B berjudul "Comparison with OpenMP Affinity Approaches" tapi tidak ada satu pun pengukuran OpenMP**

Isinya perbandingan dengan serial baseline. Ini akan dibaca sebagai overclaim. Entah jalankan baseline OpenMP dengan `OMP_PLACES`/`proc_bind` yang sebanding (idealnya reimplementasi pendekatan [14] di GX10), atau ganti judul sectionnya menjadi analisis kualitatif dan hilangkan implikasi bahwa Anda mengukurnya.

**5. Threshold T tidak pernah didefinisikan**

Logika penjadwalan Anda bergantung pada `Cost > Threshold`, tapi nilainya, cara pemilihannya, dan sensitivitasnya tidak pernah disebut. Ini parameter inti mekanisme yang Anda usulkan.

Terkait ini — saya menduga **kebijakan biner Anda justru yang membuat CFS-20W menang 7.6% di kondisi idle.** Coba hitung: L7+L8 = 64.4% beban, dan kalau threshold memisahkannya ke Big saja, 10 core Big menanggung 64.4% beban sementara 10 core A725 menanggung 35.6%. Dengan rasio kapasitas A725/X925 sekitar 0.7, sisi Big menjadi bottleneck (0.0644 vs 0.0509 unit-waktu), sehingga LITTLE idle. Ini menjelaskan defisit throughput Anda secara kuantitatif, dan mengubahnya dari "kelemahan yang harus diakui" menjadi **analisis yang menguatkan paper**. Solusinya: *work-conserving fallback* (LITTLE boleh menarik tugas berat kalau queue Big menumpuk) atau pembagian proporsional-biaya alih-alih threshold biner. Kata "Prioritize" di Section III-C sebenarnya menyiratkan fallback — kalau memang ada, jelaskan; kalau tidak ada, ini eksperimen tambahan yang berpotensi memperbaiki hasil Anda.

**6. Metrik jitter terlalu lemah untuk klaim utama Anda**

"Max/Jitter" adalah nilai maksimum dari 7 run — itu estimator jitter yang sangat bising, dan jitter secara definisi adalah variasi *frame-to-frame*, bukan run-to-run. Karena robustness terhadap noise adalah kontribusi terkuat paper ini, metriknya harus kuat: catat latensi per-frame (150 sampel × 7 run), lalu laporkan p95/p99, standar deviasi, dan CDF atau boxplot. Ini juga sekaligus mengisi kekosongan besar lain — **tidak ada satu pun standar deviasi atau interval kepercayaan di seluruh paper**, padahal Anda menyebut 1343 vs 1345 ms "statistically indistinguishable" tanpa uji statistik apa pun.

**7. gprof tidak reliabel untuk program multithread**

Di Linux, gprof secara default hanya menyampel thread utama. Klaim "SyncPilot framework functions = 0.00 s self time" sebagai bukti overhead sinkronisasi negligible hampir pasti artefak instrumentasi, bukan temuan. Ini juga bertentangan dengan penjelasan Anda sendiri di Section V-D bahwa penurunan instruksi di 20W sebagian disebabkan berkurangnya busy-wait/spinlock — busy-wait itu *seharusnya* muncul sebagai self-time di fungsi framework. Ganti ke `perf record`/`perf report` per-thread, atau tetap pakai gprof tapi turunkan klaimnya secara signifikan.

---

## Masalah framing (akan ditanya reviewer di kalimat pertama)

**8. GX10 bukan big.LITTLE, dan sulit disebut edge device**

Kalau ini ASUS Ascent GX10 (kernel `6.17.0-1018-nvidia` + 10× X925 / 10× A725 mengarah ke NVIDIA GB10 Grace Blackwell), maka:

- Ini bukan ARM big.LITTLE, melainkan cluster heterogen Armv9 (DynamIQ), tanpa efficiency core sejati (tidak ada A5xx/A520). Anda sudah menyinggung ini, tapi paper tetap menyebut A725 sebagai "LITTLE" di sepanjang teks. Saran: reframe konsisten sebagai **big + mid**, dan akui bahwa temuan Anda tentang scaling ke seluruh cluster kemungkinan *tidak* berlaku pada big.LITTLE klasik (A55/A510) — ini justru memperkuat kontribusi Anda karena membedakan platform Anda dari [14] secara arsitektural, bukan cuma "lebih kuat".
- Perangkatnya adalah workstation dev seharga beberapa ribu dolar dengan GPU Blackwell, bukan edge device khas. Reviewer **pasti** menanyakan: mengapa menjalankan inferensi DNN di CPU pada mesin yang seluruh alasan keberadaannya adalah GPU-nya? Jawab preemptively di Section V-A (misal: memodelkan skenario CPU-only/GPU-contended, atau memposisikan GX10 murni sebagai *proxy* untuk topologi CPU Armv9 heterogen generasi terbaru).

**9. Klaim energi tanpa data energi**

Intro dan Section III-C mengklaim efisiensi energi ("maximizing energy efficiency for trivial computations"), tapi tidak ada satu pengukuran daya. Di platform NVIDIA ini biasanya tersedia telemetri daya on-board. Entah ukur, atau hapus semua klaim energi dari intro dan kontribusi dan sisakan sebagai future work saja.

**10. Reposisi paper: temuan terbaik Anda terkubur di Discussion**

Novelty IC-RCE (profiling sekali saat startup) jujurnya tipis — ini teknik yang sudah lazim, dan sangat dekat dengan offline profiling Pipe-it. Yang benar-benar menarik dan publishable adalah **Section VI-C**: demonstrasi empiris bahwa mekanisme overutilization EAS gagal di bawah beban sistem realistis, sehingga hard-pinning menang pada jitter meskipun kalah pada throughput idle. Itu temuan yang berguna dan tidak trivial. Saya sangat menyarankan restrukturisasi dengan itu sebagai kontribusi utama, dan IC-RCE sebagai mekanisme pendukung. Sekalian: nyatakan jitter dalam angka absolut (1427 vs 1769 ms) dan bukan hanya pertumbuhan relatif dari baseline masing-masing (21.9% vs 65.8%) — framing relatif terlihat seperti spin, padahal angka absolut Anda tetap menang, jadi tidak ada gunanya mengambil risiko itu.

---

## Masalah minor

- **Tabel II memuat kolom "2W"** yang tidak pernah dideskripsikan di setup (konfigurasi yang didaftarkan hanya 4W/8W/10W/20W).
- **Tabel II baris IPC 20W (2.97)** disajikan sebagai data padahal teks menyebutnya artefak sampling. Beri tanda bintang + catatan kaki, atau pisahkan.
- **Tiga nilai IPC Big-cluster yang berbeda** (2.95 di EXP-2, 3.60 di EXP-3, 2.99 di EXP-4) tanpa tabel yang menjelaskan setup EXP-2/3/4. Pembaca tidak bisa memverifikasi apa pun. Buat tabel kecil untuk eksperimen kontrol ini.
- **Penjelesan ganda yang saling bersaing** untuk penurunan instruksi 20W (artefak PMU *dan* pengurangan busy-wait). Pilih satu, atau jelaskan kontribusi masing-masing.
- **Paragraf "Two hardware-level mechanisms..."** ada di Section V-E (profiling fungsi) padahal isinya tentang perf counter — pindahkan ke V-D.
- **Tabel V dirujuk di Section V-E** sebelum diperkenalkan di V-F. Urutkan ulang.
- **Persentase Tabel IV** berjumlah 98.28%, dan 4.74/9.12 = 52.0% bukan 51.08%. Periksa lagi.
- **Verifikasi korektnes:** teks menyebut "a ground-truth reference frame" (tunggal). Klarifikasi bahwa semua 150 frame diverifikasi. Juga, "infinite PSNR" lebih baik dinyatakan sebagai bit-exact / MSE = 0. Dan turunkan sedikit klaimnya: FSRCNN deterministik + reorder buffer, jadi bit-exactness itu *ekspektasi*, bukan temuan — nilainya ada sebagai kontras terhadap korupsi piksel di [14], dan itu saja sudah cukup kuat.
- **Efisiensi paralel:** 9.39× pada 20 core = ~47% efisiensi. Sebutkan dan bahas. Terkait: dengan 150 frame independen, paralelisme level-frame nyaris embarrassingly parallel — reviewer akan bertanya mengapa pipeline 8-stage lebih baik daripada `parallel for` atas frame. Perlu dijawab.
- **Reproducibility:** tidak ada governor cpufreq, kondisi termal, status GPU, flag kompilasi untuk baseline, apakah noise thread dipin atau tidak (Anda sebut unpinned — pertimbangkan varian yang dipin ke cluster Big untuk kasus terburuk), dan tidak ada link artifact/kode.
- **Section IV (Implementation) hanya 5 kalimat** dan tumpang tindih dengan V-A. Isi dengan hal yang sekarang hilang: struktur data queue (Anda menyebut "lock-free" di V-E tapi "tanpa global lock" di III-C tanpa deskripsi implementasi apa pun), mekanisme reorder buffer, algoritma pull dalam bentuk pseudocode.
- **Gambar:** Fig 1 dan Fig 2 menampilkan data yang sama (FPS dan waktu adalah kebalikan satu sama lain). Buang satu, ganti dengan diagram arsitektur atau CDF jitter. Paper ini tidak punya diagram arsitektur sama sekali — untuk paper sistem itu kelemahan nyata.
- **Abstract ~250 kata**, agak panjang untuk format IEEE.
- **Referensi:** verifikasi [16] (pola DOI `s41598-026-...` tidak lazim) dan tahun [1] (Pipe-it TCAD vol. 39 no. 10 umumnya tercatat 2020). Kutipan langsung dari dokumentasi kernel di VI-C sebaiknya diparafrase saja.
- **[14] tampaknya self-citation** (co-author Adnan yang sama). Tidak masalah, tapi perbedaan terhadap [14] harus dinyatakan lebih tegas dan lebih awal — saat ini paragraf pembuka Related Work hampir seluruhnya merangkum [14], yang membuat paper terasa seperti follow-up inkremental. Section V-F juga mencampur atribusi: dibuka dengan "reference paper [14] conducted..." lalu Tabel V justru pengukuran Anda sendiri di GX10.

---

## Yang sudah bagus

Supaya seimbang: struktur naratifnya jelas, analisis anomali IPC 20W menunjukkan kejujuran ilmiah yang jarang (banyak penulis akan menyembunyikannya), eksperimen kontrol EXP-2/3/4 untuk mengeliminasi hipotesis kontensi L3 adalah kerja yang benar, dan yang paling saya hargai — Anda **melaporkan bahwa CFS mengalahkan metode Anda** di kondisi idle, lalu membangun eksperimen noise untuk menjelaskannya. Itu justru yang membuat paper ini kredibel dan menarik. Jangan hilangkan itu; jadikan pusat paper.

---

## Prioritas perbaikan

1. Betulkan Tabel V (jumlah kolom + rekonsiliasi dengan serial baseline) dan baseline ganda di Tabel VII.
2. Tambahkan ablasi capacity-agnostic pulling dan continuous-profiling.
3. Ganti metrik jitter ke distribusi per-frame; tambahkan std dev/CI di semua tabel.
4. Jalankan baseline OpenMP, atau ubah judul Section VI-B.
5. Definisikan threshold T + uji work-conserving fallback (berpotensi memperbaiki hasil idle Anda).
6. Reframe terminologi hardware (big+mid, bukan big.LITTLE) dan jawab pertanyaan "mengapa CPU, bukan GPU".
7. Reposisi Section VI-C sebagai kontribusi utama.
8. Ganti gprof dengan perf per-thread, atau turunkan klaim overhead 0.00s.

Kalau mau, saya bisa bantu drafting ulang abstract + intro dengan framing baru (EAS-failure sebagai kontribusi utama), atau menyusun tabel ablasi yang perlu Anda isi.