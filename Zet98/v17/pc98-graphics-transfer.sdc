# Bundled graphics transfers, not free-running single-cycle data paths.
#
# Address: GRAMADRb is held throughout GRAMRD/GRAMACK. SDRAMC samples the
# request in VIDCLK, passes it through lVIDREQ, then selects ST_VIDREAD before
# using the address. The address therefore precedes its enabled capture by
# more than 20 ns, including the least favorable 25/100 MHz phase.
#
# Data: SDRAMC writes VIDDAT0..3, then changes the vidend completion toggle.
# Two VIDCLK synchronizer stages precede registered VIDACKb. GRAPHSCR
# captures WDAT0..3 after ACK; the line RAM writes those pixel-clock registers
# on the next pixel edge. No new read can replace the data until the consumer
# releases GRAMRD and starts another request. The enabled WDAT capture follows
# synchronized completion, not the nearest arbitrary 100/25 MHz clock edges.
#
# Limit only these buses to 20 ns. The data bundle's hold requirement is
# supplied by the handshake: WDAT capture releases GRAMRD; the next pixel
# edge clears lVIDstb, and only the following edge can toggle a new VIDREQ.
# VIDDAT cannot change until that request crosses to SDRAMC and completes.
# Thus arbitrary adjacent memory/pixel edges are not enabled hold captures.
# Exclude hold only for this completed-data bundle; keep its setup bound,
# ordinary address hold checks, WDAT-to-line-RAM timing and all control paths.
# tests/run-video-sdram.sh checks >=20 ns before AND after each actual capture
# with 0/20/40 ns transport routes, six clock phases and six CPU rates. Both
# late arrival and a post-capture glitch must fail. See rtl/GRAPHICS_TRANSFER.md.
# CPU-written graphics configuration registers receive no exception here.
# Since graphics VRAM moved to block RAM (gvram_m10k), this SDRAM video port
# carries the text font: font_prefetch holds f_adr through FNTRD/FNTACK and
# captures the completed words in f_dat, exactly as GRAPHSCR did with
# GRAMADRb/WDAT (tests/run-font-prefetch.sh covers the handshake).
set graphics_address [get_registers {*|VID|TXT|*|f_adr*}]
set sdram_address [get_registers {*|ram|MEMADR*}]
set graphics_data [get_registers {*|ram|VIDDAT*}]
set graphics_capture [get_registers {*|VID|TXT|*|f_dat*}]
if {[get_collection_size $graphics_address] < 14 ||
    [get_collection_size $sdram_address] < 13 ||
    [get_collection_size $graphics_data] < 64 ||
    [get_collection_size $graphics_capture] < 64} {
    error "Expected the complete SDRAMC/font prefetch bundled address and data buses"
}
set_max_delay -from $graphics_address -to $sdram_address 20.000
set_max_delay -from $graphics_data -to $graphics_capture 20.000
set_false_path -hold -from $graphics_data -to $graphics_capture

# Only the input of each control synchronizer is asynchronous. The remaining
# stages, edge detection, completion comparison and ACK/BUFWE logic are timed.
set graphics_request [get_registers {*|ram|VIDREQ*}]
set graphics_request_meta [get_registers {*|ram|lVIDREQ[0]}]
# TimeQuest includes fitter-created ~DUPLICATE copies of an exact source
# register match. Each is the same completion source; all can feed the one
# first-stage synchronizer. Require that source to exist, not to be singular.
set graphics_done [get_registers {*|ram|vidend}]
set graphics_done_meta [get_registers {*|ram|VIDdone_sync[0]}]
if {[get_collection_size $graphics_request] < 1 ||
    [get_collection_size $graphics_request_meta] != 1 ||
    [get_collection_size $graphics_done] < 1 ||
    [get_collection_size $graphics_done_meta] != 1} {
    error "Expected both graphics control synchronizers"
}
set_false_path -from $graphics_request -to $graphics_request_meta
set_false_path -from $graphics_done -to $graphics_done_meta
