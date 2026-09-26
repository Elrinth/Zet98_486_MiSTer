# GDC configuration is held in the CPU domain until copied after a two-stage
# request synchronizer in the 75 MHz video domain. Minimum launch-to-capture
# interval is 26.66 ns; bound the coherent payload to 20 ns. See the actual
# delayed-payload/early-capture regressions in tests/run-video-settings.sh.
set settings_payload [get_registers {*|gdc_settings|held_data*}]
set settings_capture [get_registers {*|gdc_settings|received_data*}]
# Packed raster consumes both partition lengths, including bits95..104.
# Check every consumed bit, including new packed-mode/base/page/clock fields;
# aggregate counts alone could be satisfied by replicated registers.
foreach bank [list $settings_payload $settings_capture] {
    set present [dict create]
    foreach_in_collection reg $bank {
        set name [get_node_info $reg -name]
        if {[regexp {(held_data|received_data)\[([0-9]+)\]} $name unused field bit]} {
            dict set present $bit 1
        }
    }
    set settings_width [expr {$pegc_enabled ? 128 : 122}]
    for {set bit 0} {$bit < $settings_width} {incr bit} {
        if {!$pegc_enabled && $bit>=95 && $bit<=104} {continue}
        if {![dict exists $present $bit]} {
            error "Missing consumed GDC settings snapshot bit $bit"
        }
    }
}
set_max_delay -from $settings_payload -to $settings_capture 20.000
# Capture is enabled only after the synchronized request. The receiving edge
# sends ACK; two CPU synchronizer stages must return it before held_data can
# change (at least two CPU periods, 20 ns at the tested 100 MHz maximum).
# An unrelated near-coincident CPU/video edge is therefore not a hold launch.
# Keep the 20 ns setup bound; exclude only that impossible payload hold check.
set_false_path -hold -from $settings_payload -to $settings_capture
foreach {source first_stage} {
    {*|gdc_settings|request_toggle} {*|gdc_settings|request_sync[0]}
    {*|gdc_settings|ack_toggle} {*|gdc_settings|ack_sync[0]}
} {
    set launch [get_registers $source]
    set capture [get_registers $first_stage]
    if {[get_collection_size $launch] < 1 || [get_collection_size $capture] != 1} {
        error "Expected the GDC settings control synchronizer: $source"
    }
    set_false_path -from $launch -to $capture
}
foreach reset {settings_cpu_reset settings_video_reset} {
    set clears [get_pins -compatibility_mode "*|gdc_settings|${reset}|stages*|clrn"]
    if {[get_collection_size $clears] != 2} {
        error "Expected two GDC settings reset synchronizer CLRN pins: $reset"
    }
    set_false_path -to $clears
}
