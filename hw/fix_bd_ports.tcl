# fix_bd_ports.tcl  — flat, no loops, no lassign
#
# SUPERSEDED by hw/build_multi_channel_design.tcl — kept for reference only.
# Recreates sample_in [31:0] and sample_valid [1:0] and reconnects them.
#
# source {C:/Users/User/zynq-fsk-packet-detector/hw/fix_bd_ports.tcl}

open_bd_design [get_files design_1.bd]
current_bd_design [get_bd_designs design_1]

# ── sample_in ─────────────────────────────────────────────────────────────
# Remove every net touching the port or the cell pin before deleting either.
set n [get_bd_nets -of_objects [get_bd_ports sample_in]]
if {$n ne ""} { delete_bd_objs $n }
set n [get_bd_nets -of_objects [get_bd_pins multi_channel_top_0/sample_in]]
if {$n ne ""} { delete_bd_objs $n }

delete_bd_objs [get_bd_ports sample_in]
create_bd_port -dir I -from 31 -to 0 sample_in
connect_bd_net [get_bd_ports sample_in] [get_bd_pins multi_channel_top_0/sample_in]
puts "sample_in \[31:0\] done."

# ── sample_valid ──────────────────────────────────────────────────────────
set n [get_bd_nets -of_objects [get_bd_ports sample_valid]]
if {$n ne ""} { delete_bd_objs $n }
set n [get_bd_nets -of_objects [get_bd_pins multi_channel_top_0/sample_valid]]
if {$n ne ""} { delete_bd_objs $n }

delete_bd_objs [get_bd_ports sample_valid]
create_bd_port -dir I -from 1 -to 0 sample_valid
connect_bd_net [get_bd_ports sample_valid] [get_bd_pins multi_channel_top_0/sample_valid]
puts "sample_valid \[1:0\] done."

# ── Validate, save, regenerate wrapper ────────────────────────────────────
validate_bd_design
save_bd_design
generate_target all [get_files design_1.bd]
make_wrapper -files [get_files design_1.bd] -top
puts "Done — reset synth_1, re-run impl_1 to rebuild bitstream."
