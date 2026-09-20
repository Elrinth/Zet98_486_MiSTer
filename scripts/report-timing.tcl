# Run in Zet98/v17 after fitting:
# quartus_sta -t ../../scripts/report-timing.tcl
project_open Zet98 -revision release-Zet98MiSTer
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 12 -detail full_path -file output_files/critical-setup-paths.txt
report_timing -recovery -npaths 4 -detail full_path -file output_files/critical-recovery-paths.txt
report_clock_fmax_summary -file output_files/clock-fmax.txt
set system_clock [get_clocks {*emu*general?1?*divclk}]
if {[get_collection_size $system_clock] != 1} {
    error "Expected exactly one core system clock"
}
report_timing -setup -from_clock $system_clock -to_clock $system_clock -npaths 6 -nworst 1 -detail full_path -file output_files/system-setup-paths.txt
set cpu_registers [get_registers {*|cpu|*}]
if {[get_collection_size $cpu_registers] == 0} {
    error "Zet CPU registers were not found"
}
report_timing -setup -from $cpu_registers -to $cpu_registers -npaths 6 -nworst 1 -detail full_path -file output_files/cpu-setup-paths.txt
delete_timing_netlist
project_close
