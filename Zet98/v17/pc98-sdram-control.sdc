# CPU/drawing requests and all four completion channels are held toggles.
# First-stage flops have no functional consumers other than stage two.
# CPU/drawing admission compares request stages two/three; completion and
# returned words are consumed only after the two return synchronizer stages.
# Keep every inter-stage path and every destination consumer normally timed.
foreach port {CPU SUB FDE FEC} {
    foreach suffix [list "l${port}REQ\[0\]" "${port}done_sync\[0\]"] {
        set first [get_registers "*|ram|$suffix"]
        if {[get_collection_size $first] != 1} {
            error "Expected one first-stage SDRAM control register: $suffix"
        }
        set_false_path -to $first
    }
    # Operation type is captured with the request and held through completion.
    # Admission is on memory edge three, >=20 ns after source acceptance at
    # 100 MHz. The 15 ns route bound leaves >=5 ns setup; hold stays checked.
    set source [get_registers "*|ram|n${port}JOB*"]
    set destination [get_registers "*|ram|${port}JOB*"]
    if {[get_collection_size $source] == 0 || [get_collection_size $destination] == 0} {
        error "Missing held SDRAM operation endpoints: $port"
    }
    post_message "SDRAM $port operation: [get_collection_size $source] held, [get_collection_size $destination] captured registers"
    set_max_delay -from $source -to $destination 15.000
}
