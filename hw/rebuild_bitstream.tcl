# rebuild_bitstream.tcl
#
# Batch-mode entry point: opens the Vivado project, applies the
# multi-channel block-design wiring, and rebuilds the bitstream.
#
# Run with:
#   vivado.bat -mode batch -source hw/rebuild_bitstream.tcl -log hw/rebuild.log -journal hw/rebuild.jou

open_project {C:/Users/User/fsk_signal_detection.xpr}

source {C:/Users/User/zynq-fsk-packet-detector/hw/build_multi_channel_design.tcl}

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "synth_1 failed — check hw/rebuild.log"
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "impl_1 failed — check hw/rebuild.log"
}

puts ""
puts "===================================================================="
puts "Bitstream build complete."
puts "Bitstream: [get_property DIRECTORY [get_runs impl_1]]/design_1_wrapper.bit"
puts "===================================================================="
