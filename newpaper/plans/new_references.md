# New references added to itis.tex (RTX 4090 cross-platform section)

Added 2026-08-07 to support the new Section VI ("Cross-Platform Validation on
Discrete-GPU Hardware"). Check each link yourself before trusting the
citation — status notes below are from automated fetch attempts, not a
guarantee.

---

## 1. Intel hybrid architecture / Thread Director — REMOVED from itis.tex (inaccessible, confirmed by user)

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

#judul lengkapnya: Flexible system software scheduling for asymmetric multicore systems with PMCSched: A case for Intel Alder Lake

## 2. Asymmetric multicore scheduling (Alder Lake)

**Cite key:** `bilbao2023pmcsched`

C. Bilbao, J. C. Saez, and M. Prieto-Matías, "Flexible system software
scheduling for asymmetric multicore systems with PMCSched: A case for
Intel Alder Lake," _Concurrency and Computation: Practice and Experience_,
vol. 35, no. 25, e7814, 2023.

- DOI: https://doi.org/10.1002/cpe.7814
- Wiley page: https://onlinelibrary.wiley.com/doi/10.1002/cpe.7814

**Verification status:** DOI resolves correctly (302 redirect from
doi.org to the Wiley page) — confirms the DOI is real and live. The Wiley
page itself is paywalled (403 to automated fetch), so I could not read
the abstract directly, but author names/title/venue/volume/issue were
cross-confirmed via independent search results. This looks solid.

---

#judul dan lainnya yang lengkap:
The Design of OpenMP Thread Affinity
Alexandre E. Eichenberger1, Christian Terboven2, Michael Wong3,
and Dieter an Mey2
1 IBM T.J. Watson Research Center, Yorktown Heights, New York, USA
alexe@us.ibm.com 2 Center for Computing and Communication,
JARA, RWTH Aachen University, Germany
{terboven,anmey}@rz.rwth-aachen.de 3 IBM Software Group, Toronto, Ontario, Canada
michaelw@ca.ibm.com

## 3. OpenMP thread affinity design

**Cite key:** `eichenberger2012ompaffinity`

A. E. Eichenberger, C. Terboven, M. Wong, and D. an Mey, "The Design of
OpenMP Thread Affinity," in _OpenMP in a Heterogeneous World (IWOMP 2012)_, Lecture Notes in Computer Science, vol. 7312, Springer, 2012,
pp. 15–28.

- DOI: https://doi.org/10.1007/978-3-642-30961-8_2
- Springer page: https://link.springer.com/chapter/10.1007/978-3-642-30961-8_2

**Verification status:** Found via search only, not independently
fetched (didn't attempt — Springer chapter pages are almost always
paywalled/403 to bots). Title, authors, and DOI are consistent across the
Springer listing and a ResearchGate mirror. Recommend a quick manual check
since I didn't verify this one by direct fetch.

---

#AMAN

## 4. NVIDIA CUDA C++ Programming Guide

**Cite key:** `nvidiacudaguide`

NVIDIA Corporation, _CUDA C++ Programming Guide_, online, continuously
updated.

- URL: https://docs.nvidia.com/cuda/cuda-c-programming-guide/

**Verification status:** Fetched directly and confirmed — this is the
live, official NVIDIA guide. Note this is a _living document_ (NVIDIA
updates it per CUDA release), so it doesn't have a fixed "year" the way
a paper does; cited as an ongoing reference, which is standard practice
for this kind of primary-source technical citation in GPU-computing
papers.

---

## 5. APUNet (discrete-GPU PCIe/DMA overhead)

**Cite key:** `go2017apunet`

Y. Go, M. A. Jamshed, Y. Moon, C. Hwang, and K. Park, "APUNet:
Revitalizing GPU as Packet Processing Accelerator," in _Proc. 14th
USENIX Symposium on Networked Systems Design and Implementation (NSDI)_,
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

#judul lengkapnya:
Image Quality Assessment: From Error Visibility to Structural Similarity

Zhou Wang1, Alan C. Bovik2, Hamid R. Sheikh2 and Eero P. Simoncelli1

1Laboratory for Computational Vision (LCV), New York University, New York, NY 10003

2Laboratory for Image and Video Engineering (LIVE), The University of Texas at Austin, Austin, TX 78712

### 6. SSIM metric

**Cite key:** `wang2004ssim`

Z. Wang, A. C. Bovik, H. R. Sheikh, and E. P. Simoncelli, "Image Quality
Assessment: From Error Visibility to Structural Similarity," _IEEE
Transactions on Image Processing_, vol. 13, no. 4, pp. 600–612, Apr. 2004.

- Author's own page: https://ece.uwaterloo.ca/~z70wang/publications/ssim.html

**Verification status:** Not directly fetched, but this is an extremely
well-known, heavily-cited paper (the foundational SSIM paper) — full
citation details cross-confirmed via search. High confidence.

# judul lengkapnya:

Learning a Deep Convolutional Network
for Image Super-Resolution
Chao Dong1, Chen Change Loy1, Kaiming He2, and Xiaoou Tang1
1 Department of Information Engineering,
The Chinese University of Hong Kong, China
2 Microsoft Research Asia, Beijing, China

### 7. SRCNN (FSRCNN's precursor)

**Cite key:** `dong2014srcnn`

C. Dong, C. C. Loy, K. He, and X. Tang, "Learning a Deep Convolutional
Network for Image Super-Resolution," in _Proc. ECCV_, 2014, pp. 184–199.

- DOI: https://doi.org/10.1007/978-3-319-10593-2_13
- Springer page: https://link.springer.com/chapter/10.1007/978-3-319-10593-2_13

**Verification status:** Title/authors/DOI cross-confirmed via search
(Springer's own listing). Not independently fetched (paywalled).

#aman

### 8. Amdahl's Law (original paper)

**Cite key:** `amdahl1967`

G. M. Amdahl, "Validity of the Single Processor Approach to Achieving
Large Scale Computing Capabilities," in _Proc. AFIPS Spring Joint
Computer Conference_, 1967, pp. 483–485.

- DOI: https://doi.org/10.1145/1465482.1465560 (ACM Digital Library)

**Verification status:** High confidence — classic, extremely
well-documented paper, DOI cross-confirmed via ACM DL and dblp listings.

# data lengkapnya:

ThreadSanitizer – data race detection in practiceKonstantin SerebryanyOOO Google7 Balchug st.Moscow, 115035, Russiakcc@google.comTimur IskhodzhanovMIPT9 Institutskii per.Dolgoprudny, 141700, Russiatimur.iskhodzhanov@phystech.edu

### 9. ThreadSanitizer

**Cite key:** `serebryany2009threadsanitizer`

K. Serebryany and T. Iskhodzhanov, "ThreadSanitizer: Data Race Detection
in Practice," in _Proc. WBIA_, 2009, pp. 62–71.

- DOI: https://doi.org/10.1145/1791194.1791203
- Google Research page: https://research.google/pubs/threadsanitizer-data-race-detection-in-practice/

**Verification status:** High confidence — DOI and Google Research's own
publication listing both confirm this.

# lengkapnya:

Doi:10.1145/1498765.1498785The Roofline model offers insight on howto improve the performance of softwareand hardware.BY SAmueL WiLLiAmS, AnDReW WAteRmAn, AnD DAViD PAtteRSon

### 10. Roofline model

**Cite key:** `williams2009roofline`

S. Williams, A. Waterman, and D. Patterson, "Roofline: An Insightful
Visual Performance Model for Multicore Architectures," _Communications
of the ACM_, vol. 52, no. 4, pp. 65–76, Apr. 2009.

- DOI: https://doi.org/10.1145/1498765.1498785

**Verification status:** High confidence — classic paper, DOI
cross-confirmed via ACM DL and OSTI.gov.

# lengkapnya:

cuDNN: Efficient Primitives for Deep Learning
Sharan Chetlur, Cliff Woolley, Philippe Vandermersch, Jonathan Cohen, John Tran, Bryan Catanzaro, Evan Shelhamer

### 11. cuDNN

**Cite key:** `chetlur2014cudnn`

S. Chetlur et al., "cuDNN: Efficient Primitives for Deep Learning,"
arXiv:1410.0759, 2014.

- arXiv page: https://arxiv.org/abs/1410.0759

**Verification status:** High confidence — arXiv ID directly confirmed
via search (dblp cross-listing too).

#Lengkapnya:
A guide to convolution arithmetic for deep
learning
Vincent Dumoulin
1
F and Francesco Visin
2
F
†
FMILA, Université de Montréal †AIRLab, Politecnico di Milano
January 12, 2018

### 12. Convolution arithmetic guide (transposed convolution)

**Cite key:** `dumoulin2016convolution`

V. Dumoulin and F. Visin, "A Guide to Convolution Arithmetic for Deep
Learning," arXiv:1603.07285, 2016.

- arXiv page: https://arxiv.org/pdf/1603.07285

**Verification status:** High confidence — well-known reference,
arXiv ID confirmed via search.

#aman

### 13. NVIDIA GB10 / Grace Blackwell official announcement

**Cite key:** `nvidiagb10_2025`

NVIDIA Corporation, "NVIDIA Puts Grace Blackwell on Every Desk and at
Every AI Developer's Fingertips," NVIDIA Newsroom, Jan. 2025.

- URL: https://nvidianews.nvidia.com/news/nvidia-puts-grace-blackwell-on-every-desk-and-at-every-ai-developers-fingertips

**Verification status:** Directly fetched and confirmed live. Publication
date Jan 6, 2025 confirmed. Specs (20 Arm cores, Blackwell GPU, NVLink-C2C)
match Table I in the paper exactly.

#aman

### 14. ARM DynamIQ

**Cite key:** `armdynamiq`

Arm Limited, "DynamIQ Technology." Online.

- URL: https://www.arm.com/technologies/dynamiq

**Verification status:** Directly fetched and confirmed live — Arm's own
official technology page.

#aman

### 15. NVIDIA Ada GPU Architecture whitepaper

**Cite key:** `nvidiaada2022`

NVIDIA Corporation, _NVIDIA Ada GPU Architecture_, Whitepaper V2.02, 2022.

- URL: https://images.nvidia.com/aem-dam/Solutions/geforce/ada/nvidia-ada-gpu-architecture.pdf

**Verification status:** Medium confidence. The URL is on NVIDIA's own
asset CDN (images.nvidia.com) and was returned directly by search, but
my automated fetch got back raw/corrupted PDF binary data it couldn't
parse into readable text — so I could not visually confirm the title
page myself. Recommend opening this one yourself to double check it's
the right document before the paper goes out.

#aman

### 16. NVIDIA Grace Hopper / NVLink-C2C

**Cite key:** `nvidiagracehopper2022`

NVIDIA Corporation, "NVIDIA Grace Hopper Superchip Architecture
In-Depth," NVIDIA Developer Technical Blog, Nov. 2022.

- URL: https://developer.nvidia.com/blog/nvidia-grace-hopper-superchip-architecture-in-depth/

**Verification status:** Directly fetched and confirmed live — this is
the _developer blog_ version, not the gated whitepaper-download page
(`resources.nvidia.com`, which 302-redirected to NVIDIA's homepage for
me — likely a lead-capture form that doesn't work for a bot). The blog
version has the same technical content and is freely accessible, which
is why I cited it instead.

Lengkapnya:
Dissecting CPU-GPU Unified Physical Memory on AMD MI300A APUs
Jacob Wahlgren, Gabin Schieffer, Ruimin Shi, Edgar A. León, Roger Pearce, Maya Gokhale, Ivy Peng
Discrete GPUs are a cornerstone of HPC and data center systems, requiring management of separate CPU and GPU memory spaces. Unified Virtual Memory (UVM) has been proposed to ease the burden of memory management; however, at a high cost in performance. The recent introduction of AMD's MI300A Accelerated Processing Units (APUs)--as deployed in the El Capitan supercomputer--enables HPC systems featuring integrated CPU and GPU with Unified Physical Memory (UPM) for the first time. This work presents the first comprehensive characterization of the UPM architecture on MI300A. We first analyze the UPM system properties, including memory latency, bandwidth, and coherence overhead. We then assess the efficiency of the system software in memory allocation, page fault handling, TLB management, and Infinity Cache utilization. We propose a set of porting strategies for transforming applications for the UPM architecture and evaluate six applications on the MI300A APU. Our results show that applications on UPM using the unified memory model can match or outperform those in the explicitly managed model--while reducing memory costs by up to 44%.
Comments: To be published in IISWC 2025
Subjects: Distributed, Parallel, and Cluster Computing (cs.DC); Performance (cs.PF)
Cite as: arXiv:2508.12743 [cs.DC]
(or arXiv:2508.12743v1 [cs.DC] for this version)

https://doi.org/10.48550/arXiv.2508.12743
Focus to learn more
Related DOI:
https://doi.org/10.1109/IISWC66894.2025.00038
Focus to learn more

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

Lengkapnya:
Dynamic Warp Resizing in High-Performance SIMT
Ahmad Lashgar, Amirali Baniasadi, Ahmad Khonsari
Modern GPUs synchronize threads grouped in a warp at every instruction. These results in improving SIMD efficiency and makes sharing fetch and decode resources possible. The number of threads included in each warp (or warp size) affects divergence, synchronization overhead and the efficiency of memory access coalescing. Small warps reduce the performance penalty associated with branch and memory divergence at the expense of a reduction in memory coalescing. Large warps enhance memory coalescing significantly but also increase branch and memory divergence. Dynamic workload behavior, including branch/memory divergence and coalescing, is an important factor in determining the warp size returning best performance. Optimal warp size can vary from one workload to another or from one program phase to the next. Based on this observation, we propose Dynamic Warp Resizing (DWR). DWR takes innovative microarchitectural steps to adjust warp size during runtime and according to program characteristics. DWR outperforms static warp size decisions, up to 1.7X to 2.28X, while imposing less than 1% area overhead. We investigate various alternative configurations and show that DWR performs better for narrower SIMD and larger caches.
Comments: 9 pages, 5 Figures, 3 Lists, 1 Table, The extended version of ICCD 2012 poster paper
Subjects: Hardware Architecture (cs.AR)
Cite as: arXiv:1208.2374 [cs.AR]
(or arXiv:1208.2374v2 [cs.AR] for this version)

https://doi.org/10.48550/arXiv.1208.2374
Focus to learn more

### 18. Warp/thread-block sizing (SIMT)

**Cite key:** `lashgar2012warpresize`

A. Lashgar, A. Baniasadi, and A. Khonsari, "Dynamic Warp Resizing in
High-Performance SIMT," arXiv:1208.2374, 2012.

- arXiv page: https://arxiv.org/abs/1208.2374

**Verification status:** High confidence — arXiv ID and authors
cross-confirmed via search and ResearchGate.

yang annisa jga 3 penulisnya:
Enhancing Computational Efficiency: Transitioning
from Serial to Parallel Programming for Low-to-
High Resolution Video Reconstruction Using
FSRCNN on AMP Architecture
Annisa
Department of Informatics
Hasanuddin University, Indonesia
annisa21d@student.unhas.ac.id
Adnan
Department of Informatics
Hasanuddin University, Indonesia
adnan@unhas.ac.id
Zahir Zainuddin
Department of Informatics
Hasanuddin University, Indonesia
zahir@unhas.ac.id
Abstr

---

## Summary

| Key                             | Confidence | Why                                                                        |
| ------------------------------- | ---------- | -------------------------------------------------------------------------- |
| `bilbao2023pmcsched`            | High       | DOI resolves live via doi.org redirect                                     |
| `go2017apunet`                  | High       | Cross-confirmed via dblp                                                   |
| `nvidiacudaguide`               | High       | Directly fetched and read                                                  |
| `wang2004ssim`                  | High       | Famous/well-documented paper                                               |
| `amdahl1967`                    | High       | DOI cross-confirmed, classic paper                                         |
| `serebryany2009threadsanitizer` | High       | DOI + Google Research listing                                              |
| `williams2009roofline`          | High       | DOI cross-confirmed                                                        |
| `chetlur2014cudnn`              | High       | arXiv ID confirmed                                                         |
| `dumoulin2016convolution`       | High       | arXiv ID confirmed                                                         |
| `nvidiagb10_2025`               | High       | Directly fetched and read                                                  |
| `armdynamiq`                    | High       | Directly fetched and read                                                  |
| `nvidiagracehopper2022`         | High       | Directly fetched and read                                                  |
| `wahlgren2025upm`               | High       | arXiv ID confirmed (note: AMD-specific paper, used for general point only) |
| `lashgar2012warpresize`         | High       | arXiv ID confirmed                                                         |
| `dong2014srcnn`                 | Medium     | Search-confirmed only, paywalled                                           |
| `eichenberger2012ompaffinity`   | Medium     | Search-confirmed only, not fetched                                         |
| `intelhybrid2021`               | Medium     | 403 on both URLs, title/domain consistent across searches                  |
| `nvidiaada2022`                 | Medium     | URL confirmed genuine, but fetch returned unparseable PDF binary           |

**24 references total now** (6 original + 18 added across two passes).
The three "Medium" confidence ones are all cases where the _content_
couldn't be read by the automated fetcher (paywall or bot-blocking), not
cases where I found conflicting information — but you should still open
each yourself before final submission.

Two bibliography entries were already present and already unused before
I touched this file: `tomasulo1967` and `wang2020pipeit`. Not something I
added — flagging in case you want them cited somewhere or removed.
