// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Shared legacy bus for the ao486 memory and native I/O interfaces.
// Drain memory traffic (including the second command of an unaligned write)
// before granting I/O. Ownership is held through all halfwords and ACK release.
// I/O already in progress cannot be interrupted by a prefetch/memory request.
// This is a same-clock bridge; external DMA arbitration, PC-98 address decoding
// and interrupt acknowledgement are separate integration responsibilities.
module ao486_bus_bridge #(
    parameter READ_MASK_ALWAYS_NONZERO = 1'b0,
    // >0: posted-write command queue of 2**MEMORY_QUEUE_BITS entries in front
    // of the memory bridge (ao486_memory_queue); 0: direct, as before.
    parameter MEMORY_QUEUE_BITS = 0,
    parameter WIDE_RAM_MB = 0,
    parameter WIDE_RAM_ENABLE = 1'b1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [29:0] avm_address,
    input  wire [31:0] avm_writedata,
    input  wire [3:0]  avm_byteenable,
    input  wire [3:0]  avm_burstcount,
    input  wire        avm_write,
    input  wire        avm_read,
    output wire        avm_waitrequest,
    output wire        avm_readdatavalid,
    output wire [31:0] avm_readdata,
    input  wire        io_read_do,
    input  wire [15:0] io_read_address,
    input  wire [2:0]  io_read_length,
    output wire [31:0] io_read_data,
    output wire        io_read_done,
    input  wire        io_write_do,
    input  wire [15:0] io_write_address,
    input  wire [2:0]  io_write_length,
    input  wire [31:0] io_write_data,
    output wire        io_write_done,
    output wire        busy,

    output wire [31:1] bus_address,
    output wire [1:0]  bus_select,
    output wire [15:0] bus_writedata,
    output wire        bus_write,
    output wire        bus_strobe,
    output wire        bus_io,
    input  wire [15:0] bus_readdata,
    input  wire        bus_ack,
    input  wire        wide_linear_enable, wide_backend_busy,
    output wire [29:0] wide_address,
    output wire [31:0] wide_writedata,
    output wire [3:0]  wide_byteenable, wide_burstcount,
    output wire        wide_read, wide_write,
    input  wire        wide_waitrequest, wide_readdatavalid,
    input  wire [31:0] wide_readdata
);
    localparam NONE = 2'd0, MEMORY = 2'd1, IO = 2'd2;
    reg [1:0] owner;
    wire mem_busy, io_busy, mem_wait;
    wire [31:1] mem_address;
    wire [15:1] io_address;
    wire [1:0] mem_select, io_select;
    wire [15:0] mem_writedata, io_writedata;
    wire mem_write, io_write, mem_strobe, io_strobe;
    wire mem_request = avm_read || avm_write;
    wire io_request = io_read_do || io_write_do;

    always @(posedge clk) begin
        if (reset) owner <= NONE;
        else case (owner)
            NONE: if (!bus_ack && (WIDE_RAM_MB == 0 || !wide_backend_busy)) begin
                if (mem_request) owner <= MEMORY;
                else if (io_request) owner <= IO;
            end
            MEMORY: if (!mem_busy && !mem_request && !bus_ack) owner <= NONE;
            IO: if (!io_busy && !io_request && !bus_ack) owner <= NONE;
            default: owner <= NONE;
        endcase
    end

    assign busy = owner != NONE || (WIDE_RAM_MB != 0 && wide_backend_busy);
    assign avm_waitrequest = owner != MEMORY || mem_wait;
    assign bus_io = owner == IO;
    assign bus_address = bus_io ? {16'b0, io_address} : mem_address;
    assign bus_select = bus_io ? io_select : owner == MEMORY ? mem_select : 2'b00;
    assign bus_writedata = bus_io ? io_writedata : mem_writedata;
    assign bus_write = bus_io ? io_write : mem_write;
    assign bus_strobe = !reset && (bus_io ? io_strobe : owner == MEMORY && mem_strobe);

    wire [29:0] q_address;
    wire [31:0] q_writedata;
    wire [3:0] q_byteenable, q_burstcount;
    wire q_write, q_read, q_wait, bridge_busy;
    generate if (MEMORY_QUEUE_BITS > 0) begin : queued
        ao486_memory_queue #(.DEPTH_BITS(MEMORY_QUEUE_BITS)) memory_queue (
            .clk(clk), .reset(reset),
            .up_address(avm_address), .up_writedata(avm_writedata),
            .up_byteenable(avm_byteenable), .up_burstcount(avm_burstcount),
            .up_write(avm_write && owner == MEMORY), .up_read(avm_read && owner == MEMORY),
            .up_waitrequest(mem_wait), .busy(mem_busy),
            .dn_address(q_address), .dn_writedata(q_writedata),
            .dn_byteenable(q_byteenable), .dn_burstcount(q_burstcount),
            .dn_write(q_write), .dn_read(q_read), .dn_waitrequest(q_wait),
            .dn_busy(bridge_busy), .readdatavalid(avm_readdatavalid)
        );
    end else begin : direct
        assign q_address = avm_address;
        assign q_writedata = avm_writedata;
        assign q_byteenable = avm_byteenable;
        assign q_burstcount = avm_burstcount;
        assign q_write = avm_write && owner == MEMORY;
        assign q_read = avm_read && owner == MEMORY;
        assign mem_wait = q_wait;
        assign mem_busy = bridge_busy;
    end endgenerate
    ao486_memory_bridge #(.READ_MASK_ALWAYS_NONZERO(READ_MASK_ALWAYS_NONZERO),
                         .WIDE_RAM_MB(WIDE_RAM_MB), .WIDE_RAM_ENABLE(WIDE_RAM_ENABLE)) memory_bridge (
        .clk(clk), .reset(reset), .avm_address(q_address),
        .avm_writedata(q_writedata), .avm_byteenable(q_byteenable),
        .avm_burstcount(q_burstcount),
        .avm_write(q_write), .avm_read(q_read),
        .avm_waitrequest(q_wait), .avm_readdatavalid(avm_readdatavalid),
        .avm_readdata(avm_readdata), .busy(bridge_busy),
        .bus_address(mem_address), .bus_select(mem_select),
        .bus_writedata(mem_writedata), .bus_write(mem_write), .bus_strobe(mem_strobe),
        .bus_readdata(bus_readdata), .bus_ack(bus_ack && owner == MEMORY),
        .wide_linear_enable(wide_linear_enable), .wide_address(wide_address),
        .wide_writedata(wide_writedata), .wide_byteenable(wide_byteenable),
        .wide_burstcount(wide_burstcount), .wide_read(wide_read), .wide_write(wide_write),
        .wide_waitrequest(wide_waitrequest), .wide_readdatavalid(wide_readdatavalid),
        .wide_readdata(wide_readdata)
    );
    ao486_io_bridge io_bridge (
        .clk(clk), .reset(reset),
        .io_read_do(io_read_do && owner == IO), .io_read_address(io_read_address),
        .io_read_length(io_read_length), .io_read_data(io_read_data), .io_read_done(io_read_done),
        .io_write_do(io_write_do && owner == IO), .io_write_address(io_write_address),
        .io_write_length(io_write_length), .io_write_data(io_write_data), .io_write_done(io_write_done),
        .busy(io_busy), .bus_address(io_address), .bus_select(io_select),
        .bus_writedata(io_writedata), .bus_write(io_write), .bus_strobe(io_strobe),
        .bus_readdata(bus_readdata), .bus_ack(bus_ack && owner == IO)
    );
endmodule
