# CPU palette snapshot held until video acknowledges receipt. The request
# traverses two video-clock synchronizer stages before enabled capture on
# the third edge. With video at 75 MHz this gives >=26.66 ns from launch to
# capture. A 20 ns payload bound retains >=6.66 ns of settling time.
# CPU writes during a transfer dirty a later snapshot; they do not change
# this held payload. The return toggle prevents premature reuse.
# Tests exercise all CPU clock ratios/phases with 20 ns transport delay;
# 60 ns payload and live unsampled palette negative controls must fail.
set palette_payload [get_registers {*|pal|*palette_hold*}]
set palette_capture [get_registers {*|pal|PAL_VIDEO* *|pal|C8_VIDEO* *|pal|COLOR_VIDEO}]
if {[get_collection_size $palette_payload] < 217 ||
    [get_collection_size $palette_capture] < 217} {
    error "Expected the complete 217-bit palette snapshot and video capture"
}
set_max_delay -from $palette_payload -to $palette_capture 20.000

# Only the input of each control synchronizer is asynchronous. Subsequent
# stages, the request/ack comparisons and pixel lookup remain normally timed.
set palette_request [get_registers {*|pal|*palette_request}]
set palette_request_meta [get_registers {*|pal|*request_sync[0]}]
set palette_ack [get_registers {*|pal|*palette_ack}]
set palette_ack_meta [get_registers {*|pal|*ack_sync[0]}]
if {[get_collection_size $palette_request] < 1 ||
    [get_collection_size $palette_request_meta] != 1 ||
    [get_collection_size $palette_ack] < 1 ||
    [get_collection_size $palette_ack_meta] != 1} {
    error "Expected both palette transfer control synchronizers"
}
set_false_path -from $palette_request -to $palette_request_meta
set_false_path -from $palette_ack -to $palette_ack_meta

# The CPU/loader reset only enters the asynchronous clear pins of this local
# release synchronizer. Do not cut its D inputs or its output to real logic.
# Pin names and compatibility-mode matching were checked on the same fitted
# reset_release primitive used elsewhere in this design.
set palette_reset_clear [get_pins -compatibility_mode {*|pal|*palette_reset|stages*|clrn}]
if {[get_collection_size $palette_reset_clear] != 2} {
    error "Expected exactly two palette reset synchronizer clear pins"
}
set_false_path -to $palette_reset_clear
