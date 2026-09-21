# Only the asynchronous reset inputs of the reset-release synchronizers are
# excepted. Stage-to-stage paths and synchronizer outputs to real logic retain
# normal setup, hold, recovery and removal checks.
set reset_loader [get_registers {emu|ldr_done}]
set reset_video_stages [get_registers {*|video_reset|stages*}]
set reset_video_release [get_registers {*|video_reset|stages[1]}]
set reset_pixel_stages [get_registers {*|VID|pixel_reset|stages*}]
if {[get_collection_size $reset_loader] != 1 ||
    [get_collection_size $reset_video_stages] != 2 ||
    [get_collection_size $reset_video_release] != 1 ||
    [get_collection_size $reset_pixel_stages] != 2} {
    error "Expected the loader/video/pixel reset-release chains"
}
set_false_path -from $reset_loader -to $reset_video_stages
set_false_path -from $reset_video_release -to $reset_pixel_stages
