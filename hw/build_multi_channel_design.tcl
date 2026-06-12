# build_multi_channel_design.tcl
#
# Consolidated, idempotent rebuild of design_1's block design for the
# 2-channel FSK detector with on-board packet generator and runtime
# AXI-GPIO controls.
#
# This script supersedes the older step-by-step scripts
# (replace_top.tcl, connect_fsk_generator.tcl, add_gpio_control.tcl,
# connect_gpio_to_top.tcl, recover_wiring.tcl, fix_port_widths.tcl,
# fix_bd_ports.tcl). Those are kept for reference only — do not run them;
# run this script instead. It can be re-run safely at any point: every
# step checks whether it has already been applied before acting, and
# multi_channel_top_0's pins are fully (re)connected in one pass so no
# input is ever left floating across a validate/save boundary.
#
# Run from the Vivado TCL console while the project is open:
#   source {C:/Users/User/zynq-fsk-packet-detector/hw/build_multi_channel_design.tcl}
#
# End state:
#   fsk_gen_0 (fsk_packet_generator) --sample_out/sample_valid--> multi_channel_top_0
#   multi_channel_top_0 --tdata/tvalid/tlast/tready--> axis_data_fifo_0
#   axi_gpio_ctrl/gpio_io_o   -> multi_channel_top_0/n_active   (4 bit)
#   axi_gpio_thresh/gpio_io_o -> multi_channel_top_0/min_energy (32 bit)
#   axi_gpio_freq/gpio_io_o   -> multi_channel_top_0/bin_f0     (8 bit)
#   axi_gpio_freq/gpio2_io_o  -> multi_channel_top_0/bin_f1     (8 bit)
#   No external sample_in / sample_valid BD ports (internal generator only).

# ── 0. Open block design ───────────────────────────────────────────────────
set bd_file [get_files design_1.bd]
if {$bd_file eq ""} {
    error "design_1.bd not found — make sure the project is open."
}
open_bd_design $bd_file
current_bd_design [get_bd_designs design_1]

# ── 1. Replace TOP_0 with multi_channel_top_0 ─────────────────────────────
if {[get_bd_cells -quiet TOP_0] ne ""} {
    delete_bd_objs [get_bd_cells TOP_0]
    puts "Deleted TOP_0."
    foreach pin_path {
        axis_data_fifo_0/s_axis_tdata
        axis_data_fifo_0/s_axis_tvalid
        axis_data_fifo_0/s_axis_tlast
        axis_data_fifo_0/s_axis_tready
    } {
        set n [get_bd_nets -quiet -of_objects [get_bd_pins $pin_path]]
        if {$n ne ""} { delete_bd_objs $n }
    }
}

if {[get_bd_cells -quiet multi_channel_top_0] eq ""} {
    create_bd_cell -type module -reference multi_channel_top multi_channel_top_0
    puts "Created multi_channel_top_0."
} else {
    puts "multi_channel_top_0 already exists."
}

# ── 2. Add the on-board FSK packet generator ──────────────────────────────
set gen_src {C:/Users/User/zynq-fsk-packet-detector/hw/rtl/fsk_packet_generator.vhd}
if {[get_files -quiet $gen_src] eq ""} {
    add_files -norecurse $gen_src
    update_compile_order -fileset sources_1
    puts "Added fsk_packet_generator.vhd."
}

if {[get_bd_cells -quiet fsk_gen_0] eq ""} {
    create_bd_cell -type module -reference fsk_packet_generator fsk_gen_0
    puts "Created fsk_gen_0."
} else {
    puts "fsk_gen_0 already exists."
}

# ── 3. Remove external sample_in / sample_valid BD ports (if present) ────
# The packet generator drives multi_channel_top_0 internally — no external
# sample ports are needed.
foreach port_name {sample_in sample_valid} {
    set p [get_bd_ports -quiet $port_name]
    if {$p ne ""} {
        set n [get_bd_nets -quiet -of_objects $p]
        if {$n ne ""} { delete_bd_objs $n }
        delete_bd_objs $p
        puts "Removed external BD port $port_name."
    }
}

# ── 4. Add AXI GPIO runtime-control peripherals ───────────────────────────
set need_gpio 0
foreach cell_name {axi_gpio_ctrl axi_gpio_thresh axi_gpio_freq} {
    if {[get_bd_cells -quiet $cell_name] eq ""} { set need_gpio 1 }
}

if {$need_gpio} {
    set ic [get_bd_cells ps7_0_axi_periph]
    if {$ic eq ""} {
        error "ps7_0_axi_periph not found — verify the block design name."
    }
    set_property CONFIG.NUM_MI {4} $ic
    puts "Expanded ps7_0_axi_periph: NUM_MI -> 4"

    if {[get_bd_cells -quiet axi_gpio_ctrl] eq ""} {
        create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_ctrl
        set_property -dict [list \
            CONFIG.C_GPIO_WIDTH   {4} \
            CONFIG.C_ALL_OUTPUTS  {1} \
            CONFIG.C_DOUT_DEFAULT {0x00000002} \
        ] [get_bd_cells axi_gpio_ctrl]
        puts "Created axi_gpio_ctrl (n_active[3:0], default=2)."
    }

    if {[get_bd_cells -quiet axi_gpio_thresh] eq ""} {
        create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 axi_gpio_thresh
        set_property -dict [list \
            CONFIG.C_GPIO_WIDTH   {32} \
            CONFIG.C_ALL_OUTPUTS  {1} \
            CONFIG.C_DOUT_DEFAULT {0x3B9ACA00} \
        ] [get_bd_cells axi_gpio_thresh]
        puts "Created axi_gpio_thresh (min_energy[31:0], default=1e9)."
    }

    if {[get_bd_cells -quiet axi_gpio_freq] eq ""} {
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
        puts "Created axi_gpio_freq (bin_f0[7:0]=25, bin_f1[7:0]=30)."
    }

    # AXI interface connections (M01/M02/M03 of ps7_0_axi_periph)
    if {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins axi_gpio_ctrl/S_AXI]] eq ""} {
        connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M01_AXI] \
                             [get_bd_intf_pins axi_gpio_ctrl/S_AXI]
    }
    if {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins axi_gpio_thresh/S_AXI]] eq ""} {
        connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M02_AXI] \
                             [get_bd_intf_pins axi_gpio_thresh/S_AXI]
    }
    if {[get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins axi_gpio_freq/S_AXI]] eq ""} {
        connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M03_AXI] \
                             [get_bd_intf_pins axi_gpio_freq/S_AXI]
    }
    puts "Connected GPIO AXI interfaces (M01/M02/M03)."

    # Clocks
    set clk [get_bd_pins processing_system7_0/FCLK_CLK0]
    foreach pin [list \
        axi_gpio_ctrl/s_axi_aclk axi_gpio_thresh/s_axi_aclk axi_gpio_freq/s_axi_aclk \
        ps7_0_axi_periph/M01_ACLK ps7_0_axi_periph/M02_ACLK ps7_0_axi_periph/M03_ACLK \
    ] {
        if {[get_bd_nets -quiet -of_objects [get_bd_pins $pin]] eq ""} {
            connect_bd_net $clk [get_bd_pins $pin]
        }
    }
    puts "Connected GPIO clocks."

    # Resets
    set rst_cell [lindex [get_bd_cells -filter {VLNV =~ "xilinx.com:ip:proc_sys_reset:*"}] 0]
    if {$rst_cell eq ""} {
        error "proc_sys_reset cell not found. Check block design."
    }
    set rst [get_bd_pins ${rst_cell}/peripheral_aresetn]
    foreach pin [list \
        axi_gpio_ctrl/s_axi_aresetn axi_gpio_thresh/s_axi_aresetn axi_gpio_freq/s_axi_aresetn \
        ps7_0_axi_periph/M01_ARESETN ps7_0_axi_periph/M02_ARESETN ps7_0_axi_periph/M03_ARESETN \
    ] {
        if {[get_bd_nets -quiet -of_objects [get_bd_pins $pin]] eq ""} {
            connect_bd_net $rst [get_bd_pins $pin]
        }
    }
    puts "Connected GPIO resets."

    assign_bd_address
    puts "Assigned AXI addresses."
}

# ── 5. (Re)connect multi_channel_top_0 and fsk_gen_0 from a clean slate ──
# Disconnect any existing nets on these two cells first so re-running this
# script is safe even if the BD is in a partially-wired state. Point-to-point
# nets (e.g. fsk_gen_0/sample_out -> multi_channel_top_0/sample_in) become
# empty once both endpoints are disconnected — delete those outright so a
# later connect_bd_net doesn't reuse a now-sourceless net of the same name.
foreach pin [concat [get_bd_pins multi_channel_top_0/*] [get_bd_pins fsk_gen_0/*]] {
    set n [get_bd_nets -quiet -of_objects $pin]
    if {$n ne ""} {
        disconnect_bd_net $n $pin
        if {[llength [get_bd_pins -quiet -of_objects $n]] == 0} {
            delete_bd_objs $n
        }
    }
}

set clk [get_bd_pins processing_system7_0/FCLK_CLK0]
set rst [get_bd_pins util_vector_logic_0/Res]

# clk / reset
connect_bd_net $clk [get_bd_pins multi_channel_top_0/clk]
connect_bd_net $rst [get_bd_pins multi_channel_top_0/reset]
connect_bd_net $clk [get_bd_pins fsk_gen_0/clk]
connect_bd_net $rst [get_bd_pins fsk_gen_0/reset]
puts "Connected clk/reset to multi_channel_top_0 and fsk_gen_0."

# packet generator -> multi_channel_top_0 sample inputs
connect_bd_net [get_bd_pins fsk_gen_0/sample_out]   [get_bd_pins multi_channel_top_0/sample_in]
connect_bd_net [get_bd_pins fsk_gen_0/sample_valid] [get_bd_pins multi_channel_top_0/sample_valid]
puts "Connected fsk_gen_0 -> multi_channel_top_0 sample_in/sample_valid."

# AXI Stream output -> FIFO
connect_bd_net [get_bd_pins multi_channel_top_0/tdata]  [get_bd_pins axis_data_fifo_0/s_axis_tdata]
connect_bd_net [get_bd_pins multi_channel_top_0/tvalid] [get_bd_pins axis_data_fifo_0/s_axis_tvalid]
connect_bd_net [get_bd_pins multi_channel_top_0/tready] [get_bd_pins axis_data_fifo_0/s_axis_tready]
connect_bd_net [get_bd_pins multi_channel_top_0/tlast]  [get_bd_pins axis_data_fifo_0/s_axis_tlast]
puts "Connected multi_channel_top_0 -> axis_data_fifo_0."

# Runtime GPIO controls -> multi_channel_top_0 control inputs
connect_bd_net [get_bd_pins axi_gpio_ctrl/gpio_io_o]   [get_bd_pins multi_channel_top_0/n_active]
connect_bd_net [get_bd_pins axi_gpio_thresh/gpio_io_o] [get_bd_pins multi_channel_top_0/min_energy]
connect_bd_net [get_bd_pins axi_gpio_freq/gpio_io_o]   [get_bd_pins multi_channel_top_0/bin_f0]
connect_bd_net [get_bd_pins axi_gpio_freq/gpio2_io_o]  [get_bd_pins multi_channel_top_0/bin_f1]
puts "Connected GPIO outputs -> multi_channel_top_0 n_active/min_energy/bin_f0/bin_f1."

# ── 6. Validate and save ──────────────────────────────────────────────────
validate_bd_design
save_bd_design
puts "Block design validated and saved."

# ── 7. Regenerate wrapper and targets ─────────────────────────────────────
generate_target all [get_files design_1.bd]
make_wrapper -files [get_files design_1.bd] -top -force
set wrapper [get_files design_1_wrapper.v]
if {$wrapper eq ""} { set wrapper [get_files design_1_wrapper.vhd] }
add_files -norecurse $wrapper
set_property top design_1_wrapper [current_fileset]
puts "Wrapper regenerated and set as top."

puts ""
puts "===================================================================="
puts "Done. multi_channel_top_0 is fully wired:"
puts "  fsk_gen_0 -> multi_channel_top_0 -> axis_data_fifo_0 -> AXI DMA"
puts "  axi_gpio_ctrl/thresh/freq -> n_active/min_energy/bin_f0/bin_f1"
puts ""
puts "Next steps to rebuild the bitstream:"
puts "  reset_run synth_1"
puts "  launch_runs synth_1 -jobs 4"
puts "  wait_on_run synth_1"
puts "  launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "  wait_on_run impl_1"
puts "===================================================================="
