# One CPU-written display-page bit (pc98_display_page) enters a two-stage
# pixel-clock chain in the block-RAM graphics VRAM (gvram_m10k). The second
# stage and the display read address it selects are normally timed.
set page_meta [get_registers {*|gvram|page_sync[0]}]
set page_resolved [get_registers {*|gvram|page_sync[1]}]
if {[get_collection_size $page_meta] != 1 ||
    [get_collection_size $page_resolved] < 1} {
    error "Expected both graphics VRAM display-page synchronizer stages"
}
set_false_path -to $page_meta
set page_reset_clear [get_pins -compatibility_mode {*|gvram_video_reset|stages*|clrn}]
if {[get_collection_size $page_reset_clear] != 2} {
    error "Expected both graphics VRAM display reset synchronizer CLRN pins"
}
set_false_path -to $page_reset_clear
