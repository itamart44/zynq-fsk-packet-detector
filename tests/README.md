# tests/ — Simulation & Verification

- `TB/TB_FSKgenerator.vhd` — behavioral testbench for the full single-channel pipeline
  (`hw/rtl/TOP.vhd`). Drives a synthetic FSK tone (sweeping frequency) into the design and
  exercises the complete chain from sample input through the AXI-Stream output interface.
- `TB/fsk_pipeline_waveform.png` — captured simulation waveform showing the pipeline's
  behavior end to end.
- `samples.csv` — recorded/synthetic sample data (index, value) used for offline inspection via
  `sw/read_samples.py`.

These cover the single-channel pipeline; the multi-channel layer
(`multi_channel_top`/`channel_matcher`/`channel_selector`) was verified in simulation during
development and subsequently validated on real PYNQ-Z2 hardware (see the top-level README and
`Project_Book_FSK_Multichannel.pdf`, Ch. 7), but no standalone multi-channel testbench is
checked into this repo.
