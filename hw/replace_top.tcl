# replace_top.tcl
#
# SUPERSEDED by hw/build_multi_channel_design.tcl, which performs this step
# plus the FSK generator and GPIO wiring in one consolidated, idempotent
# pass (and avoids leaving multi_channel_top_0's control inputs floating).
# Kept for reference only — do not run on its own.
#
# Replaces TOP_0 (single-channel) with multi_channel_top_0 in design_1.
#
# Run from the Vivado TCL console while the project is open:
#   source {C:/Users/User/zynq-fsk-packet-detector/hw/replace_top.tcl}
#
# What changes:
#   - TOP_0 removed; multi_channel_top_0 added
#   - sample_in  BD port: 16-bit -> 32-bit (2 channels packed)
#   - sample_valid BD port: 1-bit  ->  2-bit
#
# What stays the same:
#   - AXI DMA already 64-bit (c_m_axi_s2mm_data_width = 64)
#   - axis_data_fifo_0 already 64-bit with TLAST
#   - All clocking / reset / interconnect infrastructure

# ── 0. Open block design ──────────────────────────────────────────────────
set bd_file [get_files design_1.bd]
if {$bd_file eq ""} {
    error "design_1.bd not found — make sure the project is open."
}
open_bd_design $bd_file
current_bd_design [get_bd_designs design_1]

# ── 1. Guard: TOP_0 must exist ────────────────────────────────────────────
if {[get_bd_cells TOP_0] eq ""} {
    error "TOP_0 not found in the block design — nothing to replace."
}

# ── 2. Delete TOP_0 ───────────────────────────────────────────────────────
# Vivado automatically disconnects all of TOP_0's pins from their nets.
# The nets themselves survive (with one endpoint missing) until we delete them.
delete_bd_objs [get_bd_cells TOP_0]
puts "Deleted TOP_0."

# ── 3. Delete the now-stub nets ───────────────────────────────────────────
# These nets had one end on TOP_0 and are now dangling.
# Looked up via the surviving pin endpoint — robust against Vivado net renaming.
# DO NOT touch the nets on: processing_system7_0/FCLK_CLK0 or util_vector_logic_0/Res —
# those retain other connections and are reused below via pin references.
foreach pin_path {
    axis_data_fifo_0/s_axis_tdata
    axis_data_fifo_0/s_axis_tvalid
    axis_data_fifo_0/s_axis_tlast
    axis_data_fifo_0/s_axis_tready
} {
    set n [get_bd_nets -of_objects [get_bd_pins $pin_path]]
    if {$n ne ""} {
        delete_bd_objs $n
        puts "Deleted stub net on $pin_path"
    } else {
        puts "No stub net on $pin_path — skipping."
    }
}
# sample_in / sample_valid BD ports
foreach port_path {sample_in sample_valid} {
    set n [get_bd_nets -of_objects [get_bd_ports $port_path]]
    if {$n ne ""} {
        delete_bd_objs $n
        puts "Deleted stub net on port $port_path"
    } else {
        puts "No stub net on port $port_path — skipping."
    }
}

# ── 4. Widen the external sample ports ───────────────────────────────────
# sample_in:  2 channels * 16 bits = [31:0]
# sample_valid: one bit per channel = [1:0]
set_property -dict {CONFIG.LEFT 31 CONFIG.RIGHT 0} [get_bd_ports sample_in]
puts "Resized sample_in to [31:0]."

set_property -dict {CONFIG.LEFT 1 CONFIG.RIGHT 0} [get_bd_ports sample_valid]
puts "Resized sample_valid to [1:0]."

# ── 5. Add multi_channel_top ──────────────────────────────────────────────
# Uses default generics: N_channel=2, sample_size=16
create_bd_cell -type module -reference multi_channel_top multi_channel_top_0
puts "Created multi_channel_top_0."

# ── 6. Reconnect ──────────────────────────────────────────────────────────

# 6a. Clock — connect via the PS7 FCLK_CLK0 pin; Vivado extends the existing
#     net (whatever it was renamed to) to cover multi_channel_top_0/clk.
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins multi_channel_top_0/clk]
puts "Connected clk."

# 6b. Reset — util_vector_logic_0 inverts active-low peripheral_aresetn to
#     the active-high reset that multi_channel_top expects.
#     Drive from the NOT gate's output pin rather than by net name.
connect_bd_net [get_bd_pins util_vector_logic_0/Res] \
               [get_bd_pins multi_channel_top_0/reset]
puts "Connected reset."

# 6c. Sample inputs from the (now resized) BD ports
connect_bd_net [get_bd_ports sample_in]    [get_bd_pins multi_channel_top_0/sample_in]
connect_bd_net [get_bd_ports sample_valid] [get_bd_pins multi_channel_top_0/sample_valid]
puts "Connected sample_in / sample_valid."

# 6d. AXI Stream to the FIFO's slave port (fresh nets, Vivado will name them)
connect_bd_net [get_bd_pins multi_channel_top_0/tdata]  \
               [get_bd_pins axis_data_fifo_0/s_axis_tdata]
connect_bd_net [get_bd_pins multi_channel_top_0/tvalid] \
               [get_bd_pins axis_data_fifo_0/s_axis_tvalid]
connect_bd_net [get_bd_pins multi_channel_top_0/tready] \
               [get_bd_pins axis_data_fifo_0/s_axis_tready]
connect_bd_net [get_bd_pins multi_channel_top_0/tlast]  \
               [get_bd_pins axis_data_fifo_0/s_axis_tlast]
puts "Connected AXI Stream to FIFO."

# ── 7. Validate and save ──────────────────────────────────────────────────
validate_bd_design
save_bd_design
puts "Block design validated and saved."

# ── 8. Regenerate wrapper and targets ─────────────────────────────────────
generate_target all [get_files design_1.bd]
make_wrapper -files [get_files design_1.bd] -top
set wrapper [get_files design_1_wrapper.v]
if {$wrapper eq ""} {
    # The wrapper may already exist as a .vhd
    set wrapper [get_files design_1_wrapper.vhd]
}
add_files -norecurse $wrapper
set_property top design_1_wrapper [current_fileset]
puts "Wrapper regenerated and set as top."

puts ""
puts "===================================================================="
puts "Done. Next steps to regenerate the bitstream:"
puts "  1. reset_run synth_1"
puts "  2. launch_runs synth_1 -jobs 4"
puts "  3. wait_on_run synth_1"
puts "  4. launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "  5. wait_on_run impl_1"
puts "  Bitstream will be at: <project>.runs/impl_1/design_1_wrapper.bit"
puts "===================================================================="
