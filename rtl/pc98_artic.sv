// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// PC-98 ARTIC: free-running 24-bit counter at 307.2 kHz, read at 5Ch-5Fh.
// Byte reads: 5Ch bits 0-7, 5Dh and 5Eh bits 8-15, 5Fh bits 16-23; word
// reads: 5Ch bits 0-15, 5Eh bits 8-23 (NP2kai io/artic.c behaviour). NEC's
// CD-ROM driver and many programs time delays with it. Writes (5Fh is used
// as an I/O wait port) are accepted and ignored.
module pc98_artic #(parameter CLK_HZ = 90000000) (
    input wire clk,
    input wire [15:0] io_address,
    input wire io_read,
    output reg [15:0] io_readdata,
    output wire io_oe
);
    reg [31:0] phase = 0;
    reg [23:0] counter = 0;
    wire [31:0] next = phase + 32'd307200;
    always @(posedge clk) begin
        if (next >= CLK_HZ) begin phase <= next - CLK_HZ; counter <= counter + 1'b1; end
        else phase <= next;
    end
    wire hit = io_address == 16'h005c || io_address == 16'h005e;
    assign io_oe = hit && io_read;
    always @* io_readdata = io_address[1] ? counter[23:8] : counter[15:0];
endmodule
