# One CPU-written display-page bit enters a two-stage memory-clock chain.
# The second stage and its SDRAM row-address consumers are normally timed.
set page_source [get_registers {*|graphgdc|r_VRAMSEL}]
set page_meta [get_registers {*|display_address|page_sync[0]}]
set page_resolved [get_registers {*|display_address|page_sync[1]}]
if {[get_collection_size $page_source] < 1 ||
    [get_collection_size $page_meta] != 1 ||
    [get_collection_size $page_resolved] < 1} {
    error "Expected the display-page source and both memory-clock stages"
}
set_false_path -from $page_source -to $page_meta
set page_reset_clear [get_pins -compatibility_mode {*|display_address|display_page_reset|stages*|clrn}]
if {[get_collection_size $page_reset_clear] != 2} {
    error "Expected both display-page reset synchronizer CLRN pins"
}
set_false_path -to $page_reset_clear
