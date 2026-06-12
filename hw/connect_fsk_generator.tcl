# connect_fsk_generator.tcl
#
# SUPERSEDED by hw/build_multi_channel_design.tcl — kept for reference only.
#
# Replaces the external sample_in / sample_valid board ports with an
# internal fsk_packet_generator instance so the full detection pipeline
# can be exercised without an ADC or external signal source.
#
# Prerequisites:
#   1. replace_top.tcl has already been sourced (multi_channel_top_0 exists).
#   2. hw/rtl/fsk_packet_generator.vhd has been added to the project sources.
#      If not yet added, this script does it automatically.
#
# Run from the Vivado TCL console while the project is open:
#   source {C:/Users/User/zynq-fsk-packet-detector/hw/connect_fsk_generator.tcl}
#
# What this script changes:
#   - Adds fsk_packet_generator.vhd to the source fileset (if absent)
#   - Removes the sample_in [31:0] and sample_valid [1:0] external BD ports
#   - Instantiates fsk_gen_0 (fsk_packet_generator, N_CHANNEL=2)
#   - Connects clk, reset, sample_out, sample_valid to multi_channel_top_0
#
# What stays the same:
#   - AXI DMA, FIFO, GPIO, clocking, reset infrastructure
#   - multi_channel_top_0 and all its other connections

# ── 0. Open block design ───────────────────────────────────────────────────
set bd_file [get_files design_1.bd]
if {$bd_file eq ""} {
    error "design_1.bd not found — make sure the project is open."
}
open_bd_design $bd_file
current_bd_design [get_bd_designs design_1]

# ── 1. Guards ──────────────────────────────────────────────────────────────
if {[get_bd_cells multi_channel_top_0] eq ""} {
    error "multi_channel_top_0 not found. Source replace_top.tcl first."
}
if {[get_bd_cells fsk_gen_0] ne ""} {
    error "fsk_gen_0 already exists — script has already been applied."
}

# ── 2. Add RTL source if not already in the project ───────────────────────
set gen_src {C:/Users/User/zynq-fsk-packet-detector/hw/rtl/fsk_packet_generator.vhd}
set existing [get_files -quiet $gen_src]
if {$existing eq ""} {
    add_files -norecurse $gen_src
    puts "Added fsk_packet_generator.vhd to sources_1."
} else {
    puts "fsk_packet_generator.vhd already in project."
}
update_compile_order -fileset sources_1

# ── 3. Remove nets on multi_channel_top_0's sample input pins ─────────────
# These nets currently run from the external BD ports to the module.
# Deleting them leaves the pins unconnected, ready for the generator.
foreach pin_path {
    multi_channel_top_0/sample_in
    multi_channel_top_0/sample_valid
} {
    set n [get_bd_nets -of_objects [get_bd_pins $pin_path]]
    if {$n ne ""} {
        delete_bd_objs $n
        puts "Deleted net on $pin_path"
    } else {
        puts "No net found on $pin_path — skipping."
    }
}

# ── 4. Remove the now-unused external BD ports ────────────────────────────
foreach port_name {sample_in sample_valid} {
    set p [get_bd_ports -quiet $port_name]
    if {$p ne ""} {
        # A port may still have a dangling net after step 3; delete that first.
        set leftover [get_bd_nets -of_objects $p]
        if {$leftover ne ""} {
            delete_bd_objs $leftover
            puts "Deleted leftover net on port $port_name"
        }
        delete_bd_objs $p
        puts "Deleted BD port $port_name"
    } else {
        puts "BD port $port_name not found — already removed or never existed."
    }
}

# ── 5. Instantiate fsk_packet_generator ───────────────────────────────────
# Uses RTL module reference; generics default to N_CHANNEL=2, CLK_DIV=100,
# MATCH_EVERY=4.  To change them edit the VHDL generic defaults or set
# CONFIG properties below before validation.
create_bd_cell -type module -reference fsk_packet_generator fsk_gen_0
puts "Created fsk_gen_0."

# ── 6. Wire clock ──────────────────────────────────────────────────────────
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] \
               [get_bd_pins fsk_gen_0/clk]
puts "Connected clk (FCLK_CLK0 → fsk_gen_0/clk)."

# ── 7. Wire reset ──────────────────────────────────────────────────────────
# util_vector_logic_0/Res is the active-high reset derived from the PS7
# peripheral_aresetn via a NOT gate — same source used by multi_channel_top_0.
connect_bd_net [get_bd_pins util_vector_logic_0/Res] \
               [get_bd_pins fsk_gen_0/reset]
puts "Connected reset (util_vector_logic_0/Res → fsk_gen_0/reset)."

# ── 8. Wire sample data and valid ─────────────────────────────────────────
# fsk_gen_0/sample_out  [31:0]  → multi_channel_top_0/sample_in  [31:0]
# fsk_gen_0/sample_valid [1:0]  → multi_channel_top_0/sample_valid [1:0]
connect_bd_net [get_bd_pins fsk_gen_0/sample_out] \
               [get_bd_pins multi_channel_top_0/sample_in]
puts "Connected sample_out → sample_in."

connect_bd_net [get_bd_pins fsk_gen_0/sample_valid] \
               [get_bd_pins multi_channel_top_0/sample_valid]
puts "Connected sample_valid."

# ── 9. Validate and save ───────────────────────────────────────────────────
validate_bd_design
save_bd_design
puts "Block design validated and saved."

# ── 10. Regenerate wrapper ─────────────────────────────────────────────────
generate_target all [get_files design_1.bd]
make_wrapper -files [get_files design_1.bd] -top
set wrapper [get_files design_1_wrapper.v]
if {$wrapper eq ""} { set wrapper [get_files design_1_wrapper.vhd] }
add_files -norecurse $wrapper
set_property top design_1_wrapper [current_fileset]
puts "Wrapper regenerated and set as top."

puts ""
puts "===================================================================="
puts "FSK packet generator connected to multi_channel_top_0."
puts ""
puts "fsk_gen_0 defaults (edit VHDL generics to change):"
puts "  N_CHANNEL       = 2"
puts "  CLK_DIV         = 100   (sample rate = 100 MHz / 100 = 1 MHz)"
puts "  GAP_BITS        = 32    (32 × 256-sample noise windows between packets)"
puts "  PREAMBLE_BITS   = 32    (32 × 256-sample 120 kHz windows before sync)"
puts "  MATCH_EVERY     = 4     (every 4th packet forces same address on all channels)"
puts "  NOISE_AMPLITUDE = 200   (peak noise < energy detector MIN_ENERGY threshold)"
puts ""
puts "External ports sample_in and sample_valid have been removed from"
puts "the block design.  They are no longer present in the bitstream top level."
puts ""
puts "Next steps to rebuild the bitstream:"
puts "  reset_run synth_1"
puts "  launch_runs synth_1 -jobs 4"
puts "  wait_on_run synth_1"
puts "  launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "  wait_on_run impl_1"
puts "===================================================================="
