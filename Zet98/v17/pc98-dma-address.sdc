# DMA memory address into the SDRAM controller's CPU-port request capture.
#
# The 8237 selects the active channel (ACTCH) and that channel's current
# address (CURADDR) at least two CPU clocks before the same channel raises
# MEMRD/MEMWR: the channel's BUSREQ selects ACTCH on the next edge, DMASW
# registers DMAen (BUSACK) from BUSREQ, and the channel only asserts the
# memory strobe on the edge after it sees BUSACK in WAITBUS. CURADDR changes
# on the edge after the strobe is cleared (ADDRINC) and the next strobe needs
# TRANS6/NEXT/WAITBUS first. ACTCH returns to 4 only after the strobe is low.
# SDRAMC samples CPUADR/CPUBNK/CPUBSEL/CPUPSEL only with an asserted request,
# so these held-address arcs have two clocks. The strobe arcs from the
# channel FSMs (CHMEMRD/CHMEMWR) and DMAen are not covered and stay
# single-cycle; an ACTCH change never toggles the selected strobe.
set dma_address_source [get_registers {*|DMA|ACTCH* *|DMA|DMA?|CURADDR*}]
set dma_address_capture [get_registers {*|ram|lCPUADR* *|ram|lCPUBNK* *|ram|lCPUBSEL* *|ram|lCPUPSEL* *|ram|cpu_write_source* *|ram|pw_fifo* *|ram|lcpustb* *|ram|nCPUJOB* *|ram|CPUREQ* *|ram|pw_wbin* *|ram|pw_wgray* *|ram|pw_ack*}]
if {[get_collection_size $dma_address_source] < 10 ||
    [get_collection_size $dma_address_capture] < 40} {
    error "Expected DMA address sources and SDRAMC CPU request capture registers"
}
set_multicycle_path -setup 2 -from $dma_address_source -to $dma_address_capture
set_multicycle_path -hold 1 -from $dma_address_source -to $dma_address_capture
