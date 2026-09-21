// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Read-through, write-through cache for fixed RAM below 80000h only.
// Each entry holds one complete 16-bit word. CPU writes invalidate their slot;
// DMA and writes through aliased bank windows invalidate all slots. No dirty
// data is retained. VRAM, ROM, I/O and banked windows always use the legacy bus.
module pc98_lowmem_cache #(
    parameter INDEX_BITS = 12
) (
    input wire clk, reset, invalidate,
    input wire [19:1] address,
    input wire [1:0] select,
    input wire write, io, strobe,
    output wire legacy_strobe,
    input wire legacy_ack,
    input wire [15:0] legacy_readdata,
    output wire ack,
    output wire [15:0] readdata
);
    localparam TAG_BITS = 18 - INDEX_BITS;
    localparam IDLE=0, CHECK=1, MISS=2, HIT=3;
    reg [1:0] state;
    reg [(1<<INDEX_BITS)-1:0] valid;
    (* ramstyle = "M10K" *) reg [TAG_BITS+15:0] words[0:(1<<INDEX_BITS)-1];
    reg [TAG_BITS+15:0] lookup;
    reg lookup_valid, cancelled;
    wire cacheable = !io && !address[19];
    wire [INDEX_BITS-1:0] index = address[INDEX_BITS:1];
    wire [TAG_BITS-1:0] tag = address[18:INDEX_BITS+1];
    wire reading = strobe && cacheable && !write;
    assign legacy_strobe = strobe && !reset &&
        (!cacheable || write || state==MISS);
    // Preserve the memory controller's ACK release for the upstream bridge.
    assign ack = !reset && (state==HIT ? strobe && !invalidate : legacy_ack);
    assign readdata = state==HIT ? lookup[15:0] : legacy_readdata;

    // Synchronous data/tag RAM. Valid bits have a separate immediate clear so
    // DMA does not incur a cache-sweep delay. Reads always request both bytes.
    always @(posedge clk) begin
        if(state==IDLE && reading) lookup<=words[index];
        if(state==MISS && strobe && legacy_ack && !invalidate && !cancelled)
            words[index]<={tag,legacy_readdata};
    end
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE; valid<=0; lookup_valid<=0; cancelled<=0;
        end else begin
            if(invalidate) valid<=0;
            else if(strobe && cacheable && write) valid[index]<=0;
            else if(state==MISS && strobe && legacy_ack && !cancelled) valid[index]<=1;
            if(invalidate && state!=IDLE) cancelled<=1;
            case(state)
                IDLE: if(reading && !legacy_ack) begin
                    lookup_valid<=valid[index] && !invalidate;
                    cancelled<=invalidate;
                    state<=CHECK;
                end
                CHECK: if(!strobe) state<=IDLE;
                else if(lookup_valid && lookup[TAG_BITS+15:16]==tag && !invalidate && !cancelled)
                    state<=HIT;
                else state<=MISS;
                MISS: if(!strobe && !legacy_ack) state<=IDLE;
                HIT: if(!strobe) state<=IDLE;
                else if(invalidate) state<=MISS;
                default: state<=IDLE;
            endcase
        end
    end
    // synthesis translate_off
    always @(posedge clk) if(legacy_strobe && cacheable && !write && select!=2'b11)
        $fatal(1,"low RAM cache requires complete halfword reads");
    // synthesis translate_on
endmodule
