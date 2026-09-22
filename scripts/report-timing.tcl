# Run in Zet98/v17 after fitting:
# quartus_sta -t ../../scripts/report-timing.tcl
project_open Zet98 -revision release-Zet98MiSTer
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 12 -detail full_path -file output_files/critical-setup-paths.txt
report_timing -hold -npaths 8 -detail full_path -file output_files/critical-hold-paths.txt
report_timing -recovery -npaths 4 -detail full_path -file output_files/critical-recovery-paths.txt
report_clock_fmax_summary -file output_files/clock-fmax.txt
set system_clock [get_clocks {*emu*general?1?*divclk}]
if {[get_collection_size $system_clock] != 1} {
    error "Expected exactly one core system clock"
}
report_timing -setup -from_clock $system_clock -to_clock $system_clock -npaths 6 -nworst 1 -detail full_path -file output_files/system-setup-paths.txt
# Overall worst paths can all end in the CPU. Also expose the worst incoming
# paths for each peripheral clock so CPU improvements do not hide other limits.
foreach {domain pattern} {incoming-system {*emu*general?1?*divclk} memory {*emu*general?0?*divclk} video {*emu*general?2?*divclk} hdmi {*pll_hdmi*counter?0?*divclk}} {
    set domain_clock [get_clocks $pattern]
    set domain_clocks($domain) $domain_clock
    if {[get_collection_size $domain_clock] != 1} {
        error "Expected exactly one $domain clock"
    }
    report_timing -setup -to_clock $domain_clock -npaths 6 -nworst 1 -detail full_path -file output_files/${domain}-setup-paths.txt
}
set cpu_registers [get_registers {*|cpu|* *|*zet_cpu:cpu|*}]
if {[get_collection_size $cpu_registers] == 0} {
    error "CPU registers were not found"
}
report_timing -setup -from $cpu_registers -to $cpu_registers -npaths 6 -nworst 1 -detail full_path -file output_files/cpu-setup-paths.txt
# The default slow/hot corner does not expose cold-corner hold/removal
# failures. Keep each available corner separate so no result is overwritten.
set corner 0
foreach_in_collection condition [get_available_operating_conditions] {
    set_operating_conditions $condition
    update_timing_netlist
    puts "CORNER $corner: model=[get_operating_conditions_info $condition -model] temperature=[get_operating_conditions_info $condition -temperature]"
    foreach check {setup hold recovery removal} {
        report_timing -$check -npaths 6 -nworst 1 -detail full_path -file output_files/corner-${corner}-${check}.txt
    }
    # A cold HDMI failure may be hidden below six worse CPU/memory paths.
    # Report every destination domain at every corner independently.
    foreach domain {incoming-system memory video hdmi} {
        report_timing -setup -to_clock $domain_clocks($domain) -npaths 6 -nworst 1 -detail full_path -file output_files/corner-${corner}-${domain}.txt
    }
    incr corner
}
delete_timing_netlist
project_close
