import matplotlib.pyplot as plt
import matplotlib.patches as patches

# IEEE style typography
plt.rcParams['font.family'] = 'serif'
plt.rcParams['font.serif'] = ['Times New Roman', 'DejaVu Serif']
plt.rcParams['mathtext.fontset'] = 'stix'

# Set figure dimensions: 7.16 inches wide, 2.5 inches high
fig, ax = plt.subplots(figsize=(7.16, 2.5), dpi=300)
ax.set_xlim(0, 100)
ax.set_ylim(0, 36)
ax.axis('off')

# Color palette: Pure publication style (Navy, Slate, White)
c_bg = '#FFFFFF'
c_frame = '#0F172A'       # Slate 900
c_blue = '#1E3A8A'        # Deep Navy
c_box_blue = '#F1F5F9'    # Slate 100
c_box_active = '#EFF6FF'  # Cool blue 50
c_accent = '#2563EB'      # Blue 600
c_text = '#0F172A'
c_sub = '#475569'

# -------------------------------------------------------------------------
# 1. HOST (CPU) Container: x in [1, 14]
# -------------------------------------------------------------------------
box_host = patches.FancyBboxPatch((1, 3), 13, 29, boxstyle="round,pad=0.2,rounding_size=1.0",
                                  facecolor=c_box_blue, edgecolor=c_frame, linewidth=1.2)
ax.add_patch(box_host)
ax.text(7.5, 29.5, "HOST (CPU)", ha='center', va='center', weight='bold', fontsize=9, color=c_text)
ax.text(7.5, 26.5, "Layers 1–7", ha='center', va='center', weight='bold', fontsize=8.5, color=c_blue)
ax.text(7.5, 24.0, "(OpenMP Threads)", ha='center', va='center', fontsize=7.2, color=c_sub)

# Tensor icon for Host (3 stacked clean planes)
for i in [2, 1, 0]:
    ox, oy = 4.0 + i*1.1, 12.5 + i*1.8
    p = patches.Rectangle((ox, oy), 5.0, 6.2, facecolor=c_bg, edgecolor=c_frame, linewidth=0.9)
    ax.add_patch(p)

ax.text(7.5, 8.5, "56 Feature Maps", ha='center', va='center', weight='bold', fontsize=7.8, color=c_text)
ax.text(7.5, 5.5, "$176 \\times 144$ (FP64)", ha='center', va='center', fontsize=7.2, color=c_sub)

# Arrow Host -> GPU: x from 14.5 to 25.5 (generous 11-unit span)
ax.annotate('', xy=(25.5, 16.5), xytext=(14.5, 16.5),
            arrowprops=dict(facecolor=c_frame, edgecolor=c_frame, arrowstyle='->', lw=1.3))
ax.text(20.0, 19.5, "H2D Copy", ha='center', va='center', weight='bold', fontsize=7.2, color=c_text)
ax.text(20.0, 13.8, "(NVLink/PCIe)", ha='center', va='center', fontsize=6.5, color=c_sub)

# -------------------------------------------------------------------------
# 2. MAIN DEVICE (GPU) Container: x in [26, 99]
# -------------------------------------------------------------------------
box_gpu = patches.FancyBboxPatch((26, 2), 73, 31, boxstyle="round,pad=0.3,rounding_size=1.2",
                                 facecolor=c_bg, edgecolor=c_frame, linewidth=1.3, linestyle='--')
ax.add_patch(box_gpu)
ax.text(27.8, 31.0, "DEVICE (GPU): Layer 8 Transposed Deconvolution & Spatial Reduction",
        ha='left', va='center', weight='bold', fontsize=8.5, color=c_blue)

# -------------------------------------------------------------------------
# STAGE 1: Deconvolution Kernel: x in [27.5, 43.5] (width 16)
# -------------------------------------------------------------------------
box_s1 = patches.FancyBboxPatch((27.5, 4), 16, 24, boxstyle="round,pad=0.2,rounding_size=0.8",
                                facecolor=c_box_active, edgecolor=c_accent, linewidth=1.1)
ax.add_patch(box_s1)
ax.text(35.5, 25.5, "Step 1: Deconv", ha='center', va='center', weight='bold', fontsize=8.2, color=c_blue)
ax.text(35.5, 22.8, "deconv_kernel", ha='center', va='center', fontfamily='monospace', weight='bold', fontsize=7.6, color=c_text)

ax.text(35.5, 19.0, "Transposed Conv $9{\\times}9$\nStride = 2", ha='center', va='center', fontsize=7.2, color=c_text)

# Warp aligned highlight box
wb = patches.Rectangle((28.5, 11.2), 14.0, 5.2, facecolor=c_bg, edgecolor=c_accent, linewidth=0.8)
ax.add_patch(wb)
ax.text(35.5, 14.5, "Warp-Aligned Grid:", ha='center', va='center', fontsize=6.8, color=c_sub)
ax.text(35.5, 12.8, "$32{\\times}8$ Threads/Block", ha='center', va='center', weight='bold', fontsize=7.2, color=c_blue)

ax.text(35.5, 7.5, "Per-Channel Isolation:\nChannel $c \\in [0, 55]$", ha='center', va='center', fontsize=6.8, color=c_sub)

# Arrow Stage 1 -> Private Buffers (x from 44.0 to 48.5)
ax.annotate('', xy=(48.5, 16), xytext=(44.0, 16),
            arrowprops=dict(facecolor=c_frame, edgecolor=c_frame, arrowstyle='->', lw=1.3))

# -------------------------------------------------------------------------
# STAGE 2: Private Buffer Layout: x in [49, 68] (width 19)
# -------------------------------------------------------------------------
box_s2 = patches.FancyBboxPatch((49, 4), 19, 24, boxstyle="round,pad=0.2,rounding_size=0.8",
                                 facecolor=c_box_blue, edgecolor=c_frame, linewidth=1.1)
ax.add_patch(box_s2)
ax.text(58.5, 25.5, "Private Buffers (Global)", ha='center', va='center', weight='bold', fontsize=8.2, color=c_text)
ax.text(58.5, 22.8, "d_all_tmp (43.3 MiB)", ha='center', va='center', fontfamily='monospace', weight='bold', fontsize=7.5, color=c_text)

# 3 Distinct, widely spaced planes
planes_y = [16.2, 12.5, 8.8]
labels = ["Plane 55 ($352{\\times}288$)", ".   .   .", "Plane 0 ($352{\\times}288$)"]
for y_pos, lbl in zip(planes_y, labels):
    rect = patches.Rectangle((50.5, y_pos), 16.0, 2.8, facecolor=c_bg, edgecolor=c_frame, linewidth=0.8)
    ax.add_patch(rect)
    ax.text(58.5, y_pos + 1.4, lbl, ha='center', va='center', fontsize=6.5, color=c_text)

ax.text(58.5, 6.0, "Isolated Memory Slices\n[Zero Race Conditions]", ha='center', va='center',
        weight='bold', fontsize=6.8, color=c_text)

# Arrow Private Buffers -> Spatial Reduction (x from 68.5 to 73.0)
ax.annotate('', xy=(73.0, 16), xytext=(68.5, 16),
            arrowprops=dict(facecolor=c_frame, edgecolor=c_frame, arrowstyle='->', lw=1.3))

# -------------------------------------------------------------------------
# STAGE 3: Spatial Reduction: x in [73.5, 89.5] (width 16)
# -------------------------------------------------------------------------
box_s3 = patches.FancyBboxPatch((73.5, 4), 16, 24, boxstyle="round,pad=0.2,rounding_size=0.8",
                                facecolor=c_box_active, edgecolor=c_accent, linewidth=1.1)
ax.add_patch(box_s3)
ax.text(81.5, 25.5, "Step 2: Reduction", ha='center', va='center', weight='bold', fontsize=8.2, color=c_blue)
ax.text(81.5, 22.8, "spatial_reduction", ha='center', va='center', fontfamily='monospace', weight='bold', fontsize=7.2, color=c_text)

ax.text(81.5, 19.0, "Parallel Per Pixel\n(101,376 Threads)", ha='center', va='center', fontsize=7.0, color=c_text)

# Formula badge (spacious, zero collision)
fb = patches.Rectangle((74.5, 11.2), 14.0, 5.2, facecolor=c_bg, edgecolor=c_accent, linewidth=0.8)
ax.add_patch(fb)
ax.text(81.5, 13.8, r"$\sum_{c=0}^{55} \mathrm{plane}[c] + \mathrm{bias}_8$", ha='center', va='center', fontsize=7.4, color=c_blue)

ax.text(81.5, 7.5, "Deterministic Order\n[Bit-Exact Invariance]", ha='center', va='center', fontsize=6.8, color=c_sub)

# Arrow Spatial Reduction -> Output (x from 90.0 to 92.5)
ax.annotate('', xy=(92.5, 16), xytext=(90.0, 16),
            arrowprops=dict(facecolor=c_frame, edgecolor=c_frame, arrowstyle='->', lw=1.3))

# -------------------------------------------------------------------------
# STAGE 4: Final Output: x in [93, 98.2] (width 5.2)
# -------------------------------------------------------------------------
box_s4 = patches.FancyBboxPatch((93, 4), 5.2, 24, boxstyle="round,pad=0.2,rounding_size=0.8",
                                facecolor=c_box_blue, edgecolor=c_frame, linewidth=1.1)
ax.add_patch(box_s4)
ax.text(95.6, 25.5, "Output", ha='center', va='center', weight='bold', fontsize=8.0, color=c_text)

r_hr = patches.Rectangle((93.7, 13.0), 3.8, 7.8, facecolor=c_bg, edgecolor=c_frame, linewidth=0.9)
ax.add_patch(r_hr)
ax.text(95.6, 17.8, "HR Y", ha='center', va='center', weight='bold', fontsize=7.0, color=c_text)
ax.text(95.6, 15.2, "Frame", ha='center', va='center', fontsize=6.5, color=c_sub)

ax.text(95.6, 10.2, "$352{\\times}288$", ha='center', va='center', fontsize=6.5, color=c_text)
ax.text(95.6, 6.8, "Bit-Exact\n(SHA-256)", ha='center', va='center', weight='bold', fontsize=6.5, color=c_blue)

plt.tight_layout(pad=0.1)
plt.savefig('/Users/hamdaniilham/Thesis/Paper/newpaper/figures/architecture_pipeline.pdf', format='pdf', bbox_inches='tight')
print("Successfully generated clean architecture_pipeline.pdf")
