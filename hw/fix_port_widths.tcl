# fix_port_widths.tcl
#
# SUPERSEDED by hw/build_multi_channel_design.tcl — kept for reference only.
#
# Resizes sample_in to [31:0] and sample_valid to [1:0].
# BD ports cannot be resized with set_property — they must be deleted
# and recreated. Existing connections to multi_channel_top_0 are
# re-established after recreation.
#
# Run from the Vivado TCL console with the project open:
#   source {C:/Users/User/zynq-fsk-packet-detector/hw/fix_port_widths.tcl}

set bd_file [get_files design_1.bd]
if {$bd_file eq ""} { error "design_1.bd not found — open the project first." }
open_bd_design $bd_file
current_bd_design [get_bd_designs design_1]

# Delete any net hanging off each port, then delete the port itself,
# then recreate it at the correct width, then reconnect.
foreach item {
    {sample_in    I 31  0 multi_channel_top_0/sample_in}
    {sample_valid I  1  0 multi_channel_top_0/sample_valid}
} {
    lassign $item port_name dir msb lsb cell_pin

    # Disconnect / remove old net on this port
    set old_net [get_bd_nets -of_objects [get_bd_ports $port_name]]
    if {$old_net ne ""} { delete_bd_objs $old_net }

    # Delete the port
    delete_bd_objs [get_bd_ports $port_name]
    puts "Deleted port $port_name."

    # Recreate with correct width
    create_bd_port -dir $dir -from $msb -to $lsb $port_name
    puts "Created port $port_name \[$msb:$lsb\]."

    # Reconnect to multi_channel_top_0
    connect_bd_net [get_bd_ports $port_name] [get_bd_pins $cell_pin]
    puts "Connected $port_name -> $cell_pin."
}

validate_bd_design
save_bd_design
puts "Done — port widths fixed, design saved."
