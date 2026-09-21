# Run using quartus_sta after scripts/probe-cpu.tcl completes.
project_open cpu_probe
create_timing_netlist
read_sdc
update_timing_netlist
report_clock_fmax_summary -file output_files/cpu-fmax.txt
set registers [all_registers]
report_timing -setup -from $registers -to $registers -npaths 8 -detail full_path -file output_files/register-setup.txt
report_timing -hold -from $registers -to $registers -npaths 4 -detail full_path -file output_files/register-hold.txt
report_ucp -file output_files/unconstrained.txt
delete_timing_netlist
project_close
