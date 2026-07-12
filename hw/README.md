# hw/ — FPGA Design

Vivado 2019.1 project sources for the multi-channel FSK receiver, targeting PYNQ-Z2
(Zynq XC7Z020-1CLG400C).

## Layout

- `rtl/` — VHDL sources (see `rtl/README.md` for the pipeline description). Includes the
  single-channel pipeline (`TOP.vhd`), the multi-channel layer (`multi_channel_top.vhd`,
  `channel_matcher.vhd`, `channel_selector.vhd`), and the self-test signal source
  (`fsk_packet_generator.vhd`).
- `build_multi_channel_design.tcl` — main, idempotent Block Design build script: instantiates
  the Zynq Processing System, AXI DMA, AXI-GPIO control registers, and the multi-channel design,
  and wires them together. Safe to re-run.
- `add_gpio_control.tcl`, `connect_fsk_generator.tcl`, `connect_gpio_to_top.tcl` — incremental
  Block Design steps invoked by `build_multi_channel_design.tcl`.
- `rebuild_bitstream.tcl` — batch-mode entry point: opens the project, applies the Block Design
  wiring, and runs synthesis → implementation → bitstream generation end to end.
- `legacy/` — superseded one-off Block Design patch scripts, kept for reference only (each is
  self-documented as superseded by `build_multi_channel_design.tcl`). Not part of the current
  build flow.

## Build

From the Vivado Tcl console, with the project open:

```tcl
source {hw/build_multi_channel_design.tcl}
```

Or fully headless:

```
vivado.bat -mode batch -source hw/rebuild_bitstream.tcl -log hw/rebuild.log -journal hw/rebuild.jou
```

This produces `design_1_wrapper.bit` (bitstream) and `design_1.hwh` (hardware handoff), both
required by PYNQ to load the overlay — see `sw/multi_channel/upload_to_pynq.py`.

## Verified results

Timing closure and resource utilization for the current design are summarized in the top-level
[`README.md`](../README.md#-verified-results) and documented in full in
[`Project_Book_FSK_Multichannel.pdf`](../Project_Book_FSK_Multichannel.pdf) (Ch. 7–8).
