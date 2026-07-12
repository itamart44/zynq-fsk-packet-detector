# sw/ — Python Software (PS side)

PYNQ/Python runtime that reads the FPGA's AXI-Stream output over AXI DMA and visualizes it in
Jupyter. The directory reflects the project's incremental development: single-channel bring-up
first, then the multi-channel runtime used for the results in the top-level README.

## `single_channel/`

The original single-channel scripts, kept for reference:

- `run_fpga.py` — loads the single-channel bitstream, reads one AXI DMA channel, decodes
  power/sync/address packets, and plots a live power-comparison graph.
- `simulation.py` — despite the name, this is not an offline simulator: it also loads the
  bitstream and drives real hardware over AXI DMA (near-identical to `run_fpga.py` from the same
  development stage).

## `multi_channel/`

The current runtime, used to produce the verified results in the top-level README:

- `run_fpga.py` — loads the multi-channel overlay, reads the combined 64-bit AXI-Stream output
  over AXI DMA, decodes `match_detected` / `best_channel` / `ch_index` / type-tag / payload from
  each word, and renders a live per-channel dashboard (rolling power history, current-window
  power bars, address log, status banner) at ~10 FPS. See the module docstring for the
  packet-format and rendering details.
- `upload_to_pynq.py` — pushes the bitstream, hardware handoff file, and `run_fpga.py` to the
  board's Jupyter notebook root over the Jupyter Contents API.
- `install_ipympl.py` — offline installer for the `ipympl` Matplotlib widget backend on the
  board. Kept for reference; the current `run_fpga.py` uses PNG-frame rendering instead, adopted
  after `ipympl` proved unreliable (stopped updating after a browser refresh) in this Jupyter
  setup.

## `read_samples.py`

Small standalone helper to load `tests/samples.csv` for offline inspection (not part of the
hardware runtime path).
