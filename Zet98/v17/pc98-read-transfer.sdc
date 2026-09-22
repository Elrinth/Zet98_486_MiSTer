# Completed CPU/GDC reads are held in memclk until a later request.
# Single-word data is captured when lclkcount=6 (current count 7), and
# cpuend/subend is asserted at count 8. Four-word data finishes at current
# count 10, with completion at 11. Thus the last data transition precedes
# completion by >=10ns (one 100MHz memory cycle); the CPU samples afterward.
# RMW operations complete later still. Completion now crosses two source-clock
# synchronizer stages before data and ACK are captured on the SAME edge.
# The additional settling time is not used to loosen this 5 ns data bound.
#
# Bound just this held return-data route to 5ns, leaving >=5ns of settling
# before capture. Keep ordinary hold checks and all control/ACK/RMW paths.
# tests/run-sdram-read-bundle.sh injects 5ns and checks 5ns stability over
# six CPU rates and 24 memory phases for both ports; 80ns must fail.
# Unused upper plane outputs can disappear; require at least one 16-bit word.
foreach port {cpu sub} {
    set read_source [get_registers "*|ram|${port}_read_words*"]
    set read_target [get_registers "*|ram|[string toupper $port]RDAT*"]
    if {[get_collection_size $read_source] < 16 || [get_collection_size $read_target] < 16} {
        error "Expected completed $port read source and capture registers"
    }
    set_max_delay -from $read_source -to $read_target 5.000
}

# Floppy return words are likewise held until the following request. Data is
# captured only when a busy request's completion has crossed both synchronizer
# stages, on the same edge that drops WAIT. Bound only the sixteen held bits;
# do not exclude ACK/WAIT, inter-stage or downstream capture paths.
# tests/run-floppy-read-bundle.sh verifies 5ns transport plus 5ns settling.
foreach port {fde fec} {
    set read_source [get_registers "*|ram|${port}_read_data*"]
    set read_target [get_registers "*|ram|[string toupper $port]RDAT*"]
    if {[get_collection_size $read_source] != 16 || [get_collection_size $read_target] != 16} {
        error "Expected one held sixteen-bit $port read word and capture register"
    }
    set_max_delay -from $read_source -to $read_target 5.000
}
