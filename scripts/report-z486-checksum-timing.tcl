# Optional post-fit diagnosis for a z486 BIOS checksum failure.
# Run from the saved Zet98/v17 snapshot; this changes no constraints or RTL.
project_open Zet98 -revision release-Zet98MiSTer
create_timing_netlist
read_sdc
update_timing_netlist

# Separate architectural endpoints so numerous paths into the same microcode
# bit cannot hide the byte-add, LOOP, LODSW and branch/flag paths of interest.
foreach {group patterns} {
    eax {*|data_unit_inst|eax*}
    ecx {*|data_unit_inst|ecx*}
    edx {*|data_unit_inst|edx*}
    esi {*|data_unit_inst|esi*}
    flags {*|data_unit_inst|eflags*}
    load {*|data_unit_inst|opr_r* *|vipt_load_wb_data_r*}
    microcode {*|microsequencer_inst|*}
    issue {*|d2_valid_r* *|data_unit_inst|dst_reg_sel_r*}
} {
    set endpoints($group) [get_registers $patterns]
    set count [get_collection_size $endpoints($group)]
    puts "CHECKSUM TIMING GROUP $group: $count registers"
    if {$count == 0} {
        error "Missing $group endpoints; inspect fitted register names"
    }
}

set corner 0
foreach_in_collection condition [get_available_operating_conditions] {
    set_operating_conditions $condition
    update_timing_netlist
    puts "CHECKSUM CORNER $corner: model=[get_operating_conditions_info $condition -model] temperature=[get_operating_conditions_info $condition -temperature]"
    foreach group [lsort [array names endpoints]] {
        report_timing -setup -to $endpoints($group) -npaths 4 -nworst 1 \
            -detail full_path -file output_files/checksum-${corner}-${group}.txt
    }
    incr corner
}
delete_timing_netlist
project_close
