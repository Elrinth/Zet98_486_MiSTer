# GDC configuration is held in the CPU domain until copied after a two-stage
# request synchronizer in the 75 MHz video domain. Minimum launch-to-capture
# interval is 26.66 ns; bound the coherent payload to 20 ns. See the actual
# delayed-payload/early-capture regressions in tests/run-video-settings.sh.
set settings_payload [get_registers {*|gdc_settings|held_data*}]
set settings_capture [get_registers {*|gdc_settings|received_data*}]
if {[get_collection_size $settings_payload] < 121 ||
    [get_collection_size $settings_capture] < 121} {
    error "Expected the complete 121-bit GDC settings snapshot"
}
set_max_delay -from $settings_payload -to $settings_capture 20.000
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
foreach reset {cpu_reset video_reset} {
    set clears [get_pins -compatibility_mode "*|gdc_settings|${reset}|stages*|clrn"]
    if {[get_collection_size $clears] != 2} {
        error "Expected two GDC settings reset synchronizer CLRN pins: $reset"
    }
    set_false_path -to $clears
}
