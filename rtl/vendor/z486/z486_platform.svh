`ifndef Z486_PLATFORM_SVH
`define Z486_PLATFORM_SVH

// Board builds select one vendor explicitly. Keep the legacy synthesis
// symbol used by Quartus as a compatibility input for MiSTer projects.
`ifdef ALTERA_RESERVED_QIS
`ifndef Z486_ALTERA
`define Z486_ALTERA
`endif
`endif

// Normalize legacy implementation switches to feature-oriented names.
`ifdef Z486_QUARTUS_M10K_UCODE
`define Z486_USE_ALTERA_UCODE_ROM
`endif

`ifdef Z486_QUARTUS_LOGIC_UCODE
`define Z486_USE_LOGIC_UCODE_ROM
`endif

`ifdef Z486_ALTERA_ALU
`define Z486_USE_ALTERA_ALU
`endif

`ifdef Z486_ALTERA
`ifndef Z486_USE_ALTERA_UCODE_ROM
`define Z486_USE_ALTERA_UCODE_ROM
`endif
`ifndef Z486_USE_ALTERA_ALU
`define Z486_USE_ALTERA_ALU
`endif
`define Z486_USE_ALTERA_MEMORY
`endif

// Synthesis intent. These macros must never change a visible cycle contract.
`ifdef Z486_XILINX
`define Z486_BLOCK_RAM             (* ram_style = "block" *)
`define Z486_BLOCK_RAM_NO_RW_CHECK (* ram_style = "block" *)
`define Z486_DISTRIBUTED_RAM       (* ram_style = "distributed" *)
`define Z486_KEEP                  (* keep = "true" *)
`define Z486_NO_PRUNE              (* dont_touch = "true" *)
`define Z486_REPLICATE             (* max_fanout = 32 *)
`elsif Z486_ALTERA
`define Z486_BLOCK_RAM             (* ramstyle = "M10K" *)
`define Z486_BLOCK_RAM_NO_RW_CHECK (* ramstyle = "M10K, no_rw_check" *)
`define Z486_DISTRIBUTED_RAM       (* ramstyle = "MLAB, no_rw_check" *)
`define Z486_KEEP                  (* preserve *)
`define Z486_NO_PRUNE              (* noprune *)
`define Z486_REPLICATE             (* syn_replicate = 1 *)
`else
`define Z486_BLOCK_RAM
`define Z486_BLOCK_RAM_NO_RW_CHECK
`define Z486_DISTRIBUTED_RAM
`define Z486_KEEP
`define Z486_NO_PRUNE
`define Z486_REPLICATE
`endif

// Optional replacement-table placement for the 32 KB instruction-cache build.
// Preserve read-during-write semantics; do not request no_rw_check here.
`ifdef Z486_ALTERA
`ifdef ZET98_Z486_PLRU_MLAB
`define Z486_PLRU_RAM (* ramstyle = "MLAB" *)
`else
`define Z486_PLRU_RAM
`endif
`else
`define Z486_PLRU_RAM
`endif

// L1 cache tag width in physical address bits (27 = 128 MiB); addresses that
// differ only above it share a line and must never be cached.
`ifndef Z486_L1_PHYS_ADDR_BITS
`define Z486_L1_PHYS_ADDR_BITS 27
`endif

`endif
