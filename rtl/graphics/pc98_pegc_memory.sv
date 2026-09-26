// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// One CPU halfword transaction to PEGC's 512 KB DDR backing store. The address
// decoder upstream resolves BOTH aliases and the banked windows to this offset.
// Video is read-only, so no CPU cache/coherency mechanism is needed here.
// Like pc98_extmem_bridge, accepted reads drain even across a guest reset.
module pc98_pegc_memory (
    input wire clk, reset,
    input wire [18:1] address,
    input wire [1:0] select,
    input wire [15:0] writedata,
    input wire write, strobe,
    output wire ack,
    output reg [15:0] readdata,
    output wire [28:0] ddr_address,
    output wire [63:0] ddr_writedata,
    output wire [7:0] ddr_byteenable,
    output wire ddr_read, ddr_write,
    input wire ddr_busy, ddr_readdatavalid,
    input wire [63:0] ddr_readdata
);
    localparam IDLE=0, ISSUE=1, READ_DATA=2, ACK=3;
    reg [1:0] state=IDLE;
    reg [18:1] held_address;
    reg [15:0] held_data;
    reg [1:0] held_select;
    reg held_write, cancelled;
    // Core-owned 30000000h DDR region, reserved PC-98 graphics hole at 15 MB.
    // Exactly 30F00000h..30F7FFFFh, never ordinary RAM or HPS-owned memory.
    assign ddr_address = (32'h30f00000 >> 3) | {13'b0,held_address[18:3]};
    assign ddr_writedata = {4{held_data}};
    assign ddr_byteenable = {6'b0,held_select} << {held_address[2:1],1'b0};
    assign ddr_read = state==ISSUE && !held_write && strobe && !reset;
    assign ddr_write = state==ISSUE && held_write && strobe && !reset;
    assign ack = state==ACK && strobe && !cancelled && !reset;
    always @(posedge clk) begin
        if (reset) begin
            cancelled<=1;
            if (state!=READ_DATA || ddr_readdatavalid) state<=IDLE;
        end else case (state)
            IDLE: if(strobe) begin
                held_address<=address; held_data<=writedata;
                held_select<=select; held_write<=write; cancelled<=0;
                state<=ISSUE;
            end
            ISSUE: if(!strobe) state<=IDLE;
            else if(!ddr_busy) begin
                if(held_write) state<=ACK;
                else if(ddr_readdatavalid) begin
                    readdata<=ddr_readdata[{held_address[2:1],4'b0}+:16];
                    state<=ACK;
                end else state<=READ_DATA;
            end
            READ_DATA: begin
                if(!strobe) cancelled<=1;
                if(ddr_readdatavalid) begin
                    readdata<=ddr_readdata[{held_address[2:1],4'b0}+:16];
                    state<=cancelled || !strobe ? IDLE : ACK;
                end
            end
            ACK: if(!strobe) state<=IDLE;
        endcase
    end
endmodule
