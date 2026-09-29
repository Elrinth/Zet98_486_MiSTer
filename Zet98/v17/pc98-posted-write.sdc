# Posted CPU word writes (SDRAMC POSTED_WRITE_BITS): a dual-clock FIFO from
# CPUCLK to memclk. Pointers cross as Gray code through two-stage
# synchronizers; bound their skew to less than one destination period
# instead of cutting the paths. An entry is written on the CPU edge that
# advances the write pointer and is read by the memory side only after that
# pointer has crossed both memclk stages (>= 20 ns at 100 MHz), so its route
# gets the same 15 ns bound as the held CPU request bundle. Hold is not a
# protocol relationship for these entries; every other path stays timed.
set pw_entries [get_registers -nowarn {*|ram|pw_fifo*}]
set pw_wgray [get_registers -nowarn {*|ram|pw_wgray[*]}]
set pw_rgray [get_registers -nowarn {*|ram|pw_rgray[*]}]
set pw_wgray_mem0 [get_registers -nowarn {*|ram|pw_wgray_mem0[*]}]
set pw_rgray_cpu0 [get_registers -nowarn {*|ram|pw_rgray_cpu0[*]}]
if {[get_collection_size $pw_entries] > 0} {
    if {[get_collection_size $pw_wgray] == 0 || [get_collection_size $pw_wgray_mem0] == 0 ||
        [get_collection_size $pw_rgray] == 0 || [get_collection_size $pw_rgray_cpu0] == 0} {
        error "Posted-write FIFO present without its pointer synchronizers"
    }
    post_message "Posted-write FIFO: [get_collection_size $pw_entries] entry bits"
    set_max_delay -from $pw_wgray -to $pw_wgray_mem0 8.000
    set_false_path -hold -from $pw_wgray -to $pw_wgray_mem0
    set_max_delay -from $pw_rgray -to $pw_rgray_cpu0 8.000
    set_false_path -hold -from $pw_rgray -to $pw_rgray_cpu0
    set_max_delay -from $pw_entries 15.000
    set_false_path -hold -from $pw_entries
}
