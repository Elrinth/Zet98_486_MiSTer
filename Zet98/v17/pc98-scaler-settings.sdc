# The host's two scaler-mode bits use the same held snapshot contract as the
# GDC settings: capture follows two synchronizer stages in 75 MHz input video.
set scaler_payload [get_registers {scaler_settings|held_data*}]
set scaler_capture [get_registers {scaler_settings|received_data*}]
if {[get_collection_size $scaler_payload] != 2 ||
    [get_collection_size $scaler_capture] != 2} {
    error "Expected two held and two captured scaler-mode bits"
}
set_max_delay -from $scaler_payload -to $scaler_capture 20.000
foreach {source first_stage} {
    {scaler_settings|request_toggle} {scaler_settings|request_sync[0]}
    {scaler_settings|ack_toggle} {scaler_settings|ack_sync[0]}
} {
    set launch [get_registers $source]
    set capture [get_registers $first_stage]
    if {[get_collection_size $launch] < 1 || [get_collection_size $capture] != 1} {
        error "Expected the scaler settings control synchronizer: $source"
    }
    set_false_path -from $launch -to $capture
}
foreach reset {settings_cpu_reset settings_video_reset} {
    set clears [get_pins -compatibility_mode "scaler_settings|${reset}|stages*|clrn"]
    if {[get_collection_size $clears] != 2} {
        error "Expected two scaler settings reset synchronizer CLRN pins: $reset"
    }
    set_false_path -to $clears
}
