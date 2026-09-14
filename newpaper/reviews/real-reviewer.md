Review
Originality Technical Quality Significance Presentation Quality Relevance to IEEE ITIS 2026 Reviewer Confidence Overall Recommendation
Good6 Very Good8 Good6 Very Good8 Very Good8 Familiar3 Weak Accept6
Comments to Authors
Strengths

1. Bit-exactness is verified with strict methods. The paper uses byte-level comparison and SHA-256 hash matching across two GPU architectures. This gives strong evidence for the determinism claim.
2. The paper reports its own limitations honestly. It states that the h2d_ms counter is unreliable and explains why. This kind of transparency is rare and adds credibility.
3. The unified-vs-discrete memory comparison is clear and useful. Unified memory gives faster device-to-host transfer. Discrete memory gives a faster reduction kernel due to L2 cache capacity. Both results are well supported by the data in Table III.
   Weaknesses
4. No competitive GPU baseline is tested. The paper does not compare against atomicAdd or cuDNN. Without this, the source of the speedup cannot be fully confirmed.
5. Key architectural claims are inferred, not measured. The L2 cache explanation and the coalescing explanation are both based on timing differences. Direct profiler counters, such as L2 hit-rate and load efficiency, are not collected.
6. The experimental scope is narrow. Only one video sequence and one upscale factor are tested. This limits how well the proposed design rule can generalize to other networks or resolutions.
   Good6 Good6 Good6 Very Good8 Very Good8 Very Familiar4 Accept8
   Comments to Authors
   The manuscript presents promising results and addresses a relevant problem in GPU-based inference optimization. However, several improvements could further enhance the technical rigor and impact of the study. Specifically, the authors are encouraged to include a more detailed GPU performance-counter analysis (e.g., occupancy, memory throughput, and cache hit rates) to better explain the observed performance gains; investigate FP32, FP16, and BF16 implementations to quantify the trade-offs between determinism, numerical accuracy, and execution performance; expand the related work section to cover recent GPU inference optimization frameworks and techniques; provide an architectural diagram illustrating memory layout, kernel execution, and reduction workflow; and incorporate appropriate statistical significance tests to support the main performance claims. Addressing these aspects would substantially strengthen the paper's methodological depth, reproducibility, and overall contribution.
   Very Good8 Very Good8 Very Good8 Good6 Excellent10 Very Familiar4 Accept8
   Comments to Authors
   1.The paper presents a relevant and technically strong approach for accelerating FSRCNN inference while preserving bit-exact determinism.
7. The cross-platform evaluation and kernel-level profiling strengthen the validity of the results.
8. Please consider adding comparisons with other GPU implementations (e.g., atomic-based kernels or cuDNN) to further justify performance advantages.
9. The evaluation is limited to one sequence and scale factor; additional workloads would improve generalizability.
10. Some performance explanations are based on inference from timing results; hardware counter analysis would strengthen the discussion.
11. Fix IEEE template formatting, including figure/table consistency, reference formatting, and minor layout issues.
12. Please proofread and paraphrase several dense technical sentences to improve readability and accessibility.
