// Synchronous lookup ROM shared by FYL2X and F2XM1. Each word returns the
// selected Q52 sample and its precomputed delta to the successor. Address
// ranges 0/256/512 select log2/exp2/exp2(-x); 768 and 769 are exp2 endpoints.
`include "z486_platform.svh"
module x87_logexp_rom (
    input  logic         clk,
    input  logic   [9:0] address,
    output logic  [99:0] q
);

`ifdef Z486_USE_ALTERA_MEMORY

altsyncram #(
    .operation_mode("ROM"),
    .width_a(100),
    .widthad_a(10),
    .numwords_a(770),
    .outdata_reg_a("UNREGISTERED"),
    .address_aclr_a("NONE"),
    .outdata_aclr_a("NONE"),
    .init_file("x87_logexp_tables.mif"),
    .ram_block_type("M10K"),
    .intended_device_family("Cyclone V"),
    .lpm_type("altsyncram")
) logexp_rom (
    .address_a(address),
    .clock0(clk),
    .clocken0(1'b1),
    .q_a(q),
    .aclr0(1'b0),
    .addressstall_a(1'b0),
    .clocken1(1'b1),
    .clocken2(1'b1),
    .clocken3(1'b1),
    .rden_a(1'b1),
    .eccstatus()
);

`else

`include "x87_logexp_tables.svh"

always_ff @(posedge clk) begin
    q <= x87_logexp_q52(address);
end

`endif

endmodule
