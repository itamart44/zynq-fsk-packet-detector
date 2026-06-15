"""Generate simple block diagrams for the final project book (Hebrew)."""
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.font_manager import FontProperties

plt.rcParams['font.family'] = 'Arial'

OUT = r'C:\Users\User\zynq-fsk-packet-detector\docs\figures'


def box(ax, x, y, w, h, text, fc='#dbe9f7', fontsize=9):
    r = patches.FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02",
                                linewidth=1.2, edgecolor='#2c3e50', facecolor=fc)
    ax.add_patch(r)
    ax.text(x + w / 2, y + h / 2, text, ha='center', va='center', fontsize=fontsize, wrap=True)


def arrow(ax, x1, y1, x2, y2):
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                 arrowprops=dict(arrowstyle='->', lw=1.2, color='#2c3e50'))


# ---------------------------------------------------------------------------
# Figure 1: top-level system architecture (PS/PL, multi-channel, DMA)
# ---------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(9, 5.5))
ax.set_xlim(0, 10)
ax.set_ylim(0, 7)
ax.axis('off')

box(ax, 0.3, 4.8, 2.6, 1.4, 'Channel 0\nTOP\n(DSP pipeline)', fc='#cde4ff')
box(ax, 0.3, 2.6, 2.6, 1.4, 'Channel 1\nTOP\n(DSP pipeline)', fc='#cde4ff')
box(ax, 0.3, 0.4, 2.6, 1.4, 'fsk_packet_generator\n(self-test source)', fc='#ffe8c2')

box(ax, 3.4, 3.7, 2.6, 1.4, 'channel_matcher\n(match_detected)', fc='#d9f2d0')
box(ax, 3.4, 1.6, 2.6, 1.4, 'channel_selector\n(best_channel)', fc='#d9f2d0')

box(ax, 6.4, 2.7, 2.6, 1.6, 'Output MUX\n(multi_channel_top)\n64-bit tdata / AXI-Stream', fc='#f7d6e0')

box(ax, 6.4, 4.8, 2.6, 1.4, 'AXI DMA\n(PL -> PS)', fc='#e6d6f7')
box(ax, 6.4, 0.4, 2.6, 1.4, 'AXI GPIO\nthresh / freq / n_active', fc='#e6d6f7')

box(ax, 9.0, 5.0, 1.0, 1.0, 'PS\n(ARM)', fc='#fff2b3')

# arrows
arrow(ax, 2.9, 5.5, 3.4, 4.6)
arrow(ax, 2.9, 3.3, 3.4, 4.3)
arrow(ax, 2.9, 1.1, 3.4, 2.6)

arrow(ax, 6.0, 4.4, 6.4, 3.8)
arrow(ax, 6.0, 2.3, 6.4, 3.3)

arrow(ax, 7.7, 4.3, 7.7, 4.8)
arrow(ax, 7.7, 4.8, 9.0, 5.5)
arrow(ax, 9.0, 5.3, 7.7, 4.3)

arrow(ax, 7.7, 2.0, 7.7, 1.8)
ax.text(8.0, 1.5, 'min_energy, bin_f0/1,\nn_active', fontsize=7, ha='left')

ax.set_title('תרשים מערכת: ארכיטקטורת PS/PL רב-ערוצית', fontsize=11)
plt.tight_layout()
plt.savefig(f'{OUT}/fig1_system_architecture.png', dpi=160)
plt.close(fig)


# ---------------------------------------------------------------------------
# Figure 2: single-channel processing pipeline (TOP.vhd)
# ---------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(10, 3.2))
ax.set_xlim(0, 11)
ax.set_ylim(0, 2)
ax.axis('off')

stages = [
    'SampleInput',
    'Energy\nDetector',
    'sample_\nbuffer',
    'FFT\ncontroller\n+ xfft',
    'Bin\nselector',
    'power_\nCalculator',
    'FSK\nDecision',
    'Sync\nDetector',
    'Adders_\nExtractor',
    'Output_\nInterface',
]
w = 1.0
gap = 0.06
x = 0.05
for s in stages:
    box(ax, x, 0.5, w, 1.0, s, fc='#cde4ff', fontsize=7.5)
    if x > 0.05:
        arrow(ax, x - gap, 1.0, x, 1.0)
    x += w + gap

ax.set_title('תרשים צנרת עיבוד חד-ערוצית (TOP.vhd)', fontsize=11)
plt.tight_layout()
plt.savefig(f'{OUT}/fig2_pipeline.png', dpi=160)
plt.close(fig)


# ---------------------------------------------------------------------------
# Figure 3: 64-bit output word bit-field layout
# ---------------------------------------------------------------------------
fig, ax = plt.subplots(figsize=(10, 2.2))
ax.set_xlim(0, 64)
ax.set_ylim(0, 1)
ax.axis('off')

fields = [
    (63, 64, 'match\ndetected'),
    (62, 63, 'best\nvalid'),
    (59, 62, 'best\nchannel'),
    (56, 59, 'ch\nindex'),
    (36, 56, 'reserved (0)'),
    (32, 36, 'type\ntag'),
    (0, 32, 'payload (32 bit)'),
]
for hi, lo_excl, label in fields:
    lo = lo_excl
    width = hi - lo + 1 if False else None

for (hi, lo, label) in [(63,63,'match\ndetected'), (62,62,'best\nvalid'),
                         (61,59,'best\nchannel'), (58,56,'ch\nindex'),
                         (55,36,'reserved (0)'), (35,32,'type tag'),
                         (31,0,'payload (32 bit)')]:
    width = hi - lo + 1
    x0 = 64 - 1 - hi
    box(ax, x0, 0.15, width, 0.7, f'{label}\n[{hi}:{lo}]', fc='#dbe9f7', fontsize=7.5)

ax.set_title('תרשים: מבנה מילת הפלט (64 סיביות) של multi_channel_top', fontsize=11)
plt.tight_layout()
plt.savefig(f'{OUT}/fig3_output_word.png', dpi=160)
plt.close(fig)

print('done')
