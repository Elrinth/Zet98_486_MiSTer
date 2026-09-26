// Synchronous x87 control store. The generated image is the source
// of truth; simulation and Quartus consume equivalent generated forms.
`include "z486_platform.svh"
module x87_ucode_rom
    import x87_ucode_pkg::*;
(
    input  logic          clk,
    input  logic    [7:0] address, // Address captured for the next execution cycle.
    output x87_uop_t      uop      // 64-bit horizontal microinstruction.
);

logic [63:0] raw_uop;
assign uop = x87_uop_t'(raw_uop);

`ifdef Z486_XILINX

// Keep the dense image in block RAM. Vivado otherwise recognizes the sparse
// case function below as logic and implements this 16 Kibit control store in
// thousands of LUTs.
`Z486_BLOCK_RAM logic [63:0] control_store [0:255];
initial $readmemh("x87_ucode.mem", control_store);

always_ff @(posedge clk)
    raw_uop <= control_store[address];

`elsif Z486_USE_ALTERA_MEMORY

altsyncram #(
    .operation_mode("ROM"),
    .width_a(64),
    .widthad_a(8),
    .numwords_a(256),
    // M10K captures the address on clock0. Keep q unregistered so the ROM
    // latency matches the one-cycle behavioral model and sequencer contract.
    .outdata_reg_a("UNREGISTERED"),
    .address_aclr_a("NONE"),
    .outdata_aclr_a("NONE"),
    .init_file("x87_ucode.mif"),
    .ram_block_type("M10K"),
    .intended_device_family("Cyclone V"),
    .lpm_type("altsyncram")
) control_store (
    .address_a(address),
    .clock0(clk),
    .clocken0(1'b1),
    .q_a(raw_uop),
    .aclr0(1'b0),
    .addressstall_a(1'b0),
    .clocken1(1'b1),
    .clocken2(1'b1),
    .clocken3(1'b1),
    .rden_a(1'b1),
    .eccstatus()
);

`else

`include "x87_ucode.svh"

always_ff @(posedge clk)
    raw_uop <= x87_ucode_word(address);

`endif

endmodule
