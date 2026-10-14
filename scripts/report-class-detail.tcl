# Run in Zet98/v17 after fitting:
# quartus_sta -t ../../scripts/report-class-detail.tcl
# Worst detailed setup path for each major z486 path class
# (output_files/class-detail.txt).
project_open Zet98 -revision release-Zet98MiSTer
create_timing_netlist
read_sdc
update_timing_netlist
set f output_files/class-detail.txt
file delete -force $f
foreach {from to} {
    *skel_raw_lit_off_r* *microcode_rom*
    *skel_raw_lit_off_r* *desc_cache*base*
    *skel_raw_lit_off_r* *desc_cache*limit*
    *skel_raw_lit_off_r* *seg_base_r*
    *skel_raw_lit_off_r* *exec_ind_r*
    *skel_window_raw_r* *i.displacement*
    *CR0* *microcode_rom*
    *CR0* *entry_rom*
    *flag2_result_r* *entry_rom*
    *flag2_result_r* *win_d1_r*
    *vipt_tlb* *desc_cache*limit*
    *vipt_tlb* *microcode_rom*
    *vipt_load_wb_valid_r* *sigma*
    *vipt_load_wb_size_r* *sigma*
    *recipe_memory_mode* *sigma*
    *op_size_src* *flags_result*
    *win_d1_r* *skel_lit_win*
    *win_d1_r* *win_d1_r*
    *address* *OPR_R*
    *exec_linear_r* *ext_addr_r*
    *sigma* *ea_partial_r*
    *ea_base* *ea_partial_r*
} {
    set paths [get_timing_paths -setup -from [get_registers $from] -to [get_keepers $to] -npaths 1]
    if {[get_collection_size $paths] == 0} continue
    report_timing -setup -from [get_registers $from] -to [get_keepers $to] -npaths 1 -detail full_path -append -file $f
}
project_close
