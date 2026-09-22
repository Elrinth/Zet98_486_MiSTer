# Long-lived video levels enter two-flop synchronizers. Only the first stage
# is asynchronous; every inter-stage path and functional consumer stays timed.
set hdmi_first [get_registers {hdmi_vs_meta}]
set hdmi_second [get_registers {hdmi_vs_sync}]
set hdmi_source [get_registers {hdmi_out_vs*}]
if {[get_collection_size $hdmi_first] != 1 || [get_collection_size $hdmi_second] != 1 || [get_collection_size $hdmi_source] < 1} {
    error "Expected HDMI vertical-sync launch and two unique synchronizer stages"
}
set_false_path -from $hdmi_source -to $hdmi_first

set retrace_source [get_registers {*|retrace_status|source_status*}]
set retrace_first [get_registers {*|retrace_status|status_meta*}]
set retrace_second [get_registers {*|retrace_status|status_sync*}]
if {[get_collection_size $retrace_source] != 2 || [get_collection_size $retrace_first] != 2 || [get_collection_size $retrace_second] != 2} {
    error "Expected two independent retrace levels with two synchronizer stages"
}
set_false_path -from $retrace_source -to $retrace_first
