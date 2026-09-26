# Packed line address/bank/page-wrap is held from video request until CPU ACK.
# CPU sees a two-flop request synchronizer before sampling the18-bit command.
# Keep payload setup AND hold checks, with explicit maximum/minimum delay.
# Only first-stage controls and reset-chain asynchronous inputs are excluded.
set pegc_request [get_registers {*|packed_fetch|request_payload*}]
set pegc_capture [get_registers {*|packed_fetch|next_address* *|packed_fetch|write_bank *|packed_fetch|wrap_page}]
set pegc_present [dict create]
foreach_in_collection reg $pegc_request {
    set name [get_node_info $reg -name]
    if {[regexp {request_payload\[([0-9]+)\]} $name unused bit]} {dict set pegc_present $bit 1}
}
# Raster starts are SAD*16 bytes and pitches are multiples of16 bytes.
# Thus payload[0] (64-bit word bit0) and next_address[3] can be folded to0.
# Bound them if preserved; require every other live bit even after replication.
for {set bit 1} {$bit<18} {incr bit} {
    if {![info exists pegc_present] || ![dict exists $pegc_present $bit]} {error "Missing PEGC request bit $bit"}
}
set pegc_dest [dict create]
foreach_in_collection reg $pegc_capture {
    set name [get_node_info $reg -name]
    if {[regexp {next_address\[([0-9]+)\]} $name unused bit]} {dict set pegc_dest $bit 1}
    foreach flag {write_bank wrap_page} {if {[string match "*|$flag*" $name]} {dict set pegc_dest $flag 1}}
}
foreach field {4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 write_bank wrap_page} {
    if {![dict exists $pegc_dest $field]} {error "Missing PEGC capture $field"}
}
set_max_delay -from $pegc_request -to $pegc_capture 20.000
set_min_delay -from $pegc_request -to $pegc_capture 0.500
foreach {source first_stage} {
    {*|packed_fetch|request_toggle} {*|packed_fetch|request_sync[0]}
    {*|packed_fetch|acknowledge_toggle} {*|packed_fetch|acknowledge_sync[0]}
} {
    set launch [get_registers $source]
    set capture [get_registers $first_stage]
    if {[get_collection_size $launch]<1 || [get_collection_size $capture]!=1} {error "Missing PEGC control synchronizer $source"}
    set_false_path -from $launch -to $capture
}
# Only asynchronous inputs of the two reset-release chains are asynchronous.
# Stage-to-stage, released-reset fanout and all payload paths retain timing.
foreach reset_chain {cpu_reset_sync video_reset_sync} {
    set clears [get_pins -compatibility_mode "*|packed_fetch|${reset_chain}*|clrn"]
    if {[get_collection_size $clears]!=2} {error "Missing PEGC reset chain $reset_chain"}
    set_false_path -to $clears
}
