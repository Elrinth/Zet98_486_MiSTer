# Bundled graphics transfers, not free-running single-cycle data paths.
#
# Address: GRAMADRb is held throughout GRAMRD/GRAMACK. SDRAMC samples the
# request in VIDCLK, passes it through lVIDREQ, then selects ST_VIDREAD before
# using the address. The address therefore precedes its enabled capture by
# more than 20 ns, including the least favorable 25/100 MHz phase.
#
# Data: SDRAMC writes VIDDAT0..3, then changes the vidend completion toggle.
# Two VIDCLK synchronizer stages precede registered VIDACKb. GRAPHSCR
# registers BUFWE after ACK; the line RAM writes on the next
# pixel edge. No new read can replace the data until the consumer releases
# GRAMRD and starts another request. The enabled write is at least two pixel
# edges after completion, not the nearest arbitrary 100/25 MHz clock edges.
#
# Limit only these buses to 20 ns; retain normal hold checks and every control
# path. tests/run-video-sdram.sh exercises the real producer/consumer with
# 20 ns transport delays, per-plane/order/count checks and >=20 ns of capture
# margin. A late-data negative control must fail. This is not a global CDC
# false path and does not relax CPU-written graphics configuration registers.
set graphics_address [get_registers {*|VID|GRP|GRAMADRb*}]
set sdram_address [get_registers {*|ram|MEMADR*}]
set graphics_data [get_registers {*|ram|VIDDAT*}]
set graphics_line_data [get_registers {*|VID|GRP|buf*|*porta_datain_reg*}]
if {[get_collection_size $graphics_address] < 14 ||
    [get_collection_size $sdram_address] < 13 ||
    [get_collection_size $graphics_data] < 64 ||
    [get_collection_size $graphics_line_data] < 64} {
    error "Expected the complete SDRAMC/GRAPHSCR bundled address and data buses"
}
set_max_delay -from $graphics_address -to $sdram_address 20.000
set_max_delay -from $graphics_data -to $graphics_line_data 20.000

# Only the input of each control synchronizer is asynchronous. The remaining
# stages, edge detection, completion comparison and ACK/BUFWE logic are timed.
set graphics_request [get_registers {*|ram|VIDREQ*}]
set graphics_request_meta [get_registers {*|ram|lVIDREQ[0]}]
set graphics_done [get_registers {*|ram|vidend}]
set graphics_done_meta [get_registers {*|ram|VIDdone_sync[0]}]
if {[get_collection_size $graphics_request] < 1 ||
    [get_collection_size $graphics_request_meta] != 1 ||
    [get_collection_size $graphics_done] != 1 ||
    [get_collection_size $graphics_done_meta] != 1} {
    error "Expected both graphics control synchronizers"
}
set_false_path -from $graphics_request -to $graphics_request_meta
set_false_path -from $graphics_done -to $graphics_done_meta
