# One CPU-written 480-line mode bit enters a two-stage video-clock chain.
# The second stage and CRTC98's staging registers are normally timed.
set lines_source [get_registers {*|textgdc|r_LINES480}]
set lines_meta [get_registers {*|lines480_sync_inst|lines480_sync[0]}]
if {[get_collection_size $lines_source] != 1 ||
    [get_collection_size $lines_meta] != 1} {
    error "Expected the 480-line source and its first video-clock stage"
}
set_false_path -from $lines_source -to $lines_meta
