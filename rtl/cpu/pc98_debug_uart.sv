// SPDX-License-Identifier: GPL-3.0-or-later
// Optional bring-up telemetry. One atomic 128-bit snapshot per quarter second,
// formatted as Z + 32 hexadecimal digits + newline at 115200 baud, 8N1.
module pc98_debug_uart #(
    parameter integer CLOCK_HZ = 50000000,
    parameter integer INTERVAL_CYCLES = CLOCK_HZ/4
) (
    input wire clk, reset,
    input wire [127:0] snapshot,
    output wire tx
);
    localparam integer DIV = (CLOCK_HZ + 57600)/115200;
    reg [$clog2(INTERVAL_CYCLES+1)-1:0] interval_count;
    reg [$clog2(DIV+1)-1:0] baud_count;
    reg [127:0] held;
    reg [5:0] character;
    reg [3:0] bits_left;
    reg [9:0] shift;
    reg sending;
    wire [3:0] nibble = held[127:124];
    wire [7:0] ascii_hex = nibble < 10 ? 8'h30 + nibble : 8'h41 + nibble - 10;
    wire [7:0] next_byte = character == 0 ? 8'h5a : character == 33 ? 8'h0a : ascii_hex;
    assign tx = shift[0];
    always @(posedge clk) begin
        if (reset) begin
            interval_count <= 0; baud_count <= 0; held <= 0;
            character <= 0; bits_left <= 0; shift <= 10'h3ff; sending <= 0;
        end else if (bits_left != 0) begin
            if (baud_count == 0) begin
                shift <= {1'b1,shift[9:1]};
                bits_left <= bits_left - 1'b1;
                baud_count <= DIV-1;
            end else baud_count <= baud_count-1'b1;
        end else if (sending) begin
            shift <= {1'b1,next_byte,1'b0};
            bits_left <= 10; baud_count <= DIV-1;
            if (character != 0) held <= {held[123:0],4'b0};
            if (character == 33) begin sending <= 0; interval_count <= INTERVAL_CYCLES-1; end
            else character <= character+1'b1;
        end else if (interval_count == 0) begin
            held <= snapshot; character <= 0; sending <= 1;
        end else interval_count <= interval_count-1'b1;
    end
endmodule
