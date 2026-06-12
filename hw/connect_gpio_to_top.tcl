# connect_gpio_to_top.tcl
#
# SUPERSEDED by hw/build_multi_channel_design.tcl — kept for reference only.
#
# Phase 2: wire the AXI GPIO output registers to multi_channel_top_0's
# control input ports.
#
# Run THIS SCRIPT only AFTER:
#   1. hw/add_gpio_control.tcl has been applied, AND
#   2. The RTL has been updated to add these ports to multi_channel_top:
#
#        n_active   : in std_logic_vector(2 downto 0)
#        min_energy : in std_logic_vector(31 downto 0)
#        bin_f0     : in std_logic_vector(7 downto 0)
#        bin_f1     : in std_logic_vector(7 downto 0)
#
#   3. The updated VHDL file has been saved and Vivado has refreshed the IP.
#      If the cell pins are stale, run first:
#        refresh_bd_cells [get_bd_cells multi_channel_top_0]
#
# Run from the Vivado TCL console while the project is open:
#   source {C:/Users/User/zynq-fsk-packet-detector/hw/connect_gpio_to_top.tcl}

# ── 0. Open block design ───────────────────────────────────────────────────
set bd_file [get_files design_1.bd]
if {$bd_file eq ""} { error "design_1.bd not found." }
open_bd_design $bd_file
current_bd_design [get_bd_designs design_1]

# ── 1. Guard: GPIO blocks must exist ─────────────────────────────────────
foreach cell_name {axi_gpio_ctrl axi_gpio_thresh axi_gpio_freq} {
    if {[get_bd_cells $cell_name] eq ""} {
        error "$cell_name not found — run add_gpio_control.tcl first."
    }
}

# ── 2. Guard: multi_channel_top_0 must have the new ports ────────────────
foreach pin_path {
    multi_channel_top_0/n_active
    multi_channel_top_0/min_energy
    multi_channel_top_0/bin_f0
    multi_channel_top_0/bin_f1
} {
    if {[get_bd_pins $pin_path] eq ""} {
        error "$pin_path does not exist — update the VHDL and refresh the cell first:\n  refresh_bd_cells \[get_bd_cells multi_channel_top_0\]"
    }
}

# ── 3. Connect GPIO outputs to multi_channel_top_0 inputs ─────────────────

# axi_gpio_ctrl gpio_io_o[3:0] → n_active[2:0]
# The GPIO is 4-bit wide; only bits [2:0] are meaningful for channel count.
# Connect the full 3-bit n_active port to the lower slice of the 4-bit gpio output.
# If Vivado doesn't auto-slice, use xlslice; check if a width mismatch warning appears.
connect_bd_net \
    [get_bd_pins axi_gpio_ctrl/gpio_io_o] \
    [get_bd_pins multi_channel_top_0/n_active]
puts "Connected axi_gpio_ctrl/gpio_io_o -> multi_channel_top_0/n_active"

# axi_gpio_thresh gpio_io_o[31:0] → min_energy[31:0]
connect_bd_net \
    [get_bd_pins axi_gpio_thresh/gpio_io_o] \
    [get_bd_pins multi_channel_top_0/min_energy]
puts "Connected axi_gpio_thresh/gpio_io_o -> multi_channel_top_0/min_energy"

# axi_gpio_freq gpio_io_o[7:0]  → bin_f0[7:0]
connect_bd_net \
    [get_bd_pins axi_gpio_freq/gpio_io_o] \
    [get_bd_pins multi_channel_top_0/bin_f0]
puts "Connected axi_gpio_freq/gpio_io_o  -> multi_channel_top_0/bin_f0"

# axi_gpio_freq gpio2_io_o[7:0] → bin_f1[7:0]
connect_bd_net \
    [get_bd_pins axi_gpio_freq/gpio2_io_o] \
    [get_bd_pins multi_channel_top_0/bin_f1]
puts "Connected axi_gpio_freq/gpio2_io_o -> multi_channel_top_0/bin_f1"

# ── 4. Validate and save ──────────────────────────────────────────────────
validate_bd_design
save_bd_design
puts "Block design validated and saved."

generate_target all [get_files design_1.bd]
make_wrapper -files [get_files design_1.bd] -top
set wrapper [get_files design_1_wrapper.v]
if {$wrapper eq ""} { set wrapper [get_files design_1_wrapper.vhd] }
add_files -norecurse $wrapper
set_property top design_1_wrapper [current_fileset]
puts "Wrapper regenerated."

puts ""
puts "===================================================================="
puts "GPIO outputs are now wired to multi_channel_top_0."
puts "Re-synthesise to build the updated bitstream:"
puts "  reset_run synth_1"
puts "  launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "  wait_on_run impl_1"
puts "===================================================================="
