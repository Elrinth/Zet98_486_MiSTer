# Run in Zet98/v17 after fitting:
# quartus_sta -t ../../scripts/report-path-classes.tcl
# Lists the worst system-clock setup paths (slack, from, to) for grouping by
# source/destination module (output_files/system-setup-classes.txt).
project_open Zet98 -revision release-Zet98MiSTer
create_timing_netlist
read_sdc
update_timing_netlist
set clk [get_clocks {*emu*general?1?*divclk}]
set out [open output_files/system-setup-classes.txt w]
foreach_in_collection p [get_timing_paths -setup -from_clock $clk -to_clock $clk -npaths 5000 -nworst 1] {
    puts $out "[get_path_info $p -slack]\t[get_node_info -name [get_path_info $p -from]]\t[get_node_info -name [get_path_info $p -to]]\t[get_path_info $p -num_logic_levels]"
}
close $out
project_close
