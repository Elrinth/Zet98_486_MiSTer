// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// In-order command queue in front of ao486_memory_bridge (posted writes).
//
// The 16-bit PC-98 memory fabric completes one halfword in ~20 CPU clocks,
// and the bridge holds one command, so a store followed by any other memory
// access used to stall the CPU for the whole transfer. Here writes are
// accepted into a FIFO and drained in order behind the CPU. A read enters the
// same FIFO (so it can never overtake an older write); after accepting a read
// nothing else is accepted until its last data beat returns, which keeps the
// CPU's single outstanding read. busy covers queued, executing and pending
// commands, so ao486_bus_bridge still drains all memory traffic before I/O.
// waitrequest depends only on registered state (no combinational path from
// the CPU's read/write request back to it).
module ao486_memory_queue #(
    parameter DEPTH_BITS = 3                 // 2**DEPTH_BITS entries
) (
    input  wire        clk,
    input  wire        reset,
    // CPU side
    input  wire [29:0] up_address,
    input  wire [31:0] up_writedata,
    input  wire [3:0]  up_byteenable,
    input  wire [3:0]  up_burstcount,
    input  wire        up_write,
    input  wire        up_read,
    output wire        up_waitrequest,
    output wire        busy,
    // bridge side
    output wire [29:0] dn_address,
    output wire [31:0] dn_writedata,
    output wire [3:0]  dn_byteenable,
    output wire [3:0]  dn_burstcount,
    output wire        dn_write,
    output wire        dn_read,
    input  wire        dn_waitrequest,
    input  wire        dn_busy,
    input  wire        readdatavalid
);
    localparam DEPTH = 1 << DEPTH_BITS;
    localparam W = 30 + 32 + 4 + 4 + 1;      // address, data, enables, burst, read
    reg [W-1:0] fifo [0:DEPTH-1];
    reg [DEPTH_BITS-1:0] head, tail;
    reg [DEPTH_BITS:0] count;
    reg read_pending;                         // a read was accepted, data not all back
    reg [3:0] beats_left;

    wire full = count == DEPTH;
    wire empty = count == 0;
    assign up_waitrequest = reset || full || read_pending;
    wire push = (up_write || up_read) && !up_waitrequest;
    wire [W-1:0] entry = fifo[head];
    wire head_read = entry[0];
    assign {dn_address, dn_writedata, dn_byteenable, dn_burstcount} = entry[W-1:1];
    assign dn_read = !empty && head_read;
    assign dn_write = !empty && !head_read;
    wire pop = !empty && !dn_waitrequest;
    assign busy = !empty || dn_busy || read_pending;

    always @(posedge clk) begin
        if (push) fifo[tail] <= {up_address, up_writedata, up_byteenable, up_burstcount, up_read};
        if (reset) begin
            head <= 0; tail <= 0; count <= 0;
            read_pending <= 0; beats_left <= 0;
        end else begin
            if (push) tail <= tail + 1'b1;
            if (pop) head <= head + 1'b1;
            count <= count + (push ? 1'b1 : 1'b0) - (pop ? 1'b1 : 1'b0);
            if (push && up_read) begin
                read_pending <= 1;
                beats_left <= up_burstcount;
            end else if (readdatavalid && read_pending) begin
                beats_left <= beats_left - 1'b1;
                if (beats_left == 1) read_pending <= 0;
            end
        end
    end

    // synthesis translate_off
    always @(posedge clk) if (!reset) begin
        if (up_read && up_write) $fatal(1, "simultaneous memory read/write");
        if (push && up_read && up_burstcount == 0) $fatal(1, "zero read burst");
        if (readdatavalid && !read_pending) $fatal(1, "unexpected read data");
    end
    // synthesis translate_on
endmodule
