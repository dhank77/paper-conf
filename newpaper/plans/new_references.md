# New references added to itis.tex (RTX 4090 cross-platform section)

Added 2026-08-07 to support the new Section VI ("Cross-Platform Validation on
Discrete-GPU Hardware"). Check each link yourself before trusting the
citation — status notes below are from automated fetch attempts, not a
guarantee.

---

## 1. Intel hybrid architecture / Thread Director

**Cite key:** `intelhybrid2021`

Intel Corporation, "Optimizing Software for x86 Hybrid Architecture,"
Document No. 348851-001US, Rev. 1.0, Oct. 2021.

- Landing page: https://www.intel.com/content/www/us/en/content-details/818776/optimizing-software-for-x86-hybrid-architecture.html
- Direct PDF: https://cdrdv2-public.intel.com/818776/348851-optimizing-x86-hybrid-cpus.pdf

**Verification status:** Both URLs returned HTTP 403 to the automated
fetcher (Intel's site blocks bot traffic on these paths), so I could not
read the content directly. The title/doc-number/URL combination is
consistent across multiple independent search-engine results, and the
domain (`intel.com` / `cdrdv2-public.intel.com`, Intel's own document CDN)
is legitimate — but **please open the link yourself in a browser to
confirm it resolves** before relying on it. If it's dead, the document is
also generally discoverable by searching "Intel document 348851-001US".

---

## 2. Asymmetric multicore scheduling (Alder Lake)

**Cite key:** `bilbao2023pmcsched`

C. Bilbao, J. C. Saez, and M. Prieto-Matías, "Flexible system software
scheduling for asymmetric multicore systems with PMCSched: A case for
Intel Alder Lake," *Concurrency and Computation: Practice and Experience*,
vol. 35, no. 25, e7814, 2023.

- DOI: https://doi.org/10.1002/cpe.7814
- Wiley page: https://onlinelibrary.wiley.com/doi/10.1002/cpe.7814

**Verification status:** DOI resolves correctly (302 redirect from
doi.org to the Wiley page) — confirms the DOI is real and live. The Wiley
page itself is paywalled (403 to automated fetch), so I could not read
the abstract directly, but author names/title/venue/volume/issue were
cross-confirmed via independent search results. This looks solid.

---

## 3. OpenMP thread affinity design

**Cite key:** `eichenberger2012ompaffinity`

A. E. Eichenberger, C. Terboven, M. Wong, and D. an Mey, "The Design of
OpenMP Thread Affinity," in *OpenMP in a Heterogeneous World (IWOMP
2012)*, Lecture Notes in Computer Science, vol. 7312, Springer, 2012,
pp. 15–28.

- DOI: https://doi.org/10.1007/978-3-642-30961-8_2
- Springer page: https://link.springer.com/chapter/10.1007/978-3-642-30961-8_2

**Verification status:** Found via search only, not independently
fetched (didn't attempt — Springer chapter pages are almost always
paywalled/403 to bots). Title, authors, and DOI are consistent across the
Springer listing and a ResearchGate mirror. Recommend a quick manual check
since I didn't verify this one by direct fetch.

---

## 4. NVIDIA CUDA C++ Programming Guide

**Cite key:** `nvidiacudaguide`

NVIDIA Corporation, *CUDA C++ Programming Guide*, online, continuously
updated.

- URL: https://docs.nvidia.com/cuda/cuda-c-programming-guide/

**Verification status:** Fetched directly and confirmed — this is the
live, official NVIDIA guide. Note this is a *living document* (NVIDIA
updates it per CUDA release), so it doesn't have a fixed "year" the way
a paper does; cited as an ongoing reference, which is standard practice
for this kind of primary-source technical citation in GPU-computing
papers.

---

## 5. APUNet (discrete-GPU PCIe/DMA overhead)

**Cite key:** `go2017apunet`

Y. Go, M. A. Jamshed, Y. Moon, C. Hwang, and K. Park, "APUNet:
Revitalizing GPU as Packet Processing Accelerator," in *Proc. 14th
USENIX Symposium on Networked Systems Design and Implementation (NSDI)*,
2017, pp. 83–96.

- USENIX abstract page: https://www.usenix.org/conference/nsdi17/technical-sessions/presentation/go
- PDF: https://www.usenix.org/system/files/conference/nsdi17/nsdi17-go.pdf
- dblp entry: https://dblp.org/rec/conf/nsdi/GoJMHP17.html

**Verification status:** USENIX abstract page returned 403 to automated
fetch (USENIX blocks bots on that path too), but the dblp entry
independently confirms authors/title/venue/year, and dblp is a reliable
bibliographic index (not a source that can be spoofed by a search engine
result). This looks solid.

---

## Second batch (added same day, to reach 20+ total references)

### 6. SSIM metric

**Cite key:** `wang2004ssim`

Z. Wang, A. C. Bovik, H. R. Sheikh, and E. P. Simoncelli, "Image Quality
Assessment: From Error Visibility to Structural Similarity," *IEEE
Transactions on Image Processing*, vol. 13, no. 4, pp. 600–612, Apr. 2004.

- Author's own page: https://ece.uwaterloo.ca/~z70wang/publications/ssim.html

**Verification status:** Not directly fetched, but this is an extremely
well-known, heavily-cited paper (the foundational SSIM paper) — full
citation details cross-confirmed via search. High confidence.

### 7. SRCNN (FSRCNN's precursor)

**Cite key:** `dong2014srcnn`

C. Dong, C. C. Loy, K. He, and X. Tang, "Learning a Deep Convolutional
Network for Image Super-Resolution," in *Proc. ECCV*, 2014, pp. 184–199.

- DOI: https://doi.org/10.1007/978-3-319-10593-2_13
- Springer page: https://link.springer.com/chapter/10.1007/978-3-319-10593-2_13

**Verification status:** Title/authors/DOI cross-confirmed via search
(Springer's own listing). Not independently fetched (paywalled).

### 8. Amdahl's Law (original paper)

**Cite key:** `amdahl1967`

G. M. Amdahl, "Validity of the Single Processor Approach to Achieving
Large Scale Computing Capabilities," in *Proc. AFIPS Spring Joint
Computer Conference*, 1967, pp. 483–485.

- DOI: https://doi.org/10.1145/1465482.1465560 (ACM Digital Library)

**Verification status:** High confidence — classic, extremely
well-documented paper, DOI cross-confirmed via ACM DL and dblp listings.

### 9. ThreadSanitizer

**Cite key:** `serebryany2009threadsanitizer`

K. Serebryany and T. Iskhodzhanov, "ThreadSanitizer: Data Race Detection
in Practice," in *Proc. WBIA*, 2009, pp. 62–71.

- DOI: https://doi.org/10.1145/1791194.1791203
- Google Research page: https://research.google/pubs/threadsanitizer-data-race-detection-in-practice/

**Verification status:** High confidence — DOI and Google Research's own
publication listing both confirm this.

### 10. Roofline model

**Cite key:** `williams2009roofline`

S. Williams, A. Waterman, and D. Patterson, "Roofline: An Insightful
Visual Performance Model for Multicore Architectures," *Communications
of the ACM*, vol. 52, no. 4, pp. 65–76, Apr. 2009.

- DOI: https://doi.org/10.1145/1498765.1498785

**Verification status:** High confidence — classic paper, DOI
cross-confirmed via ACM DL and OSTI.gov.

### 11. cuDNN

**Cite key:** `chetlur2014cudnn`

S. Chetlur et al., "cuDNN: Efficient Primitives for Deep Learning,"
arXiv:1410.0759, 2014.

- arXiv page: https://arxiv.org/abs/1410.0759

**Verification status:** High confidence — arXiv ID directly confirmed
via search (dblp cross-listing too).

### 12. Convolution arithmetic guide (transposed convolution)

**Cite key:** `dumoulin2016convolution`

V. Dumoulin and F. Visin, "A Guide to Convolution Arithmetic for Deep
Learning," arXiv:1603.07285, 2016.

- arXiv page: https://arxiv.org/pdf/1603.07285

**Verification status:** High confidence — well-known reference,
arXiv ID confirmed via search.

### 13. NVIDIA GB10 / Grace Blackwell official announcement

**Cite key:** `nvidiagb10_2025`

NVIDIA Corporation, "NVIDIA Puts Grace Blackwell on Every Desk and at
Every AI Developer's Fingertips," NVIDIA Newsroom, Jan. 2025.

- URL: https://nvidianews.nvidia.com/news/nvidia-puts-grace-blackwell-on-every-desk-and-at-every-ai-developers-fingertips

**Verification status:** Directly fetched and confirmed live. Publication
date Jan 6, 2025 confirmed. Specs (20 Arm cores, Blackwell GPU, NVLink-C2C)
match Table I in the paper exactly.

### 14. ARM DynamIQ

**Cite key:** `armdynamiq`

Arm Limited, "DynamIQ Technology." Online.

- URL: https://www.arm.com/technologies/dynamiq

**Verification status:** Directly fetched and confirmed live — Arm's own
official technology page.

### 15. NVIDIA Ada GPU Architecture whitepaper

**Cite key:** `nvidiaada2022`

NVIDIA Corporation, *NVIDIA Ada GPU Architecture*, Whitepaper V2.02, 2022.

- URL: https://images.nvidia.com/aem-dam/Solutions/geforce/ada/nvidia-ada-gpu-architecture.pdf

**Verification status:** Medium confidence. The URL is on NVIDIA's own
asset CDN (images.nvidia.com) and was returned directly by search, but
my automated fetch got back raw/corrupted PDF binary data it couldn't
parse into readable text — so I could not visually confirm the title
page myself. Recommend opening this one yourself to double check it's
the right document before the paper goes out.

### 16. NVIDIA Grace Hopper / NVLink-C2C

**Cite key:** `nvidiagracehopper2022`

NVIDIA Corporation, "NVIDIA Grace Hopper Superchip Architecture
In-Depth," NVIDIA Developer Technical Blog, Nov. 2022.

- URL: https://developer.nvidia.com/blog/nvidia-grace-hopper-superchip-architecture-in-depth/

**Verification status:** Directly fetched and confirmed live — this is
the *developer blog* version, not the gated whitepaper-download page
(`resources.nvidia.com`, which 302-redirected to NVIDIA's homepage for
me — likely a lead-capture form that doesn't work for a bot). The blog
version has the same technical content and is freely accessible, which
is why I cited it instead.

### 17. Unified physical memory (CPU-GPU)

**Cite key:** `wahlgren2025upm`

J. Wahlgren et al., "Dissecting CPU-GPU Unified Physical Memory on AMD
MI300A APUs," arXiv:2508.12743, 2025.

- arXiv page: https://arxiv.org/abs/2508.12743

**Verification status:** High confidence — arXiv ID and full author list
cross-confirmed via search (also indexed on ResearchGate/ADS). Note this
paper is about AMD MI300A APUs specifically, not NVIDIA — cited here only
for the general unified-vs-discrete-memory architectural point, not as
NVIDIA-specific evidence. Worth double-checking the surrounding sentence
in the paper doesn't imply otherwise.

### 18. Warp/thread-block sizing (SIMT)

**Cite key:** `lashgar2012warpresize`

A. Lashgar, A. Baniasadi, and A. Khonsari, "Dynamic Warp Resizing in
High-Performance SIMT," arXiv:1208.2374, 2012.

- arXiv page: https://arxiv.org/abs/1208.2374

**Verification status:** High confidence — arXiv ID and authors
cross-confirmed via search and ResearchGate.

---

## Summary

| Key | Confidence | Why |
|---|---|---|
| `bilbao2023pmcsched` | High | DOI resolves live via doi.org redirect |
| `go2017apunet` | High | Cross-confirmed via dblp |
| `nvidiacudaguide` | High | Directly fetched and read |
| `wang2004ssim` | High | Famous/well-documented paper |
| `amdahl1967` | High | DOI cross-confirmed, classic paper |
| `serebryany2009threadsanitizer` | High | DOI + Google Research listing |
| `williams2009roofline` | High | DOI cross-confirmed |
| `chetlur2014cudnn` | High | arXiv ID confirmed |
| `dumoulin2016convolution` | High | arXiv ID confirmed |
| `nvidiagb10_2025` | High | Directly fetched and read |
| `armdynamiq` | High | Directly fetched and read |
| `nvidiagracehopper2022` | High | Directly fetched and read |
| `wahlgren2025upm` | High | arXiv ID confirmed (note: AMD-specific paper, used for general point only) |
| `lashgar2012warpresize` | High | arXiv ID confirmed |
| `dong2014srcnn` | Medium | Search-confirmed only, paywalled |
| `eichenberger2012ompaffinity` | Medium | Search-confirmed only, not fetched |
| `intelhybrid2021` | Medium | 403 on both URLs, title/domain consistent across searches |
| `nvidiaada2022` | Medium | URL confirmed genuine, but fetch returned unparseable PDF binary |

**24 references total now** (6 original + 18 added across two passes).
The three "Medium" confidence ones are all cases where the *content*
couldn't be read by the automated fetcher (paywall or bot-blocking), not
cases where I found conflicting information — but you should still open
each yourself before final submission.

Two bibliography entries were already present and already unused before
I touched this file: `tomasulo1967` and `wang2020pipeit`. Not something I
added — flagging in case you want them cited somewhere or removed.
