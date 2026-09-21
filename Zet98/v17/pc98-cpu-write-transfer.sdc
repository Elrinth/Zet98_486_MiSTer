# Static CPU/GRCG set/preserve data is captured with CPUREQ in CPUCLK.
# lCPUREQ admits CPUJOB and the payload on the third memory edge, at least
# 20 ns after launch. The source remains held until the CPU's next request,
# which cannot precede completion of this job. A 15 ns maximum gives at least
# 5 ns setup margin at admission without adding an SDRAM transaction cycle.
#
# Fresh RMW plane data is combined only after this capture, entirely in
# memclk. This exception therefore does not relax the live read/modify/write
# operation or any CPU request, acknowledgement, address or reset path.
# tests/run-sdram-write-bundle.sh injects 15 ns transport delay and checks
# capture stability, data, masks and request counts over 24 clock/phase pairs.
# Its deliberately late 80 ns bundle must fail. Normal hold checks remain.
set cpu_write_source [get_registers {*|ram|cpu_write_source*}]
set cpu_write_memory [get_registers {*|ram|cpu_write_memory*}]
if {[get_collection_size $cpu_write_source] < 80 ||
    [get_collection_size $cpu_write_memory] < 80} {
    error "Expected complete 80-bit CPU write set/preserve bundle endpoints"
}
set_max_delay -from $cpu_write_source -to $cpu_write_memory 15.000
