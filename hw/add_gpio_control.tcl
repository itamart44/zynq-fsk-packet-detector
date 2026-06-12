# add_gpio_control.tcl
#
# SUPERSEDED by hw/build_multi_channel_design.tcl — kept for reference only.
#
# Adds three AXI GPIO peripheral instances to design_1 so that Python on the
# PYNQ-Z2 can write control parameters to the FPGA at runtime:
#
#   axi_gpio_ctrl   (M01) — n_active_channels [3:0]
#                           bits [2:0] = number of channels the output MUX cycles
#                           bit  [3]   = reserved
#                           Default 0x2 → 2 channels (matches current N_channel=2)
#
#   axi_gpio_thresh (M02) — energy threshold [31:0]
#                           Replaces Energy_Detector generic MIN_ENERGY (40-bit).
#                           VHDL should zero-extend to unsigned(39 downto 0).
#                           Default 0x3B9ACA00 = 1_000_000_000 (current hardcoded value)
#
#   axi_gpio_freq   (M03) — FFT bin indices, dual-channel GPIO
#                           GPIO  [7:0] = bin_f0 (P0, 100 kHz)
#                           GPIO2 [7:0] = bin_f1 (P1, 120 kHz)
#                           Replaces Bin_selector constants BIN_F1/BIN_F2.
#                           Defaults: bin_f0=25, bin_f1=30
#                           (F*N_FFT/Fs = 100000*256/1000000 = 25,
#                                         120000*256/1000000 = 30)
#
# This script ONLY modifies the block design (AXI bus wiring).
# The gpio_io_o / gpio2_io_o output pins are left unconnected here.
# After updating the RTL to add control ports, source:
#   hw/connect_gpio_to_top.tcl
# to wire those outputs to multi_channel_top_0.
#
# Run from the Vivado TCL console while the project is open:
#   source {C:/Users/User/zynq-fsk-packet-detector/hw/add_gpio_control.tcl}
#
# RTL changes required (see connect_gpio_to_top.tcl for BD wiring):
#
#   Energy_Detector.vhd:
#     Change generic MIN_ENERGY to a port:
#       min_energy : in unsigned(39 downto 0)
#     Drive it from the GPIO value zero-extended:
#       min_energy <= resize(unsigned(min_energy_in), 40)
#
#   Bin_selector.vhd:
#     Change constants BIN_F1/BIN_F2 to ports:
#       bin_f0 : in integer range 0 to windows-1
#       bin_f1 : in integer range 0 to windows-1
#     Remove: constant BIN_F1 / BIN_F2 lines
#     Replace comparisons: bin_k = BIN_F1  →  bin_k = bin_f0
#
#   TOP.vhd:
#     Thread min_energy, bin_f0, bin_f1 down to Energy_Detector and Bin_selector.
#
#   multi_channel_top.vhd — add ports:
#       n_active  : in std_logic_vector(2 downto 0)   -- runtime channel count
#       min_energy : in std_logic_vector(31 downto 0)
#       bin_f0     : in std_logic_vector(7 downto 0)
#       bin_f1     : in std_logic_vector(7 downto 0)
#     Use n_active to limit the output MUX range and gate channel instantiation.

# ── 0. Open block design ───────────────────────────────────────────────────
set bd_file [get_files design_1.bd]
if {$bd_file eq ""} {
    error "design_1.bd not found — make sure the project is open."
}
open_bd_design $bd_file
current_bd_design [get_bd_designs design_1]

# ── 1. Guard: prevent running twice ───────────────────────────────────────
foreach cell_name {axi_gpio_ctrl axi_gpio_thresh axi_gpio_freq} {
    if {[get_bd_cells $cell_name] ne ""} {
        error "$cell_name already exists — script has already been applied."
    }
}

# ── 2. Expand the AXI Lite interconnect from 1 → 4 masters ───────────────
# ps7_0_axi_periph currently: S00=PS GP0, M00=axi_dma_0
# After:                      S00=PS GP0, M00=axi_dma_0,
#                             M01=gpio_ctrl, M02=gpio_thresh, M03=gpio_freq
set ic [get_bd_cells ps7_0_axi_periph]
if {$ic eq ""} {
    error "ps7_0_axi_periph not found — verify the block design name."
}
set_property CONFIG.NUM_MI {4} $ic
puts "Expanded ps7_0_axi_periph: NUM_MI 1 -> 4"

# ── 3. Create GPIO IP instances ───────────────────────────────────────────

# --- 3a. axi_gpio_ctrl : n_active_channels ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_ctrl
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH   {4} \
    CONFIG.C_ALL_OUTPUTS  {1} \
    CONFIG.C_DOUT_DEFAULT {0x00000002} \
] [get_bd_cells axi_gpio_ctrl]
puts "Created axi_gpio_ctrl  (n_active_channels[3:0], default=2)"

# --- 3b. axi_gpio_thresh : energy threshold ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_thresh
set_property -dict [list \
    CONFIG.C_GPIO_WIDTH   {32} \
    CONFIG.C_ALL_OUTPUTS  {1} \
    CONFIG.C_DOUT_DEFAULT {0x3B9ACA00} \
] [get_bd_cells axi_gpio_thresh]
puts "Created axi_gpio_thresh (min_energy[31:0], default=1_000_000_000)"

# --- 3c. axi_gpio_freq : FFT bin indices (dual-channel) ---
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_freq
set_property -dict [list \
    CONFIG.C_IS_DUAL        {1} \
    CONFIG.C_GPIO_WIDTH     {8} \
    CONFIG.C_GPIO2_WIDTH    {8} \
    CONFIG.C_ALL_OUTPUTS    {1} \
    CONFIG.C_ALL_OUTPUTS_2  {1} \
    CONFIG.C_DOUT_DEFAULT   {0x00000019} \
    CONFIG.C_DOUT_DEFAULT_2 {0x0000001E} \
] [get_bd_cells axi_gpio_freq]
puts "Created axi_gpio_freq   (bin_f0[7:0]=25, bin_f1[7:0]=30)"

# ── 4. Connect AXI slave ports to interconnect master ports ───────────────
connect_bd_intf_net \
    [get_bd_intf_pins ps7_0_axi_periph/M01_AXI] \
    [get_bd_intf_pins axi_gpio_ctrl/S_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins ps7_0_axi_periph/M02_AXI] \
    [get_bd_intf_pins axi_gpio_thresh/S_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins ps7_0_axi_periph/M03_AXI] \
    [get_bd_intf_pins axi_gpio_freq/S_AXI]

puts "Connected AXI interfaces: M01->gpio_ctrl, M02->gpio_thresh, M03->gpio_freq"

# ── 5. Connect clocks ─────────────────────────────────────────────────────
# All three GPIO peripherals and the three new interconnect master ports
# all share the same 100 MHz FCLK_CLK0.
set clk [get_bd_pins processing_system7_0/FCLK_CLK0]

foreach pin [list \
    axi_gpio_ctrl/s_axi_aclk \
    axi_gpio_thresh/s_axi_aclk \
    axi_gpio_freq/s_axi_aclk \
    ps7_0_axi_periph/M01_ACLK \
    ps7_0_axi_periph/M02_ACLK \
    ps7_0_axi_periph/M03_ACLK \
] {
    connect_bd_net $clk [get_bd_pins $pin]
}
puts "Connected clocks (FCLK_CLK0 -> all GPIO + interconnect master ports)"

# ── 6. Connect resets (active-low peripheral_aresetn) ─────────────────────
# Locate the proc_sys_reset cell dynamically — it is named rst_ps7_0_100M_1
# in this project but the filter makes the script robust to renames.
set rst_cell [lindex \
    [get_bd_cells -filter {VLNV =~ "xilinx.com:ip:proc_sys_reset:*"}] 0]
if {$rst_cell eq ""} {
    error "proc_sys_reset cell not found. Check block design."
}
set rst [get_bd_pins ${rst_cell}/peripheral_aresetn]

foreach pin [list \
    axi_gpio_ctrl/s_axi_aresetn \
    axi_gpio_thresh/s_axi_aresetn \
    axi_gpio_freq/s_axi_aresetn \
    ps7_0_axi_periph/M01_ARESETN \
    ps7_0_axi_periph/M02_ARESETN \
    ps7_0_axi_periph/M03_ARESETN \
] {
    connect_bd_net $rst [get_bd_pins $pin]
}
puts "Connected resets (${rst_cell}/peripheral_aresetn -> all GPIO + interconnect)"

# ── 7. Note: gpio_io_o pins are intentionally left unconnected ────────────
# These outputs (the actual register values visible to the FPGA fabric) need
# to drive multi_channel_top_0's control input ports.  Those ports do not
# exist in the current RTL.  After updating the VHDL, run:
#
#   source {C:/Users/User/zynq-fsk-packet-detector/hw/connect_gpio_to_top.tcl}
#
# Vivado will emit "Warning: ... unconnected" for the gpio_io_o pins.
# This is expected and does not prevent implementation.
puts "NOTE: gpio_io_o pins are unconnected (see connect_gpio_to_top.tcl)."

# ── 8. Auto-assign addresses ──────────────────────────────────────────────
assign_bd_address
puts "Addresses assigned (check Address Editor for exact offsets)."

# ── 9. Validate and save ──────────────────────────────────────────────────
# Unconnected-output warnings from the GPIO cells are expected — not errors.
validate_bd_design
save_bd_design
puts "Block design validated and saved."

# ── 10. Regenerate wrapper ────────────────────────────────────────────────
generate_target all [get_files design_1.bd]
make_wrapper -files [get_files design_1.bd] -top
set wrapper [get_files design_1_wrapper.v]
if {$wrapper eq ""} { set wrapper [get_files design_1_wrapper.vhd] }
add_files -norecurse $wrapper
set_property top design_1_wrapper [current_fileset]
puts "Wrapper regenerated and set as top."

# ── Summary ───────────────────────────────────────────────────────────────
puts ""
puts "===================================================================="
puts "AXI GPIO blocks added to design_1."
puts ""
puts "Address map (Vivado assigns offsets; typical GP0 range 0x4000_0000+):"
puts "  axi_gpio_ctrl   M01  register 0x0000 = n_active_channels \[3:0\]"
puts "  axi_gpio_thresh M02  register 0x0000 = min_energy \[31:0\]"
puts "  axi_gpio_freq   M03  register 0x0000 = bin_f0 \[7:0\]"
puts "                       register 0x0008 = bin_f1 \[7:0\]  (GPIO2)"
puts ""
puts "Next steps:"
puts "  1. Open Address Editor in Vivado and note the base addresses."
puts "     Update BASEADDR constants in sw/multi_channel/run_fpga.py."
puts "  2. Update RTL — see comments at the top of this file."
puts "  3. After RTL update:"
puts "       source {.../hw/connect_gpio_to_top.tcl}"
puts "  4. Re-synthesise:"
puts "       reset_run synth_1"
puts "       launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "       wait_on_run impl_1"
puts "===================================================================="
