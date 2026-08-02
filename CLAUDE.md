# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This repo contains a thesis/paper project with two distinct halves:

1. **The paper** (repo root): LaTeX manuscripts about **SyncPilot**, a runtime-cost-estimation (IC-RCE) scheduler for multithreaded pipelines on asymmetric (ARM big.LITTLE) multicore architectures, using FSRCNN video super-resolution as the case study.
2. **`sync-pilot/`**: the actual C implementation being written about — a *separate git repository* (own remote: `github.com/HPC-AI-ID/sync-pilot`), untracked from the paper repo's perspective. Treat it as an independent project nested inside this working directory; don't assume paper-repo git operations cover it.

Numbers, figures, and claims in the LaTeX files are meant to be backed by benchmark output from `sync-pilot/`. When editing results sections, cross-check against the actual `results/` and `logs/` data rather than inventing numbers.

## Paper manuscripts

Multiple `.tex` files target different venues/languages — they are largely parallel drafts, not includes of each other:

- `main.tex` — Indonesian thesis draft ("Framework Penjadwalan Dinamis Adaptif...").
- `main_en.tex` / `main_asus_en.tex` — English conference paper, IEEEtran class (`IEEEtran.cls` is vendored in the repo root). `main_asus_en.tex` is the variant updated with results from the ASUS test machine (see `fsrcnn_*_asus.png`); `main_en.tex` predates that hardware.
- `paper_springer.tex` — Springer-format variant of the same English paper.

When asked to update "the paper" without a specified target, ask which variant(s) — edits typically need to be mirrored across `main_en.tex`/`main_asus_en.tex`/`paper_springer.tex` since they share content but diverge in formatting/class.

Build a given manuscript with pdflatex, e.g.:
```bash
pdflatex -interaction=nonstopmode -halt-on-error main_asus_en.tex
```
Run it twice if citations/references/TOC need to resolve.

Supporting docs at repo root:
- `references.md` — the full bibliography of `main_asus_en.tex` with verified links (DOI/IEEE Xplore/arXiv), in citation order. Use this to check or add citations rather than re-deriving URLs from memory.
- `riset.md` (and `riset.md.backup`) — research notes/analysis log in Indonesian (compute-bound vs memory-bound profiling, IPC/scaling analysis) that back claims made in the paper.
- `results.txt`, `new_result.txt` — raw benchmark result dumps referenced by the results sections.
- `trash-caching-analyze.md` — working notes on cache-thrashing mitigation ideas for SyncPilot-20W; exploratory, not yet reflected in the paper.

## `sync-pilot/` — the SyncPilot framework

A generic C pipelining framework (worker pool + priority/work-stealing scheduler + reorder buffer) with FSRCNN as its flagship example. Full architecture writeup (bilingual EN/ID) lives in:
- `sync-pilot/README.md` — usage guide / public API tutorial (English).
- `sync-pilot/FRAMEWORK_EXPLANATION.md` — deep architecture walkthrough in Indonesian: core data structures (`PipelineTask`, `StageQueue` ring buffer, `FinalReorderBuffer`, `PipelineEngine`, `WorkerContext`), end-to-end execution flow, the IC-RCE calibration mechanism, and ARM big.LITTLE core-affinity detection.
- `sync-pilot/ALLOCATOR_TRASHING.md`, `sync-pilot/UPDATE.md`, `sync-pilot/FUTURE.md` — dated design notes (lock contention fixes, per-stage mutexes, roadmap toward asymmetry-aware scheduling).

### Core architecture

- `sync-pilot/framework/syncpilot.c` / `.h` — the engine itself. Worker threads pull tasks via non-blocking work-stealing across per-stage queues (mutex per `StageQueue`, no global lock), execute a stage's `StageProcessorFn`, then push to the next stage or into the reorder buffer if it's the final stage. A dedicated consumer thread drains the reorder buffer strictly in `task_id` order, guaranteeing ordered output despite out-of-order worker execution.
- **IC-RCE (Initial Calibration Runtime Cost Estimation)**: on the very first task (id 0), each stage's wall-clock cost is measured once and cached in `stage_cost_estimates[]`; this cost profile drives Big/LITTLE core assignment via `pthread_setaffinity_np` (Linux only — falls back to a naive first-half/second-half split if `/sys/devices/system/cpu/*/cpufreq/cpuinfo_max_freq` isn't readable). This calibration step is the paper's core contribution.
- Memory contract: developer owns freeing `task->data` inside the `ConsumerWriterFn`; the framework only frees the `PipelineTask*` wrapper itself.

### FSRCNN example (the paper's benchmark subject)

`sync-pilot/example/fsrcnn/` implements 8-layer FSRCNN super-resolution on top of the framework, with several variants used for comparison in the paper's results tables:
- `fsrcnn_baseline.c` — serial/OpenMP baseline (no SyncPilot).
- `fsrcnn_syncpilot.c` — SyncPilot pipeline, homogeneous workers.
- `fsrcnn_syncpilot_hybrid.c` — SyncPilot + inner-thread parallelism per stage.
- `fsrcnn_syncpilot_twopool.c` — explicit two-pool (big-core pool / little-core pool) variant.
- `fsrcnn_serial.c`, `fsrcnn_serial_little.c`, `fsrcnn_naive_openmp.c` — additional reference points.

Input is `suzie_qcif.yuv` (QCIF 176×144 YUV420p test video); layer weights/biases are the `weights_layerN.txt` / `biasess_layerN.txt` files alongside the source.

**`sync-pilot/example/fsrcnn/comparison.sh`** is the main benchmark driver: builds all binaries, generates a ground-truth output from the baseline, runs each scenario (BASE/A–F, defined near the top of the script) for `NUM_RUNS=8` iterations over `TOTAL_FRAMES=150`, computes PSNR against ground truth via `ffmpeg`, verifies byte-for-byte output consistency across scenarios, and plots results with `gnuplot plot_results.gp` into `fsrcnn_throughput.png` / `fsrcnn_time.png`.
```bash
cd sync-pilot/example/fsrcnn
bash comparison.sh              # build + full benchmark + PSNR + plots
bash comparison.sh --build-only # compile only, skip execution (no power-meter photos needed)
```
Note: the script's `[FOTO DAYA MULAI]`/`[FOTO DAYA SELESAI]` markers bracket sections where the operator must physically photograph a power meter — this is a manual measurement step, not something to automate around.

**`sync-pilot/implementation/Makefile`** is a separate, more instrumented profiling suite (gprof + `perf stat`, thread-count sweeps 1/2/4/8/10/20, IPC degradation analysis, CFS-vs-IC-RCE affinity A/B comparison). Key targets:
```bash
cd sync-pilot/implementation
make all              # build fsrcnn_thread{1,2,4,8,10,20} into ../results/
make quick_test        # fast run across worker counts, no profiling
make run_profiling      # full gprof + perf stat sweep
make gprof_10w / gprof_20w   # gprof flat + call-graph profile for one config
make ipc_analysis_20w   # ARM PMU cache/branch/migration breakdown
make cfs_comparison      # same binary, IC-RCE affinity on vs off (SYNCPILOT_DISABLE_AFFINITY=1)
make ipc_proof_20w BIG_CPUS=10-19 LITTLE_CPUS=0-9   # controlled big/LITTLE core-pinning experiments
make analyze            # sync-pilot/implementation/analyze_scaling.sh
make report             # sync-pilot/implementation/generate_full_analysis_report.sh
make clean
```
Compiler flags for this suite include `-pg` (gprof) and `-march=native -mtune=native`, so binaries built here are profiling instruments, not portable release builds — don't reuse them for the `comparison.sh` benchmark path or vice versa.

Manual compilation (no Makefile) follows the pattern:
```bash
gcc -O3 -o my_app main.c sync-pilot/framework/syncpilot.c -lpthread -Wall
```
Requires POSIX threads; `enable_affinity` (Big/LITTLE pinning) is Linux-only and is a no-op elsewhere.

### Result artifacts

Numeric/log evidence lives in `sync-pilot/example/fsrcnn/results/`, `sync-pilot/results/`, `sync-pilot/example/fsrcnn/logs/`, and `sync-pilot/implementation/RESULTS`. `.md` files here (`RESULT.md`, `ANALYSIS_8_WORKERS.md`, `ANALYSIS_CROSS_PLATFORM.md`, `BLIND_CFS.md`, `results/asusgx10.md`) are narrative writeups of specific experiment runs — check these before quoting a number in the paper, since they explain the conditions the number was captured under.
