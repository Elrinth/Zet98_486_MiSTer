// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// 8237 DMA cycles above 1 MB reach extended RAM in DDR.
// On 386 and later PC-98s the bank registers (21h/23h/25h/27h) supply A16-A23
// (NP2kai's IA32 build keeps all eight bits). Windows 95 places its floppy DMA
// buffer above 1 MB (NP2kai: bank 3Fh); the legacy fabric decodes only 20 bits,
// so those sectors went to the ROM area and Explorer hung opening the drive.
// This port sits between the CPU's DDR master and MiSTer's DDR interface. A
// DMA byte waits until no CPU read is outstanding and the CPU is not holding a
// refused command, then owns the DDR command slot until it completes. The
// DDR therefore never sees a command withdrawn. The CPU's caches are already
// invalidated for the whole DMA bus ownership (pc98_cache_policy dma_active).
// DDR byte address = 30000000h + guest address, as pc98_extmem_bridge.
module pc98_dma_ddr #(
    // The PEGC DDR arbiter in pc98_ao486 already ignores a response it did not
    // request (a DMA read returns only while the CPU has none outstanding), so
    // PEGC builds leave the CPU's readdatavalid ungated.
    parameter GATE_VALID = 1
) (
    input wire clk, reset,
    // One DMA byte cycle: a strobe held until ack, then released.
    input wire [23:0] dma_address,
    input wire dma_read, dma_write,
    input wire [7:0] dma_writedata,
    output wire dma_ack,
    output reg [7:0] dma_readdata,
    // CPU DDR master (pc98_ao486); read data is shared from the DDR.
    input wire [28:0] cpu_address,
    input wire [63:0] cpu_writedata,
    input wire [7:0] cpu_byteenable, cpu_burstcount,
    input wire cpu_read, cpu_write,
    output wire cpu_busy, cpu_readdatavalid,
    output wire [28:0] ddr_address,
    output wire [63:0] ddr_writedata,
    output wire [7:0] ddr_byteenable, ddr_burstcount,
    output wire ddr_read, ddr_write,
    input wire ddr_busy, ddr_readdatavalid,
    input wire [63:0] ddr_readdata
);
    localparam IDLE=0, ISSUE=1, READ_DATA=2, ACK=3;
    reg [1:0] state=IDLE;
    reg [23:0] held_address;
    reg [7:0] held_data;
    reg held_write, cancelled;
    reg dma_grant=0;            // the DDR command slot belongs to the DMA byte
    reg cpu_hold=0;             // a CPU command was shown and refused last clock
    reg [8:0] cpu_remaining=0;  // CPU read beats still to return
    wire dma_strobe = dma_read || dma_write;
    wire dma_wait = state==ISSUE && !dma_grant;
    // While a DMA byte waits, show the CPU's command only if DDR already saw it.
    wire cpu_blocked = dma_grant || (dma_wait && !cpu_hold);
    wire cpu_shown = !cpu_blocked && (cpu_read || cpu_write);
    wire cpu_read_accept = cpu_shown && cpu_read && !ddr_busy;
    wire [8:0] cpu_remaining_next = cpu_remaining +
        (cpu_read_accept ? {1'b0,cpu_burstcount} : 9'd0) -
        (ddr_readdatavalid && !dma_grant ? 9'd1 : 9'd0);
    wire dma_command = dma_grant && state==ISSUE && !reset;

    assign ddr_address = dma_grant ? {4'h3,4'h0,held_address[23:3]} : cpu_address;
    assign ddr_writedata = dma_grant ? {8{held_data}} : cpu_writedata;
    assign ddr_byteenable = dma_grant ? 8'b1 << held_address[2:0] : cpu_byteenable;
    assign ddr_burstcount = dma_grant ? 8'd1 : cpu_burstcount;
    assign ddr_read = dma_grant ? dma_command && !held_write : cpu_shown && cpu_read;
    assign ddr_write = dma_grant ? dma_command && held_write : cpu_shown && cpu_write;
    assign cpu_busy = cpu_blocked || ddr_busy;
    assign cpu_readdatavalid = ddr_readdatavalid && !(GATE_VALID && dma_grant);
    assign dma_ack = state==ACK && dma_strobe && !cancelled;

    always @(posedge clk) begin
        cpu_remaining <= cpu_remaining_next;
        cpu_hold <= cpu_shown && ddr_busy;
        if (reset) begin
            cancelled <= 1;
            // An accepted read cannot be withdrawn; drain it even across reset.
            if (state != READ_DATA || ddr_readdatavalid) begin
                state <= IDLE;
                dma_grant <= 0;
            end
        end else case (state)
            IDLE: if (dma_strobe) begin
                held_address <= dma_address;
                held_data <= dma_writedata;
                held_write <= dma_write;
                cancelled <= 0;
                state <= ISSUE;
            end
            ISSUE: if (!dma_grant) begin
                if (!(cpu_shown && ddr_busy) && cpu_remaining_next==0) dma_grant <= 1;
            end else if (!ddr_busy) begin
                if (held_write) begin
                    dma_grant <= 0;
                    state <= ACK;
                end else if (ddr_readdatavalid) begin
                    dma_readdata <= ddr_readdata[{held_address[2:0],3'b0} +: 8];
                    dma_grant <= 0;
                    state <= ACK;
                end else state <= READ_DATA;
            end
            READ_DATA: if (ddr_readdatavalid) begin
                dma_readdata <= ddr_readdata[{held_address[2:0],3'b0} +: 8];
                dma_grant <= 0;
                state <= ACK;
            end
            ACK: if (!dma_strobe) state <= IDLE;
            default: state <= IDLE;
        endcase
    end
endmodule
