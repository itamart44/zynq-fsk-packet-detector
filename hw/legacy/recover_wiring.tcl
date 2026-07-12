# recover_wiring.tcl
#
# SUPERSEDED by hw/build_multi_channel_design.tcl — kept for reference only.
#
# Recovery script — assumes TOP_0 is already deleted and stub nets are gone.
# Creates multi_channel_top_0 (if absent) and wires it up from scratch.
#
# Run from the Vivado TCL console with the project open:
#   source {C:/Users/User/zynq-fsk-packet-detector/hw/recover_wiring.tcl}

# ── 0. Open block design ──────────────────────────────────────────────────
set bd_file [get_files design_1.bd]
if {$bd_file eq ""} { error "design_1.bd not found — open the project first." }
open_bd_design $bd_file
current_bd_design [get_bd_designs design_1]

# ── 1. Create multi_channel_top_0 if not already present ─────────────────
if {[get_bd_cells multi_channel_top_0] eq ""} {
    create_bd_cell -type module -reference multi_channel_top multi_channel_top_0
    puts "Created multi_channel_top_0."
} else {
    puts "multi_channel_top_0 already exists — skipping creation."
}

# ── 2. Clear any partial connections on multi_channel_top_0 ──────────────
# Safe to call even if the pins are already unconnected.
foreach pin [get_bd_pins multi_channel_top_0/*] {
    set n [get_bd_nets -of_objects $pin]
    if {$n ne ""} {
        disconnect_bd_net $n $pin
        puts "Cleared existing connection on [get_property NAME $pin]"
    }
}

# ── 3. Ensure sample ports are the right width ────────────────────────────
# BD ports cannot be resized with set_property — delete and recreate.
foreach item {
    {sample_in    I 31  0}
    {sample_valid I  1  0}
} {
    lassign $item port_name dir msb lsb
    set n [get_bd_nets -of_objects [get_bd_ports $port_name]]
    if {$n ne ""} { delete_bd_objs $n }
    delete_bd_objs [get_bd_ports $port_name]
    create_bd_port -dir $dir -from $msb -to $lsb $port_name
}
puts "sample_in=[31:0]  sample_valid=[1:0]"

# ── 4. Ensure FIFO slave pins have no stale nets ──────────────────────────
foreach pin_path {
    axis_data_fifo_0/s_axis_tdata
    axis_data_fifo_0/s_axis_tvalid
    axis_data_fifo_0/s_axis_tready
    axis_data_fifo_0/s_axis_tlast
} {
    set n [get_bd_nets -of_objects [get_bd_pins $pin_path]]
    if {$n ne ""} { delete_bd_objs $n }
}

# ── 5. Wire up multi_channel_top_0 ───────────────────────────────────────
# All connections are made pin-to-pin so Vivado extends the correct
# existing net (clk, reset) or creates a new one (AXI stream, samples).

connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins multi_channel_top_0/clk]
puts "Connected clk."

connect_bd_net [get_bd_pins util_vector_logic_0/Res] \
               [get_bd_pins multi_channel_top_0/reset]
puts "Connected reset."

connect_bd_net [get_bd_ports sample_in]    [get_bd_pins multi_channel_top_0/sample_in]
connect_bd_net [get_bd_ports sample_valid] [get_bd_pins multi_channel_top_0/sample_valid]
puts "Connected sample_in / sample_valid."

connect_bd_net [get_bd_pins multi_channel_top_0/tdata]  [get_bd_pins axis_data_fifo_0/s_axis_tdata]
connect_bd_net [get_bd_pins multi_channel_top_0/tvalid] [get_bd_pins axis_data_fifo_0/s_axis_tvalid]
connect_bd_net [get_bd_pins multi_channel_top_0/tready] [get_bd_pins axis_data_fifo_0/s_axis_tready]
connect_bd_net [get_bd_pins multi_channel_top_0/tlast]  [get_bd_pins axis_data_fifo_0/s_axis_tlast]
puts "Connected AXI Stream to FIFO."

# ── 6. Validate and save ──────────────────────────────────────────────────
validate_bd_design
save_bd_design
puts "Block design validated and saved."

# ── 7. Regenerate wrapper ─────────────────────────────────────────────────
generate_target all [get_files design_1.bd]
make_wrapper -files [get_files design_1.bd] -top
set wrapper [get_files design_1_wrapper.v]
if {$wrapper eq ""} { set wrapper [get_files design_1_wrapper.vhd] }
add_files -norecurse $wrapper
set_property top design_1_wrapper [current_fileset]
puts "Wrapper regenerated."

puts ""
puts "===================================================================="
puts "Done. Rebuild bitstream:"
puts "  reset_run synth_1"
puts "  launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "  wait_on_run impl_1"
puts "===================================================================="
