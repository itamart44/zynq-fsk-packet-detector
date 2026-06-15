"""
Multi-channel FSK signal detection — PYNQ-Z2 runtime
=====================================================
Packet format from multi_channel_top (64-bit words):
  [63]     match_detected  — two channels received the same address
  [62]     best_valid      — best_channel is meaningful
  [61:59]  best_channel    — channel index with largest |P0-P1| margin
  [58:56]  ch_index        — which channel this word came from
  [55:36]  (zero)
  [35:32]  type tag        — 1=power0  2=power1  3=sync  4=address
  [31:0]   payload

Output_Interface asserts tlast on the last beat of each packet (power_1,
sync, or adders), so each DMA transfer carries at most one packet
(2 words for power, 1 word for sync/adders). BUFFER_WORDS=4 leaves margin.

Per-transfer debug prints were removed (they flooded the Jupyter output and
could stall live-plot rendering); a periodic [STATS] line reports a running
tag histogram instead.

The FPGA streams power0/power1 packets continuously (one pair every FFT
window, ~256us), far faster than matplotlib can usefully redraw. Redraws are
therefore throttled by wall-clock time (REDRAW_INTERVAL) rather than by
transfer count, so the plots update at a steady, readable rate (default 10
FPS) regardless of how fast packets arrive.

Live redraw renders each frame to a PNG in memory and displays it with
IPython.display, replacing the previous output cell each time. This avoids
the `%matplotlib widget` (ipympl) backend entirely, which required a browser
refresh to resync and then stopped updating.

Run in a Jupyter cell on the PYNQ-Z2:
    %run run_fpga.py
Or import and call run(). Interrupt the kernel (Stop button) to end the run.
"""

import io
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
from matplotlib.patches import FancyBboxPatch
from IPython import display
import time
import threading
from collections import deque

from pynq import Overlay, allocate

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
BITSTREAM      = 'fsk_project/design_1_wrapper.bit'
N_CHANNELS     = 2
BUFFER_WORDS   = 4            # uint64 words per DMA transfer (max packet = 2 words)
HISTORY_LEN    = 60           # samples kept in the rolling power plot
ADDR_LOG_LEN   = 30           # address events kept in the log
POLL_INTERVAL  = 0.0          # seconds between transfers (0 = as fast as possible)
DMA_TIMEOUT    = 5.0          # seconds before declaring a transfer hung

TAG_POWER0 = 0x1
TAG_POWER1 = 0x2
TAG_SYNC   = 0x3
TAG_ADDR   = 0x4

CHANNEL_COLORS = ['#2196F3', '#FF9800', '#4CAF50', '#E91E63',
                  '#9C27B0', '#00BCD4', '#FF5722', '#607D8B']

# ---------------------------------------------------------------------------
# Packet parser
# ---------------------------------------------------------------------------

def parse_word(word):
    """
    Decode one 64-bit output word from multi_channel_top.
    Returns (match_det, best_valid, best_ch, ch_idx, tag, data).

    `data` is the raw unsigned 32-bit payload. Power values are sums of
    squared FFT bins (always >= 0); treating the payload as signed made
    large power values wrap negative and get clipped by set_ylim(bottom=0),
    making the power plots appear empty.
    """
    match_det = int((word >> 63) & 0x1)
    bst_valid = int((word >> 62) & 0x1)
    bst_ch    = int((word >> 59) & 0x7)
    ch_idx    = int((word >> 56) & 0x7)
    tag       = int((word >> 32) & 0xF)
    data      = int(word & 0xFFFFFFFF)
    return match_det, bst_valid, bst_ch, ch_idx, tag, data


# ---------------------------------------------------------------------------
# Live state
# ---------------------------------------------------------------------------

class ChannelState:
    def __init__(self, ch_id):
        self.ch_id       = ch_id
        self.power0_hist = deque([0] * HISTORY_LEN, maxlen=HISTORY_LEN)
        self.power1_hist = deque([0] * HISTORY_LEN, maxlen=HISTORY_LEN)
        self.power0_last = 0
        self.power1_last = 0
        self.sync_count  = 0
        self.addr_log    = deque(maxlen=ADDR_LOG_LEN)

    def update_power0(self, val):
        self.power0_last = val

    def update_power1(self, val):
        self.power1_last = val
        # Append a new history point when we receive power1 (end of a window)
        self.power0_hist.append(self.power0_last)
        self.power1_hist.append(val)

    def update_sync(self):
        self.sync_count += 1

    def update_addr(self, addr):
        self.addr_log.append((time.time(), addr))

    @property
    def margin(self):
        return abs(self.power0_last - self.power1_last)


# ---------------------------------------------------------------------------
# Plot setup
# ---------------------------------------------------------------------------

def build_figure(n_ch):
    fig = plt.figure(figsize=(14, 8))
    fig.patch.set_facecolor('#1a1a2e')

    gs = gridspec.GridSpec(
        3, n_ch,
        figure=fig,
        hspace=0.45, wspace=0.35,
        top=0.92, bottom=0.07, left=0.06, right=0.97
    )

    ax_power  = []   # row 0: rolling power history per channel
    ax_bar    = []   # row 1: current P0 vs P1 bar
    ax_text   = []   # row 2: address log per channel

    for i in range(n_ch):
        ax_p = fig.add_subplot(gs[0, i])
        ax_b = fig.add_subplot(gs[1, i])
        ax_t = fig.add_subplot(gs[2, i])

        for ax in (ax_p, ax_b, ax_t):
            ax.set_facecolor('#16213e')
            for spine in ax.spines.values():
                spine.set_edgecolor('#444')
            ax.tick_params(colors='#aaa', labelsize=8)

        color = CHANNEL_COLORS[i % len(CHANNEL_COLORS)]
        ax_p.set_title(f'Ch {i} — Power History', color=color, fontsize=9, pad=4)
        ax_p.set_ylabel('Power', color='#aaa', fontsize=7)
        ax_p.set_ylim(bottom=0)
        ax_p.set_xlim(0, HISTORY_LEN - 1)

        ax_b.set_title(f'Ch {i} — Current Window', color=color, fontsize=9, pad=4)
        ax_b.set_ylim(bottom=0)

        ax_t.set_title(f'Ch {i} — Addresses', color=color, fontsize=9, pad=4)
        ax_t.axis('off')

        ax_power.append(ax_p)
        ax_bar.append(ax_b)
        ax_text.append(ax_t)

    # Status banner
    ax_status = fig.add_axes([0.0, 0.95, 1.0, 0.05])
    ax_status.set_facecolor('#0f3460')
    ax_status.axis('off')
    status_txt = ax_status.text(
        0.5, 0.5, 'FSK Multi-Channel Monitor — initialising…',
        ha='center', va='center', color='white', fontsize=11,
        transform=ax_status.transAxes
    )

    plt.suptitle('')
    return fig, ax_power, ax_bar, ax_text, status_txt


def update_plots(states, ax_power, ax_bar, ax_text,
                 status_txt, match_count, best_ch, best_valid, total_words):

    x = np.arange(HISTORY_LEN)

    for i, st in enumerate(states):
        color  = CHANNEL_COLORS[i % len(CHANNEL_COLORS)]
        p0_arr = np.array(st.power0_hist)
        p1_arr = np.array(st.power1_hist)

        # --- Rolling history ---
        ax = ax_power[i]
        ax.cla()
        ax.set_facecolor('#16213e')
        ax.tick_params(colors='#aaa', labelsize=8)
        for spine in ax.spines.values():
            spine.set_edgecolor('#444')
        ax.plot(x, p0_arr, color='#4FC3F7', linewidth=1.2, label='P0 (100 kHz)')
        ax.plot(x, p1_arr, color='#FF7043', linewidth=1.2, label='P1 (120 kHz)')
        ax.set_xlim(0, HISTORY_LEN - 1)
        ax.set_ylim(bottom=0)
        ax.set_ylabel('Power', color='#aaa', fontsize=7)
        ax.legend(loc='upper left', fontsize=6, facecolor='#16213e',
                  labelcolor='white', framealpha=0.6)
        ax.set_title(f'Ch {i} — Power History', color=color, fontsize=9, pad=4)

        # --- Current-window bar ---
        ax2 = ax_bar[i]
        ax2.cla()
        ax2.set_facecolor('#16213e')
        ax2.tick_params(colors='#aaa', labelsize=8)
        for spine in ax2.spines.values():
            spine.set_edgecolor('#444')
        vals   = [st.power0_last, st.power1_last]
        labels = ['P0\n100 kHz', 'P1\n120 kHz']
        bars   = ax2.bar(labels, vals, color=['#4FC3F7', '#FF7043'], width=0.5)
        ax2.set_ylim(bottom=0)
        ax2.set_title(f'Ch {i} — Current Window', color=color, fontsize=9, pad=4)
        # Label bars with values
        for bar, val in zip(bars, vals):
            if val > 0:
                ax2.text(bar.get_x() + bar.get_width() / 2, bar.get_height(),
                         f'{val:.2e}', ha='center', va='bottom',
                         color='white', fontsize=7)
        # Margin annotation
        ax2.text(0.98, 0.97, f'margin={st.margin:.2e}',
                 transform=ax2.transAxes, ha='right', va='top',
                 color='#FFD54F', fontsize=7)

        # --- Address log ---
        ax3 = ax_text[i]
        ax3.cla()
        ax3.set_facecolor('#16213e')
        ax3.axis('off')
        ax3.set_title(f'Ch {i} — Addresses', color=color, fontsize=9, pad=4)

        lines = [f'Syncs detected: {st.sync_count}', '']
        recent = list(st.addr_log)[-10:]
        for ts, addr in recent:
            t_rel = time.time() - ts
            lines.append(f'  [{t_rel:5.1f}s ago]  addr=0x{addr:02X} ({addr})')
        if not recent:
            lines.append('  (none yet)')

        ax3.text(0.03, 0.97, '\n'.join(lines),
                 transform=ax3.transAxes, ha='left', va='top',
                 color='#B0BEC5', fontsize=7.5, family='monospace')

    # --- Status banner ---
    best_str = f'best_ch={best_ch}' if best_valid else 'best_ch=?'
    match_str = f'MATCHES={match_count}' if match_count > 0 else 'no match'
    status_txt.set_text(
        f'FSK Multi-Channel Monitor  |  words={total_words}  |  '
        f'{best_str}  |  {match_str}'
    )
    status_txt.set_color('#FFD54F' if match_count > 0 else 'white')


# ---------------------------------------------------------------------------
# DMA helpers
# ---------------------------------------------------------------------------

def dma_wait_timeout(channel, timeout):
    """Block until the DMA transfer completes or timeout expires.
    Returns True on completion, False on timeout."""
    done = threading.Event()
    def _waiter():
        try:
            channel.wait()
        finally:
            done.set()
    threading.Thread(target=_waiter, daemon=True).start()
    return done.wait(timeout)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def run(n_channels=N_CHANNELS, bitstream=BITSTREAM):
    print(f'Loading overlay: {bitstream}')
    ol  = Overlay(bitstream)
    dma = ol.axi_dma_0
    buf = allocate(shape=(BUFFER_WORDS,), dtype=np.uint64)
    print('Overlay loaded. Starting monitor — interrupt the kernel to stop.')

    states = [ChannelState(i) for i in range(n_channels)]

    match_count = 0
    best_ch     = 0
    best_valid  = False
    total_words = 0

    fig, ax_power, ax_bar, ax_text, status_txt = build_figure(n_channels)
    plt.close(fig)  # prevent the default backend from also displaying it

    REDRAW_INTERVAL = 0.1   # seconds between plot redraws (~10 FPS)
    STATS_EVERY     = 200   # print a tag-count summary every N transfers
    last_redraw     = 0.0

    # Running counts of each packet type seen, keyed by TAG_* constants.
    tag_counts = {TAG_POWER0: 0, TAG_POWER1: 0, TAG_SYNC: 0, TAG_ADDR: 0}

    try:
        transfer_count = 0
        while True:
            # ---- DMA transfer ----
            dma.recvchannel.start()
            dma.recvchannel.transfer(buf)
            if not dma_wait_timeout(dma.recvchannel, DMA_TIMEOUT):
                print(f'[DMA] transfer #{transfer_count + 1} timed out after {DMA_TIMEOUT}s — no data from FPGA')
                dma.recvchannel.stop()
                continue
            transfer_count += 1

            # ---- Parse words ----
            for word in buf:
                if word == 0:
                    continue
                total_words += 1

                match_det, bst_valid, bst_ch, ch_idx, tag, data = parse_word(int(word))
                tag_counts[tag] = tag_counts.get(tag, 0) + 1

                if bst_valid:
                    best_ch    = bst_ch
                    best_valid = True
                if match_det:
                    match_count += 1
                    print(f'[MATCH] match_detected=1  ch_idx={ch_idx}  tag={tag}  word=0x{int(word):016X}  total_matches={match_count}')

                # Sync/address packets are rare — print them immediately so
                # they're easy to spot.
                if tag in (TAG_SYNC, TAG_ADDR):
                    print(f'[PKT] tag={tag} ch_idx={ch_idx} data=0x{data:08X} word=0x{int(word):016X}')

                if ch_idx >= n_channels:
                    continue

                st = states[ch_idx]
                if tag == TAG_POWER0:
                    st.update_power0(data)
                elif tag == TAG_POWER1:
                    st.update_power1(data)
                elif tag == TAG_SYNC:
                    if data & 1:
                        st.update_sync()
                elif tag == TAG_ADDR:
                    st.update_addr(data & 0x7F)

            # ---- Periodic diagnostics ----
            if transfer_count % STATS_EVERY == 0:
                print(f'[STATS] transfers={transfer_count} words={total_words} '
                      f'tag_counts={tag_counts} matches={match_count}')

            # ---- Redraw (throttled to a steady frame rate) ----
            now = time.time()
            if now - last_redraw >= REDRAW_INTERVAL:
                last_redraw = now
                update_plots(states, ax_power, ax_bar, ax_text,
                             status_txt, match_count, best_ch, best_valid,
                             total_words)
                buf_png = io.BytesIO()
                fig.savefig(buf_png, format='png', facecolor=fig.get_facecolor())
                buf_png.seek(0)
                display.display(display.Image(data=buf_png.getvalue()))
                display.clear_output(wait=True)

            if POLL_INTERVAL > 0:
                time.sleep(POLL_INTERVAL)

    except KeyboardInterrupt:
        print('\nStopped by user.')
    finally:
        buf.freebuffer()
        print(f'Total words processed: {total_words}')
        for i, st in enumerate(states):
            print(f'  Ch {i}: syncs={st.sync_count}  '
                  f'addresses={[f"0x{a:02X}" for _, a in st.addr_log]}')
        if match_count:
            print(f'  Matches detected: {match_count}')


if __name__ == '__main__':
    run()
