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
    // Keep validity in the M10K too. A background sweep clears one entry per
    // clock after reset/DMA; reads continue on the original bus meanwhile.
    reg clearing, invalidate_previous;
    reg [INDEX_BITS-1:0] clear_index;
    (* ramstyle = "M10K" *) reg [TAG_BITS+16:0] words[0:(1<<INDEX_BITS)-1];
    reg [TAG_BITS+16:0] lookup;
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

    // The sweep never stalls the legacy bus or DMA. No fills occur during it,
    // so another invalidation while clearing needs no restart. Writes always
    // invalidate their slot, and reads always request both bytes.
    always @(posedge clk) begin
        if(state==IDLE && reading) lookup<=words[index];
        if(clearing) words[clear_index]<=0;
        else if(strobe && cacheable && write) words[index]<=0;
        else if(state==MISS && strobe && legacy_ack && !invalidate && !cancelled)
            words[index]<={1'b1,tag,legacy_readdata};
    end
    always @(posedge clk) begin
        if(reset) begin
            state<=IDLE; lookup_valid<=0; cancelled<=0;
            clearing<=1; clear_index<=0; invalidate_previous<=0;
        end else begin
            invalidate_previous<=invalidate;
            if(clearing) begin
                clear_index<=clear_index+1'b1;
                if(&clear_index) clearing<=0;
            end else if(invalidate && !invalidate_previous) begin
                clearing<=1; clear_index<=0;
            end
            if(invalidate && state!=IDLE) cancelled<=1;
            case(state)
                IDLE: if(reading && !legacy_ack) begin
                    lookup_valid<=!clearing && !invalidate;
                    cancelled<=invalidate;
                    state<=CHECK;
                end
                CHECK: if(!strobe) state<=IDLE;
                else if(lookup_valid && lookup[TAG_BITS+16] && lookup[TAG_BITS+15:16]==tag && !clearing && !invalidate && !cancelled)
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
