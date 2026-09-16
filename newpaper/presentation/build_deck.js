// Deck for the ITIS 2026 talk on the GPU spatial-reduction / FSRCNN paper.
// Built with pptxgenjs, following academic-pptx-skill's content_guidelines.md
// and slide_patterns.md (communication-first design, action titles, one
// exhibit per slide). All numbers below are taken verbatim from itis.tex
// (Tables I-III, Sections IV-VII); nothing is invented. Two slides are
// explicitly marked PENDING where the Nsight Compute / FP16-BF16 experiments
// (collect_ncu_profile.sh, collect_fp16_comparison.sh) will supply real
// numbers once run on the GB10 and RTX 4090 machines.

const pptxgen = require("pptxgenjs");
const path = require("path");

const ASSETS = path.join(__dirname, "assets");

const COLORS = {
  bg: "FFFFFF",
  primary: "1F4E79",
  accent: "2E75B6",
  body: "2D2D2D",
  muted: "777777",
  rule: "CCCCCC",
  highlight: "FFF2CC",
  pending: "C0392B",
  pendingBg: "FDEDEC",
};

const FONTS = {
  face: "Arial",
  title: 26,
  sectionHeader: 22,
  body: 20,
  label: 16,
  cite: 13,
};

const M = 0.5; // margin

const pres = new pptxgen();
pres.defineLayout({ name: "LAYOUT_16x9", width: 10, height: 5.625 });
pres.layout = "LAYOUT_16x9";

function divider(slide, y) {
  slide.addShape(pres.shapes.RECTANGLE, {
    x: M, y, w: 9.0, h: 0.025, fill: { color: COLORS.rule },
  });
}

function actionTitle(slide, text, opts = {}) {
  slide.addText(text, {
    x: M, y: 0.2, w: 9.0, h: opts.h || 0.9,
    fontSize: opts.fontSize || FONTS.title, fontFace: FONTS.face,
    color: COLORS.primary, bold: true, valign: "top",
  });
  divider(slide, (opts.h || 0.9) + 0.15);
  return (opts.h || 0.9) + 0.15 + 0.15;
}

function citation(slide, text) {
  slide.addText(text, {
    x: M, y: 5.15, w: 9.0, h: 0.32,
    fontSize: FONTS.cite, fontFace: FONTS.face, color: COLORS.muted,
  });
}

function pendingTag(slide, x, y, w = 1.6) {
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x, y, w, h: 0.32,
    fill: { color: COLORS.pendingBg }, line: { color: COLORS.pending, pt: 1 },
    rectRadius: 0.05,
  });
  slide.addText("DATA PENDING", {
    x, y, w, h: 0.32, fontSize: 12, bold: true, fontFace: FONTS.face,
    color: COLORS.pending, align: "center", valign: "middle",
  });
}

// ---------------------------------------------------------------------------
// 1. Title
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  slide.background = { color: COLORS.primary };
  slide.addText(
    "Accelerating Super-Resolution CNN Inference via GPU Spatial Reduction",
    {
      x: 0.7, y: 1.1, w: 8.6, h: 1.6,
      fontSize: 30, fontFace: FONTS.face, color: "FFFFFF", bold: true,
      align: "left", valign: "top",
    }
  );
  slide.addText(
    "A Cross-Platform Study on Unified and Discrete Memory Architectures",
    {
      x: 0.7, y: 2.6, w: 8.6, h: 0.6,
      fontSize: 18, fontFace: FONTS.face, color: "CADCFC", italic: true,
    }
  );
  slide.addShape(pres.shapes.RECTANGLE, {
    x: 0.7, y: 3.35, w: 2.0, h: 0.04, fill: { color: COLORS.accent },
  });
  slide.addText("IEEE ITIS 2026", {
    x: 0.7, y: 3.5, w: 8.6, h: 0.4,
    fontSize: 16, fontFace: FONTS.face, color: "A0BBDD",
  });
  slide.addText("M. Hamdani Ilham Latjoro", {
    x: 0.7, y: 3.95, w: 8.6, h: 0.5,
    fontSize: 17, fontFace: FONTS.face, color: "FFFFFF", bold: true,
  });
}

// ---------------------------------------------------------------------------
// 2. Motivation
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(
    slide,
    "FSRCNN's last layer is both the compute bottleneck and a correctness hazard"
  );
  slide.addText(
    [
      { text: "Layer 8 does the upscaling: ", options: { bold: true, breakLine: false } },
      { text: "a 9×9 transposed convolution across 56 channels, accumulated into one output plane, for 2× upscaling.", options: { breakLine: true } },
      { text: "Disproportionate cost: ", options: { bold: true, breakLine: false } },
      { text: "Layers 1–7 stay in low-resolution space; all upscaling work concentrates in Layer 8.", options: { breakLine: true } },
      { text: "Parallelizing it is a dilemma: ", options: { bold: true, breakLine: false } },
      { text: "naive shared accumulation races; mutexes/atomics bring severe contention.", options: { breakLine: true } },
    ],
    {
      x: M, y: y0, w: 9.0, h: 3.2,
      fontSize: FONTS.body, fontFace: FONTS.face, color: COLORS.body,
      bullet: true, paraSpaceAfter: 14,
    }
  );
  citation(slide, "Dong, Loy & Tang (2016), FSRCNN, ECCV");
}

// ---------------------------------------------------------------------------
// 3. Complication (correctness)
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(
    slide,
    "Naive multi-threaded accumulation corrupts output non-reproducibly"
  );
  slide.addImage({
    path: path.join(ASSETS, "correctness-1.png"),
    x: M, y: y0, w: 9.0, h: 9.0 / 3.832,
  });
  slide.addText(
    "(b) V0 corrupted, 21.5 dB PSNR-Y / 0.767 SSIM — (c)/(d) V1 (CPU) and V2 (GPU) bit-identical to reference (a)",
    { x: M, y: y0 + 9.0 / 3.832 + 0.1, w: 9.0, h: 0.5, fontSize: FONTS.label, fontFace: FONTS.face, color: COLORS.body }
  );
  slide.addText(
    "Same 32-thread run, three repeats: 4.75M / 5.01M / 5.04M bytes corrupted each time — never the same output twice.",
    { x: M, y: y0 + 9.0 / 3.832 + 0.65, w: 9.0, h: 0.6, fontSize: FONTS.label, fontFace: FONTS.face, color: COLORS.body, bold: true }
  );
  citation(slide, "Fig. 2, frame 26, i9-14900K / RTX 4090");
}

// ---------------------------------------------------------------------------
// 4. Research question
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "Can GPU offload fix the race — and go faster — without losing bit-exactness?", { h: 1.0 });
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x: 1.2, y: y0 + 0.2, w: 7.6, h: 1.5,
    fill: { color: "EBF3FA" }, line: { color: COLORS.accent, pt: 1.5 }, rectRadius: 0.1,
  });
  slide.addText(
    "Offload Layer 8's deconvolution and reduction to CUDA, executing Layers 1–7 on the CPU, and verify the GPU result is byte-identical to a deterministic CPU reference on every configuration.",
    {
      x: 1.4, y: y0 + 0.35, w: 7.2, h: 1.2,
      fontSize: 19, fontFace: FONTS.face, color: COLORS.primary,
      align: "center", valign: "middle",
    }
  );
  slide.addText(
    [
      { text: "Tested on two architecturally distinct platforms: ", options: { bold: true, breakLine: false } },
      { text: "an NVIDIA GB10 (unified memory) and an RTX 4090 desktop (discrete memory).", options: {} },
    ],
    { x: M, y: y0 + 2.1, w: 9.0, h: 0.8, fontSize: FONTS.body, fontFace: FONTS.face, color: COLORS.body }
  );
}

// ---------------------------------------------------------------------------
// 5. Method: privatize-then-reduce
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "Privatize-then-reduce eliminates the race by writing to isolated per-channel buffers");
  slide.addText("Three variants compared", {
    x: M, y: y0, w: 9.0, h: 0.35, fontSize: FONTS.sectionHeader, fontFace: FONTS.face, color: COLORS.accent, bold: true,
  });
  slide.addText(
    [
      { text: "V0 (naive): ", options: { bold: true, breakLine: false } },
      { text: "threads accumulate directly into one shared buffer → races.", options: { breakLine: true } },
      { text: "V1 (CPU spatial reduction): ", options: { bold: true, breakLine: false } },
      { text: "private buffer, 56×352×288 doubles (43.3 MiB), each channel isolated; fixed-order reduction pass.", options: { breakLine: true } },
      { text: "V2 (GPU spatial reduction, proposed): ", options: { bold: true, breakLine: false } },
      { text: "same pattern, moved to CUDA — next slide.", options: { breakLine: true } },
    ],
    { x: M, y: y0 + 0.4, w: 9.0, h: 2.6, fontSize: FONTS.body, fontFace: FONTS.face, color: COLORS.body, bullet: true, paraSpaceAfter: 12 }
  );
}

// ---------------------------------------------------------------------------
// 6. Architecture diagram
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "We move privatize-then-reduce onto the GPU with two custom CUDA kernels", { h: 0.85 });
  slide.addImage({
    path: path.join(ASSETS, "architecture-1.png"),
    x: M, y: y0, w: 9.0, h: 9.0 / 2.743,
  });
  citation(slide, "Fig. 1: deconv_kernel writes isolated channel planes; spatial_reduction_kernel sums them in fixed order.");
}

// ---------------------------------------------------------------------------
// 7. Warp alignment (method detail)
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "A warp-aligned 32×8 thread block maximizes memory coalescing");
  slide.addText(
    [
      { text: "Custom kernels, not cuDNN or atomicAdd: ", options: { bold: true, breakLine: false } },
      { text: "atomicAdd's non-deterministic summation order across asynchronous warps breaks bit-exactness; cuDNN doesn't expose the per-channel buffers our verification needs.", options: { breakLine: true } },
      { text: "Warp granularity is 32 threads: ", options: { bold: true, breakLine: false } },
      { text: "a 16×16 block splits a warp across non-contiguous rows.", options: { breakLine: true } },
      { text: "32×8 aligns every warp to one contiguous row: ", options: { bold: true, breakLine: false } },
      { text: "all 32 threads issue into one memory transaction.", options: { breakLine: true } },
    ],
    { x: M, y: y0, w: 9.0, h: 3.0, fontSize: FONTS.body, fontFace: FONTS.face, color: COLORS.body, bullet: true, paraSpaceAfter: 12 }
  );
}

// ---------------------------------------------------------------------------
// 8. Hardware table
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "Two architecturally distinct platforms test whether the result generalizes");
  const rows = [
    [{ text: "Component", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "GB10 (ASUS GX10)", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "RTX 4090 Desktop", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } }],
    ["CPU", "20-core ARM DynamIQ big.LITTLE\n(10× X925 + 10× A725)", "Intel i9-14900K\n8 P-core + 16 E-core"],
    ["GPU", "NVIDIA Blackwell, 48 SMs", "NVIDIA Ada Lovelace, 128 SMs"],
    ["Memory", "128 GB LPDDR5x, unified", "64 GB DDR + 24 GB GDDR6X, discrete"],
    ["Interconnect", "NVLink-C2C", "PCIe"],
  ];
  slide.addTable(rows, {
    x: M, y: y0, w: 9.0, h: 3.4,
    fontSize: 15, fontFace: FONTS.face, color: COLORS.body,
    border: { type: "solid", color: COLORS.rule, pt: 0.5 },
    autoPage: false,
    valign: "middle",
  });
  citation(slide, "Table I");
}

// ---------------------------------------------------------------------------
// 9. Results: correctness
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "V0's race corrupts output non-reproducibly; V1/V2 are bit-exact by construction");
  slide.addText("What to take away", {
    x: M, y: y0, w: 9.0, h: 0.35, fontSize: FONTS.sectionHeader, fontFace: FONTS.face, color: COLORS.accent, bold: true,
  });
  slide.addText(
    [
      { text: "V0 degrades non-monotonically: ", options: { bold: true, breakLine: false } },
      { text: "13.8 dB (GB10, 4 threads) to 68.6 dB (RTX 4090, 4 threads) to 23.0 dB at 32 threads.", options: { breakLine: true } },
      { text: "68.6 dB is invisible — and still non-deterministic: ", options: { bold: true, breakLine: false } },
      { text: "a race a human reviewer would not notice by eye is exactly the case for determinism by construction.", options: { breakLine: true } },
      { text: "V1 and V2 verified byte-identical: ", options: { bold: true, breakLine: false } },
      { text: "cmp -l, diff_bytes = 0, across every grid configuration tested.", options: { breakLine: true } },
    ],
    { x: M, y: y0 + 0.4, w: 9.0, h: 2.8, fontSize: FONTS.body, fontFace: FONTS.face, color: COLORS.body, bullet: true, paraSpaceAfter: 12 }
  );
  citation(slide, "Section IV-A, Table II");
}

// ---------------------------------------------------------------------------
// 10. Results: speedup
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "GPU offload beats the fastest verified CPU baseline by 1.46× and 1.63×");
  slide.addChart(
    pres.charts.BAR,
    [
      { name: "CPU V1 (best verified)", labels: ["GB10", "RTX 4090"], values: [6921.83, 8844.17] },
      { name: "GPU V2 (best grid)", labels: ["GB10", "RTX 4090"], values: [4756.33, 5435.50] },
    ],
    {
      x: M, y: y0, w: 5.4, h: 3.3,
      barDir: "col", barGrouping: "clustered",
      chartColors: [COLORS.muted, COLORS.accent],
      chartArea: { fill: { color: COLORS.bg } },
      catAxisLabelColor: COLORS.muted, valAxisLabelColor: COLORS.muted,
      valGridLine: { color: "E2E8F0", size: 0.5 }, catGridLine: { style: "none" },
      showValue: true, dataLabelColor: "1E293B", dataLabelFontSize: 11,
      showLegend: true, legendPos: "b", legendFontSize: 11,
      valAxisTitle: "Wall time (ms, lower is better)", showValAxisTitle: true,
      valAxisTitleColor: COLORS.muted, valAxisTitleFontSize: 12,
    }
  );
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x: 6.3, y: y0 + 0.1, w: 3.2, h: 1.5, fill: { color: COLORS.highlight }, line: { color: "E6C800", pt: 1 }, rectRadius: 0.08,
  });
  slide.addText("1.46× on GB10\n(31.5 FPS)\n\n1.63× on RTX 4090\n(27.6 FPS)", {
    x: 6.3, y: y0 + 0.1, w: 3.2, h: 1.5, fontSize: 16, bold: true, fontFace: FONTS.face, color: "7A5200", align: "center", valign: "middle",
  });
  citation(slide, "Table II, best-grid configuration (32×8_256)");
}

// ---------------------------------------------------------------------------
// 11. Results: warp alignment
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "Warp alignment cuts kernel time 23.4% and 17.4% on both GPUs");
  slide.addImage({
    path: path.join(ASSETS, "warp-1.png"),
    x: M, y: y0, w: 5.3, h: 5.3 / 1.429,
  });
  slide.addText("What to take away", {
    x: 6.0, y: y0, w: 3.5, h: 0.35, fontSize: FONTS.sectionHeader - 2, fontFace: FONTS.face, color: COLORS.accent, bold: true,
  });
  slide.addText(
    [
      { text: "GB10: 696.5 → 533.2 ms (−23.4%)", options: { breakLine: true } },
      { text: "RTX 4090: 437.1 → 360.9 ms (−17.4%)", options: { breakLine: true } },
      { text: "Gain isolates entirely to deconv_kernel; the reduction kernel is unchanged.", options: { breakLine: true } },
    ],
    { x: 6.0, y: y0 + 0.4, w: 3.5, h: 2.6, fontSize: 14, fontFace: FONTS.face, color: COLORS.body, bullet: true, paraSpaceAfter: 10 }
  );
  citation(slide, "Fig. 3, Section V-A / VI-C, Welch's t-test p < 10⁻⁴");
}

// ---------------------------------------------------------------------------
// 12. Results: cost of determinism
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "Determinism costs 4.6% of GPU time on GB10 but only 0.6% on RTX 4090");
  slide.addChart(
    pres.charts.BAR,
    [{ name: "Reduction pass, % of GPU Layer-8 time", labels: ["GB10", "RTX 4090"], values: [4.6, 0.6] }],
    {
      x: M, y: y0, w: 4.6, h: 3.2,
      barDir: "col", chartColors: [COLORS.accent],
      chartArea: { fill: { color: COLORS.bg } },
      catAxisLabelColor: COLORS.muted, valAxisLabelColor: COLORS.muted,
      valGridLine: { color: "E2E8F0", size: 0.5 }, catGridLine: { style: "none" },
      showValue: true, dataLabelColor: "1E293B", showLegend: false,
      valAxisTitle: "%", showValAxisTitle: true, valAxisTitleColor: COLORS.muted, valAxisTitleFontSize: 12,
    }
  );
  slide.addText("Why: an L2-cache boundary", {
    x: 5.9, y: y0, w: 3.6, h: 0.35, fontSize: FONTS.sectionHeader - 2, fontFace: FONTS.face, color: COLORS.accent, bold: true,
  });
  slide.addText(
    [
      { text: "RTX 4090's 72 MB L2 holds the 43.3 MiB private buffer → reduction served from cache.", options: { breakLine: true } },
      { text: "GB10 streams the buffer from unified DRAM at 95% of peak bandwidth → 10× costlier.", options: { breakLine: true } },
      { text: "This L2 story is currently inferred from bandwidth arithmetic, not measured directly (see Open Questions).", options: { breakLine: true, italic: true } },
    ],
    { x: 5.9, y: y0 + 0.4, w: 3.6, h: 2.8, fontSize: 13, fontFace: FONTS.face, color: COLORS.body, bullet: true, paraSpaceAfter: 10 }
  );
  citation(slide, "Section VI-D, Table III");
}

// ---------------------------------------------------------------------------
// 13. Results: cross-platform bit-exactness
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "GPU output is bit-identical across two host ISAs and two GPU generations");
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x: 1.0, y: y0 + 0.2, w: 8.0, h: 1.7,
    fill: { color: "EBF3FA" }, line: { color: COLORS.accent, pt: 1.5 }, rectRadius: 0.1,
  });
  slide.addText(
    "cmp -l: 0 differing bytes.\nSHA-256 digests match bit-for-bit across the ARM host / Blackwell GPU\nand x86 host / Ada Lovelace GPU runs.",
    { x: 1.2, y: y0 + 0.35, w: 7.6, h: 1.4, fontSize: 18, fontFace: FONTS.face, color: COLORS.primary, align: "center", valign: "middle" }
  );
  slide.addText(
    "This is the strongest determinism test in the paper: different host instruction set, different GPU microarchitecture, same output.",
    { x: M, y: y0 + 2.2, w: 9.0, h: 0.9, fontSize: FONTS.body, fontFace: FONTS.face, color: COLORS.body }
  );
  citation(slide, "Section VI-B");
}

// ---------------------------------------------------------------------------
// 14. Discussion: memory architecture picks the winner per stage
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "Unified memory transfers 4.74× faster; discrete GPUs reduce 10× faster", { h: 1.0 });
  const rows = [
    [{ text: "Stage", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "GB10 (unified)", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "RTX 4090 (discrete)", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "Winner", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } }],
    ["Device-to-host transfer", "3.46 ms", "16.42 ms", "GB10, 4.74×"],
    ["Spatial reduction kernel", "26.32 ms", "2.62 ms", "RTX 4090, 10.0×"],
  ];
  slide.addTable(rows, {
    x: M, y: y0 + 0.1, w: 9.0, h: 1.6,
    fontSize: 15, fontFace: FONTS.face, color: COLORS.body,
    border: { type: "solid", color: COLORS.rule, pt: 0.5 }, valign: "middle",
  });
  slide.addText(
    "No single architecture wins every stage: which memory model helps depends on whether the stage is transfer-bound or bandwidth-bound-and-cacheable.",
    { x: M, y: y0 + 2.0, w: 9.0, h: 0.8, fontSize: FONTS.body, fontFace: FONTS.face, color: COLORS.body }
  );
  citation(slide, "Section VI-D, Table III");
}

// ---------------------------------------------------------------------------
// 15. Open questions (Limitations) -- explicit PENDING slide
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  const y0 = actionTitle(slide, "Three open questions the paper names as future work", { h: 0.85 });

  const items = [
    ["No competitive GPU baseline (atomicAdd, cuDNN)", "Reasoned in the paper: both break bit-exactness or hide the buffers we verify — not run.", null],
    ["L2 residency model is inferred, not measured", "Nsight Compute profiling (L2 hit rate, throughput, occupancy) on both GPUs.", "PENDING"],
    ["FP32 / FP16 / BF16 trade-off is unmeasured", "Reduced-precision Layer 8 variant built; throughput vs. PSNR-Y/SSIM trade-off to be measured.", "PENDING"],
  ];

  let yy = y0;
  items.forEach(([head, body, tag]) => {
    slide.addText(head, {
      x: M, y: yy, w: tag ? 7.1 : 9.0, h: 0.4,
      fontSize: FONTS.body, fontFace: FONTS.face, color: COLORS.primary, bold: true,
    });
    if (tag) pendingTag(slide, 8.0, yy + 0.02);
    slide.addText(body, {
      x: M, y: yy + 0.4, w: 9.0, h: 0.6,
      fontSize: 15, fontFace: FONTS.face, color: COLORS.body,
    });
    yy += 1.15;
  });

  citation(slide, "Section VII — collect_ncu_profile.sh / collect_fp16_comparison.sh will supply the two pending numbers");
}

// ---------------------------------------------------------------------------
// 16. Conclusions
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  slide.background = { color: COLORS.primary };
  slide.addText("Conclusions", {
    x: M, y: 0.25, w: 9.0, h: 0.45, fontSize: 20, fontFace: FONTS.face, color: "A0BBDD",
  });
  slide.addShape(pres.shapes.RECTANGLE, { x: M, y: 0.7, w: 9.0, h: 0.04, fill: { color: COLORS.accent } });
  slide.addText(
    [
      { text: "1. GPU spatial reduction is deterministic by construction: ", options: { bold: true, breakLine: false } },
      { text: "bit-exact vs. a verified CPU reference on every configuration, and bit-identical across two host ISAs and two GPU generations.", options: { breakLine: true, breakLine: true } },
      { text: "2. It is also faster: ", options: { bold: true, breakLine: false } },
      { text: "1.46× (GB10, 31.5 FPS) and 1.63× (RTX 4090, 27.6 FPS) over the fastest verified CPU baseline.", options: { breakLine: true, breakLine: true } },
      { text: "3. Warp-aligned 32×8 blocks cut kernel time 23.4%/17.4%; ", options: { bold: true, breakLine: false } },
      { text: "memory architecture picks the winner per stage — unified wins transfer, discrete wins the cacheable reduction.", options: { breakLine: true } },
    ],
    { x: M, y: 0.85, w: 9.0, h: 3.6, fontSize: FONTS.body, fontFace: FONTS.face, color: "FFFFFF", paraSpaceAfter: 16 }
  );
  slide.addText("M. Hamdani Ilham Latjoro  |  IEEE ITIS 2026", {
    x: M, y: 4.9, w: 8.0, h: 0.4, fontSize: 14, fontFace: FONTS.face, color: "A0BBDD",
  });
}

// ---------------------------------------------------------------------------
// 17. References
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  slide.addText("References", { x: M, y: 0.2, w: 9.0, h: 0.5, fontSize: 24, fontFace: FONTS.face, color: COLORS.primary, bold: true });
  divider(slide, 0.72);
  const refs = [
    "Dong, C., Loy, C.C., Tang, X. (2016). Accelerating the Super-Resolution CNN. ECCV.",
    "Annisa, A., Adnan, A., Zainuddin, Z. (2025). Enhancing Computational Efficiency... FSRCNN on AMP Architecture. IEEE AIMS.",
    "Wang, S. et al. (2020). High-Throughput CNN Inference on Embedded ARM big.LITTLE. IEEE TCAD.",
    "Chetlur, S. et al. (2014). cuDNN: Efficient Primitives for Deep Learning. arXiv:1410.0759.",
    "Chen, T. et al. (2018). TVM: An Automated End-to-End Optimizing Compiler for Deep Learning. USENIX OSDI.",
    "NVIDIA Corp. CUDA C++ Programming Guide; Ada GPU Architecture Whitepaper; TensorRT Architecture Overview.",
  ];
  slide.addText(
    refs.flatMap((r, i) => [{ text: r, options: { breakLine: true } }, ...(i < refs.length - 1 ? [{ text: "", options: { breakLine: true } }] : [])]),
    { x: M, y: 0.85, w: 9.0, h: 4.4, fontSize: 14, fontFace: FONTS.face, color: COLORS.body, paraSpaceAfter: 6 }
  );
}

// ---------------------------------------------------------------------------
// 18. Appendix A: Why not atomicAdd/cuDNN
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  slide.addText("Appendix A — Anticipated Question", { x: M, y: 0.15, w: 9.0, h: 0.4, fontSize: 14, fontFace: FONTS.face, color: COLORS.muted, italic: true });
  slide.addText("Why not compare against atomicAdd or cuDNN?", {
    x: M, y: 0.6, w: 9.0, h: 0.75, fontSize: FONTS.title - 2, fontFace: FONTS.face, color: COLORS.primary, bold: true,
  });
  slide.addText(
    [
      { text: "atomicAdd: ", options: { bold: true, breakLine: false } },
      { text: "floating-point addition is non-associative; asynchronous warps race to accumulate in different orders, so results vary run to run — the opposite of what this paper needs.", options: { breakLine: true } },
      { text: "cuDNN: ", options: { bold: true, breakLine: false } },
      { text: "optimizes for batched matmul; does not expose the isolated per-channel buffers our zero-race verification contract depends on.", options: { breakLine: true } },
      { text: "Future work: ", options: { bold: true, breakLine: false } },
      { text: "a throughput-only (not correctness) comparison against both remains useful to price determinism against an unconstrained baseline.", options: { breakLine: true } },
    ],
    { x: M, y: 1.5, w: 9.0, h: 3.0, fontSize: FONTS.body - 1, fontFace: FONTS.face, color: COLORS.body, bullet: true, paraSpaceAfter: 12 }
  );
}

// ---------------------------------------------------------------------------
// 19. Appendix B: Nsight Compute -- placeholder table
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  slide.addText("Appendix B — In Progress", { x: M, y: 0.15, w: 9.0, h: 0.4, fontSize: 14, fontFace: FONTS.face, color: COLORS.muted, italic: true });
  slide.addText("Nsight Compute counters for deconv_kernel / spatial_reduction_kernel", {
    x: M, y: 0.6, w: 9.0, h: 0.75, fontSize: FONTS.title - 4, fontFace: FONTS.face, color: COLORS.primary, bold: true,
  });
  pendingTag(slide, M, 1.35);
  const rows = [
    [{ text: "Metric", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "GB10", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "RTX 4090", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } }],
    ["L2 hit rate (lts__t_sector_hit_rate.pct)", "TBD", "TBD"],
    ["L2 throughput (% of peak)", "TBD", "TBD"],
    ["DRAM throughput (% of peak)", "TBD", "TBD"],
    ["Achieved occupancy (sm__warps_active)", "TBD", "TBD"],
  ];
  slide.addTable(rows, {
    x: M, y: 1.9, w: 9.0, h: 2.4, fontSize: 15, fontFace: FONTS.face, color: COLORS.muted,
    border: { type: "solid", color: COLORS.rule, pt: 0.5 }, valign: "middle",
  });
  citation(slide, "Run: newpaper/plans/collect_ncu_profile.sh on both machines, then fill this table.");
}

// ---------------------------------------------------------------------------
// 20. Appendix C: FP16/BF16 -- placeholder table
// ---------------------------------------------------------------------------
{
  const slide = pres.addSlide();
  slide.addText("Appendix C — In Progress", { x: M, y: 0.15, w: 9.0, h: 0.4, fontSize: 14, fontFace: FONTS.face, color: COLORS.muted, italic: true });
  slide.addText("What does bit-exact determinism cost against FP16/BF16?", {
    x: M, y: 0.6, w: 9.0, h: 0.75, fontSize: FONTS.title - 4, fontFace: FONTS.face, color: COLORS.primary, bold: true,
  });
  pendingTag(slide, M, 1.35);
  const rows = [
    [{ text: "Variant", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "GPU L8 time", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "diff_bytes", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } },
     { text: "PSNR-Y / SSIM", options: { bold: true, color: "FFFFFF", fill: { color: COLORS.primary } } }],
    ["FP64 (paper's baseline)", "533.19 ms (GB10)", "0 (bit-exact)", "∞ / 1.000"],
    ["FP16", "TBD", "TBD", "TBD"],
    ["BF16", "TBD", "TBD", "TBD"],
  ];
  slide.addTable(rows, {
    x: M, y: 1.9, w: 9.0, h: 2.0, fontSize: 15, fontFace: FONTS.face, color: COLORS.muted,
    border: { type: "solid", color: COLORS.rule, pt: 0.5 }, valign: "middle",
  });
  citation(slide, "Run: newpaper/plans/collect_fp16_comparison.sh on both machines, then fill this table.");
}

const OUT = path.join(__dirname, "itis_presentation.pptx");
pres.writeFile({ fileName: OUT }).then(() => {
  console.log("Wrote", OUT);
});
