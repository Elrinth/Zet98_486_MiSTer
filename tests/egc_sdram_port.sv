// Test-only wiring around the production SDRAMC synthesized by GHDL.
// Keep its bidirectional DQ port on a resolved Verilog net. GHDL 4.1's
// nested VHDL inout wrapper emits a one-way assignment and loses read data.
module egc_sdram_port (
    input wire cpuclk, memclk, reset, read4, rmw4,
    input wire [21:0] address,
    input wire [1:0] bank, bytes,
    input wire [3:0] planes,
    input wire [63:0] base_words, xor_masks,
    output wire [63:0] read_words,
    output wire ack, ready, cke, cs, ras, cas, we,
    output wire [1:0] dqm, ba,
    output wire [12:0] ma,
    inout wire [15:0] dq
);
    SDRAMC ram (
        .PMEMCKE(cke),.PMEMCS_N(cs),.PMEMRAS_N(ras),.PMEMCAS_N(cas),.PMEMWE_N(we),
        .PMEMUDQ(dqm[1]),.PMEMLDQ(dqm[0]),.PMEMBA1(ba[1]),.PMEMBA0(ba[0]),.PMEMADR(ma),.PMEMDAT(dq),
        .CPUBNK(bank),.CPUADR(address),.CPUBSEL(bytes),.CPUPSEL(planes),
        .CPUWDAT0(base_words[15:0]),.CPUWDAT1(base_words[31:16]),
        .CPUWDAT2(base_words[47:32]),.CPUWDAT3(base_words[63:48]),.CPUPRESERVE(16'b0),
        .CPURDAT0(read_words[15:0]),.CPURDAT1(read_words[31:16]),
        .CPURDAT2(read_words[47:32]),.CPURDAT3(read_words[63:48]),
        .CPUWR1(1'b0),.CPUWR4(1'b0),.CPURD1(1'b0),.CPURD4(read4),.CPURMW1(1'b0),.CPURMW4(rmw4),
        .CPUAFFINE(1'b1),.CPUXORMASK(xor_masks),.CPUACK(ack),.CPUCLK(cpuclk),
        .SUBBNK(2'b0),.SUBADR(22'b0),.SUBBSEL(2'b0),.SUBPSEL(4'b0),
        .SUBWDAT0(16'b0),.SUBWDAT1(16'b0),.SUBWDAT2(16'b0),.SUBWDAT3(16'b0),.SUBPRESERVE(16'b0),
        .SUBWR1(1'b0),.SUBWR4(1'b0),.SUBRD1(1'b0),.SUBRD4(1'b0),.SUBRMW1(1'b0),.SUBRMW4(1'b0),.SUBCLK(cpuclk),
        .VIDBNK(2'b0),.VIDADR(22'b0),.VIDRD(1'b0),.VIDCLK(cpuclk),
        .FDEADR(24'b0),.FDERD(1'b0),.FDEWR(1'b0),.FDEWDAT(16'b0),.FDECLK(cpuclk),
        .FECADR(24'b0),.FECRD(1'b0),.FECWR(1'b0),.FECWDAT(16'b0),.FECCLK(cpuclk),
        .mem_inidone(ready),.memclk(memclk),.rstn(~reset)
    );
endmodule
