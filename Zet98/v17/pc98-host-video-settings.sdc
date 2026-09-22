# Coherent host snapshots. A request traverses two destination flops before
# capture (at least two destination periods); its acknowledgement traverses
# two source flops before held_data can change again. Target clocks are 75 MHz
# input video and 148.5 MHz HDMI. A 5 ns payload limit leaves >8 ns settling
# margin at HDMI. No payload setup check or downstream arithmetic is waived.
foreach instance {
    vga_osd|host_osd_settings
    hdmi_osd|host_osd_settings
    host_viewport_settings
    emu|hdmi_scale|host_scale_settings
} {
    set payload [get_registers "${instance}|held_data*"]
    set capture [get_registers "${instance}|video_data*"]
    # Constant and unused bits may be removed. Both sets must exist and every
    # remaining bit in these named bundles receives the same path constraint.
    if {[get_collection_size $payload] == 0 || [get_collection_size $capture] == 0} {
        error "Missing held/captured host video snapshot: $instance"
    }
    post_message "Host video snapshot $instance: [get_collection_size $payload] held, [get_collection_size $capture] captured bits"
    set_max_delay -from $payload -to $capture 5.000
    # The source holds through capture until a round trip of the ack. Checking
    # the unrelated nominal clock-edge hold relationship is not the protocol.
    set_false_path -hold -from $payload -to $capture
    foreach {launch_name first_name} {
        request {request_sync[0]}
        acknowledge {acknowledge_sync[0]}
    } {
        set launch [get_registers "${instance}|${launch_name}"]
        set first [get_registers "${instance}|${first_name}"]
        if {[get_collection_size $launch] != 1 || [get_collection_size $first] != 1} {
            error "Missing host snapshot control synchronizer: $instance / $launch_name"
        }
        set_false_path -from $launch -to $first
    }
}

# Independently synchronized one-bit controls. Only the first destination
# stage is asynchronous; the next stage and every consumer remain timed.
foreach first_name {{emu|video_out|test_meta} {tune_gate|enable_video[0]}} {
    set first [get_registers $first_name]
    if {[get_collection_size $first] != 1} {
        error "Missing first-stage video control synchronizer: $first_name"
    }
    set_false_path -to $first
}
