// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// ao486 native I/O requests to a 16-bit, byte-selected PC-98 bus.
//
// Matches MiSTer ao486 9d888c485bcf2e781824b303588668529a02015e:
// io_*_address is a BYTE address, io_*_length is 1, 2 or 4 bytes,
// and the CPU holds *_do until *_done. No Avalon I/O port is involved.
//
// The peripheral fabric must honour BOTH byte selects independently; its
// even/odd device decoders must not derive A0 from only the low-byte select.
// Aligned word cycles remain single transfers for 16-bit device registers.
// Used by the opt-in ao486 build; the default CPU remains Zet.
// All ports use clk. Clock-domain crossing belongs outside this module.
module ao486_io_bridge (
    input  wire        clk,
    input  wire        reset,
    input  wire        io_read_do,
    input  wire [15:0] io_read_address,
    input  wire [2:0]  io_read_length,
    output reg  [31:0] io_read_data,
    output reg         io_read_done,
    input  wire        io_write_do,
    input  wire [15:0] io_write_address,
    input  wire [2:0]  io_write_length,
    input  wire [31:0] io_write_data,
    output reg         io_write_done,
    output wire        busy,

    output wire [15:1] bus_address,
    output wire [1:0]  bus_select,
    output wire [15:0] bus_writedata,
    output wire        bus_write,
    output wire        bus_strobe,
    input  wire [15:0] bus_readdata,
    input  wire        bus_ack
);
    localparam IDLE = 2'd0, TRANSFER = 2'd1, RELEASE = 2'd2;
    reg [1:0] state;
    reg [15:0] address;
    reg [2:0] remaining;
    reg [2:0] position;
    reg [31:0] write_data;
    reg write_request;

    wire word_cycle = !address[0] && (remaining >= 2);
    wire [2:0] consumed = word_cycle ? 3'd2 : 3'd1;
    wire [15:0] read_piece = word_cycle ? bus_readdata :
                               address[0] ? {8'b0, bus_readdata[15:8]} :
                                            {8'b0, bus_readdata[7:0]};

    assign bus_address = address[15:1];
    assign busy = state != IDLE;
    assign bus_select = !bus_strobe ? 2'b00 :
                        address[0] ? 2'b10 : word_cycle ? 2'b11 : 2'b01;
    assign bus_writedata = address[0] ? {write_data[7:0], 8'b0} : write_data[15:0];
    assign bus_write = write_request;
    assign bus_strobe = state == TRANSFER && !reset;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            address <= 0;
            remaining <= 0;
            position <= 0;
            write_data <= 0;
            write_request <= 0;
            io_read_data <= 0;
            io_read_done <= 0;
            io_write_done <= 0;
        end else begin
            io_read_done <= 0;
            io_write_done <= 0;
            case (state)
                IDLE: if ((io_write_do || io_read_do) && !bus_ack) begin
                    address <= io_write_do ? io_write_address : io_read_address;
                    remaining <= io_write_do ? io_write_length : io_read_length;
                    write_data <= io_write_data;
                    write_request <= io_write_do;
                    position <= 0;
                    io_read_data <= 0;
                    state <= TRANSFER;
                end
                TRANSFER: if (bus_ack) begin
                    if (!write_request)
                        io_read_data <= io_read_data | ({16'b0, read_piece} << (position * 8));
                    address <= address + {13'b0, consumed};
                    remaining <= remaining - consumed;
                    position <= position + consumed;
                    write_data <= write_data >> (consumed * 8);
                    if (remaining == consumed) begin
                        io_read_done <= !write_request;
                        io_write_done <= write_request;
                    end
                    // Drop strobe and wait for ACK to fall before reusing the
                    // bus: Zet98 IOack holds its acknowledgement until release.
                    state <= RELEASE;
                end
                RELEASE: if (!bus_ack)
                    state <= remaining == 0 ? IDLE : TRANSFER;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
