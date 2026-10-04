// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Extended PC-98 RAM backed by MiSTer's core-owned DDR region (30000000h).
// Keep the 15-16 MB PC-98 system/graphics aperture out of ordinary RAM.
// RAM_MB is the top of the physical RAM map, not conventional DOS memory.
// This bridge shares the CPU clock with MiSter's DDR user interface.
module pc98_extmem_bridge #(
    parameter RAM_MB = 16,
    parameter READ_CACHE = 1'b1
) (
    input wire clk, reset,
    input wire [31:1] address,
    input wire [1:0] select,
    input wire [15:0] writedata,
    input wire write, strobe,
    output wire mapped,
    output wire ack,
    output reg [15:0] readdata,
    output wire [28:0] ddr_address,
    output wire [63:0] ddr_writedata,
    output wire [7:0] ddr_byteenable, ddr_burstcount,
    output wire ddr_read, ddr_write,
    input wire ddr_busy, ddr_readdatavalid,
    input wire [63:0] ddr_readdata
);
    localparam IDLE=0, ISSUE=1, READ_DATA=2, ACK=3;
    reg [1:0] state = IDLE;
    reg [31:1] held_address;
    reg [15:0] held_data;
    reg [1:0] held_select;
    reg held_write, cancelled;
    reg line_valid;
    reg [31:3] line_address;
    reg [63:0] line_data;
    integer byte_lane;
    wire [31:0] byte_address = {address,1'b0};
    assign mapped = byte_address >= 32'h00100000 &&
        byte_address < RAM_MB * 32'h00100000 &&
        !(byte_address >= 32'h00f00000 && byte_address < 32'h01000000);
    assign ack = state == ACK && !reset && !cancelled && strobe;
    // All DDR accesses are confined to the 256 MB region used by MiSTer ao486.
    // This module's mapped range uses only its first 16/64 MB.
    assign ddr_address = {4'h3,held_address[27:3]};
    assign ddr_writedata = {4{held_data}};
    assign ddr_byteenable = {6'b0,held_select} << {held_address[2:1],1'b0};
    assign ddr_burstcount = 1;
    assign ddr_read = state == ISSUE && !held_write && !reset && strobe;
    assign ddr_write = state == ISSUE && held_write && !reset && strobe;

    always @(posedge clk) begin
        if (reset) begin
            cancelled <= 1;
            line_valid <= 0;
            // A read accepted by DDR cannot be withdrawn. Drain its response
            // even across a soft reset, before allowing any new request.
            if (state != READ_DATA || ddr_readdatavalid) state <= IDLE;
        end else case (state)
            IDLE: if (strobe && mapped) begin
                held_address<=address;
                held_data<=writedata;
                held_select<=select;
                held_write<=write;
                cancelled<=0;
                if(READ_CACHE && !write && line_valid && line_address==address[31:3]) begin
                    readdata<=line_data[{address[2:1],4'b0} +:16];
                    state<=ACK;
                end else state<=ISSUE;
            end
            ISSUE: if (!strobe) state<=IDLE;
            else if (!ddr_busy) begin
                if (held_write) begin
                    state<=ACK;
                    // CPU is the only writer to this DDR region. Update a
                    // resident word only after DDR accepts the byte write.
                    if(READ_CACHE && line_valid && line_address==held_address[31:3])
                        for(byte_lane=0;byte_lane<2;byte_lane=byte_lane+1)
                            if(held_select[byte_lane])
                                line_data[({held_address[2:1],4'b0}+byte_lane*8) +:8]<=held_data[byte_lane*8+:8];
                end
                else if (ddr_readdatavalid) begin
                    readdata<=ddr_readdata[{held_address[2:1],4'b0} +:16];
                    line_valid<=READ_CACHE;
                    line_address<=held_address[31:3];
                    line_data<=ddr_readdata;
                    state<=ACK;
                end else state<=READ_DATA;
            end
            READ_DATA: begin
                if (!strobe) cancelled<=1;
                if (ddr_readdatavalid) begin
                    readdata<=ddr_readdata[{held_address[2:1],4'b0} +:16];
                    if(!cancelled && strobe) begin
                        line_valid<=READ_CACHE;
                        line_address<=held_address[31:3];
                        line_data<=ddr_readdata;
                    end
                    state<=cancelled || !strobe ? IDLE : ACK;
                end
            end
            ACK: if (!strobe) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
    // synthesis translate_off
    initial if (RAM_MB != 16 && RAM_MB != 64)
        $fatal(1,"extended RAM map supports 16 or 64 MB");
    // synthesis translate_on
endmodule

// Native DWORD path. One 64-bit DDR read supplies up to two sequential CPU
// words; byte stores become one DDR command with the original four lanes.
// No write posting or persistent framebuffer cache: completion still means
// DDR accepted the store, and every framebuffer read observes backing RAM.
module pc98_native_ddr_bridge #(
    parameter FRAMEBUFFER_ONLY = 1'b0
) (
    input wire clk, reset,
    input wire [29:0] address,
    input wire [31:0] writedata,
    input wire [3:0] byteenable, burstcount,
    input wire read, write,
    output wire waitrequest, busy, readdatavalid,
    output wire [31:0] readdata,
    output wire [28:0] ddr_address,
    output wire [63:0] ddr_writedata,
    output wire [7:0] ddr_byteenable,
    output wire ddr_read, ddr_write,
    input wire ddr_busy, ddr_readdatavalid,
    input wire [63:0] ddr_readdata
);
    localparam IDLE=0, DATA=1, WORD=2, ISSUE=3;
    reg [1:0] state=IDLE;
    reg [29:0] next_address;
    reg [3:0] remaining;
    reg [63:0] read_word;
    reg cancelled=0;
    wire [31:0] physical = {state==IDLE ? address : next_address,2'b00};
    wire high_fb_alias = physical[31:19] == (32'hfff00000 >> 19);
    wire [31:0] backing = (FRAMEBUFFER_ONLY || high_fb_alias) ?
        (32'h30f00000 | {13'b0,physical[18:0]}) :
        (32'h30000000 | {4'b0,physical[27:0]});
    assign ddr_address=backing[31:3];
    assign ddr_writedata={2{writedata}};
    // Reads consume both halves of the returned word. Request every byte,
    // independently of the CPU's byte-store mask or original burst mask.
    assign ddr_byteenable=ddr_read ? 8'hff :
        physical[2] ? {byteenable,4'b0} : {4'b0,byteenable};
    assign ddr_read=!reset && ((state==IDLE && read) || state==ISSUE);
    assign ddr_write=!reset && state==IDLE && write;
    assign busy=state!=IDLE;
    assign waitrequest=reset || busy || ddr_busy;
    assign readdatavalid=state==WORD && !reset && !cancelled;
    assign readdata=next_address[0] ? read_word[63:32] : read_word[31:0];
    always @(posedge clk) begin
        if(reset) begin
            cancelled<=1;
            // Accepted reads retain ownership until the DDR response drains.
            if(state!=DATA || ddr_readdatavalid) state<=IDLE;
        end else case(state)
            IDLE: if(read && !waitrequest) begin
                next_address<=address; remaining<=burstcount; cancelled<=0;
                if(ddr_readdatavalid) begin read_word<=ddr_readdata;state<=WORD;end
                else state<=DATA;
            end
            ISSUE: if(!ddr_busy) begin
                if(ddr_readdatavalid) begin read_word<=ddr_readdata;state<=WORD;end
                else state<=DATA;
            end
            DATA: if(ddr_readdatavalid) begin
                read_word<=ddr_readdata;
                state<=cancelled ? IDLE : WORD;
            end
            WORD: begin
                remaining<=remaining-1'b1;
                next_address<=next_address+1'b1;
                if(remaining==1) state<=IDLE;
                else if(next_address[0]) state<=ISSUE;
            end
        endcase
    end
    // synthesis translate_off
    always @(posedge clk) if(!waitrequest && (read || write)) begin
        if(read && write) $fatal(1,"native DDR simultaneous read/write");
        if(read && (burstcount==0 || burstcount>8)) $fatal(1,"native DDR invalid burst");
    end
    // synthesis translate_on
endmodule
