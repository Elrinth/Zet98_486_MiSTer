# Run with quartus_sh in an EMPTY build directory:
# quartus_sh -t /tools/probe-cpu.tcl /source 66
# CPU/legacy-bus adapter feasibility only. Virtual pins do not describe a board,
# and a successful probe does not establish PC-98 platform timing or usability.
package require ::quartus::project
package require ::quartus::flow
if {[llength $argv] != 2} { error "Usage: probe-cpu.tcl source_root clock_mhz" }
set source_root [file normalize [lindex $argv 0]]
set clock_mhz [lindex $argv 1]
if {![string is double -strict $clock_mhz] || $clock_mhz < 1 || $clock_mhz > 150} {
    error "clock_mhz must be between 1 and 150"
}
if {[file exists cpu_probe.qpf]} { error "Use a fresh build directory" }
set constraints [open probe.sdc w]
puts $constraints "create_clock -name cpu_clk -period [expr {1000.0 / $clock_mhz}] \[get_ports clk\]"
puts $constraints {derive_clock_uncertainty}
puts $constraints {set_input_delay -clock cpu_clk 1.0 [remove_from_collection [all_inputs] [get_ports clk]]}
puts $constraints {set_output_delay -clock cpu_clk 1.0 [all_outputs]}
close $constraints
project_new cpu_probe
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CSEBA6U23I7
set_global_assignment -name TOP_LEVEL_ENTITY pc98_ao486
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE PERFORMANCE"
set_global_assignment -name NUM_PARALLEL_PROCESSORS 4
set_global_assignment -name QIP_FILE [file join $source_root rtl/cpu/ao486_pc98.qip]
set_global_assignment -name SDC_FILE probe.sdc
set_instance_assignment -name VIRTUAL_PIN ON -to *
set_instance_assignment -name IO_STANDARD "2.5 V" -to *
export_assignments
execute_module -tool map
execute_module -tool fit
execute_module -tool sta
project_close
