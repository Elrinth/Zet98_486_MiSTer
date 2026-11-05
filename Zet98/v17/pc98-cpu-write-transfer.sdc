# CPU/GRCG address, bank, masks and set/preserve data are captured with
# CPUREQ in CPUCLK (110 bits at the current 22-bit address width).
# Optional CPU_AFFINE_RMW adds 65 held coefficient/mode bits to the same
# source/admission vectors. The wildcard covers those bits when enabled;
# the ordinary core leaves that generic disabled and they can optimize away.
# lCPUREQ admits CPUJOB and the payload on the third memory edge, at least
# 20 ns after launch. The source remains held until the CPU's next request,
# which cannot precede completion of this job. A 15 ns maximum gives at least
# 5 ns setup margin at admission without adding an SDRAM transaction cycle.
#
# Fresh RMW plane data is combined only after this capture, entirely in
# memclk. This exception therefore does not relax the live read/modify/write
# operation or any CPU request, acknowledgement or reset path. Only the
# held address/data payload receives this bound; memory-side paths stay timed.
# tests/run-sdram-write-bundle.sh injects 15 ns transport delay and checks
# capture stability, data, masks and request counts over 24 clock/phase pairs.
# Its deliberately late 80 ns bundle must fail. Normal hold checks remain.
set cpu_write_source [get_registers {*|ram|cpu_write_source*}]
set cpu_write_memory [get_registers {*|ram|cpu_write_memory*}]
# Since graphics VRAM moved to block RAM, the CPU port carries main memory,
# loader and font reads only: one data word, so about 42 live bundle bits.
if {[get_collection_size $cpu_write_source] < 40 ||
    [get_collection_size $cpu_write_memory] < 40} {
    error "Expected CPU request bundle endpoints (at least 40 address/data bits; constant bits may be optimized)"
}
set_max_delay -from $cpu_write_source -to $cpu_write_memory 15.000

# The independent GDC drawing port now uses the same held-data protocol.
# Address, bank, byte/plane enables and set/preserve data travel together.
# Its source is captured with SUBREQ and admitted with SUBJOB, never on a
# live GRCG read result. tests/run-sub-write-bundle.sh checks both deadlines.
# Unused since graphics VRAM moved to block RAM (tied off; partly optimized away).
set sub_write_source [get_registers -nowarn {*|ram|sub_write_source*}]
set sub_write_memory [get_registers -nowarn {*|ram|sub_write_memory*}]
if {[get_collection_size $sub_write_source] > 0} {
    set_max_delay -from $sub_write_source -to $sub_write_memory 15.000
}

# Floppy buffer address/data use independent source and admission registers.
# Their 40-bit payloads (22-bit word address, bank, data) share the same
# three-stage request deadline; controls and return data stay normally timed.
foreach port {fde fec} {
    set source [get_registers "*|ram|${port}_request_source*"]
    set destination [get_registers "*|ram|${port}_request_memory*"]
    if {[get_collection_size $source] < 40 || [get_collection_size $destination] < 40} {
        error "Expected complete 40-bit $port request bundle endpoints"
    }
    set_max_delay -from $source -to $destination 15.000
}
