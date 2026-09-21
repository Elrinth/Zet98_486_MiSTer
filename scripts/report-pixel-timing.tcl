# Run in Zet98/v17 after fitting:
# quartus_sta -t ../../scripts/report-pixel-timing.tcl
# Reports the production pixel clocks. Older snapshots without these clocks
# receive the same definitions for audit only; that cannot improve their fit.
# This does not certify all crossings or external interface constraints.
project_open Zet98 -revision release-Zet98MiSTer
create_timing_netlist
read_sdc
update_timing_netlist

if {[get_collection_size [get_clocks -nowarn {pc98_pixel*}]] == 0} {
set pixel_register [get_registers {*|VID|TIM|clk3sft[2]}]
set pixel_source [get_pins -compatibility_mode {*|VID|TIM|clk3sft[2]|clk}]
if {[get_collection_size $pixel_register] != 1 || [get_collection_size $pixel_source] != 1} {
    error "Expected one VTIMING pixel divider register and clock pin"
}
# VTIMING rotates 001 at 75 MHz: 25 MHz with one parent cycle high.
# Reset may release on any of three parent cycles. Check every phase relative
# to the other PLL clocks. Only these mutually exclusive phases are excluded
# from timing against one another. The audit adds no data-path exceptions;
# inherited project constraints remain in force.
create_generated_clock -name pc98_pixel_phase0 -source $pixel_source -edges {1 3 7} $pixel_register
create_generated_clock -name pc98_pixel_phase1 -source $pixel_source -edges {3 5 9} -add $pixel_register
create_generated_clock -name pc98_pixel_phase2 -source $pixel_source -edges {5 7 11} -add $pixel_register
set_clock_groups -logically_exclusive -group {pc98_pixel_phase0} -group {pc98_pixel_phase1} -group {pc98_pixel_phase2}
}
derive_clock_uncertainty
update_timing_netlist
report_clocks -file output_files/pixel-generated-clocks.txt
report_timing -setup -from_clock [get_clocks {pc98_pixel*}] -npaths 8 -detail full_path -file output_files/pixel-setup-from.txt
report_timing -setup -to_clock [get_clocks {pc98_pixel*}] -npaths 8 -detail full_path -file output_files/pixel-setup-to.txt
report_timing -hold -from_clock [get_clocks {pc98_pixel*}] -npaths 8 -detail full_path -file output_files/pixel-hold-from.txt
report_timing -hold -to_clock [get_clocks {pc98_pixel*}] -npaths 8 -detail full_path -file output_files/pixel-hold-to.txt
delete_timing_netlist
project_close
