// SPDX-License-Identifier: GPL-3.0-or-later
// EGC programming interface. Experimental: not yet connected to the machine.
// Byte lanes use the native PC-98 bus order; the caller supplies the protected
// EGC-enable latch from port 6Ah. GRCG enable gates VRAM operations separately.
module pc98_egc_registers (
    input  wire        clk, reset,
    input  wire        egc_enable,
    input  wire [15:1] io_address,
    input  wire [1:0]  io_select,
    input  wire [15:0] io_writedata,
    input  wire        io_strobe, io_write,
    output wire        port_selected,
    output wire [15:0] access_control, color_select, operation,
    output wire [15:0] foreground, pixel_mask, background,
    output wire [15:0] shift_control, bit_length,
    output wire [63:0] foreground_words, background_words,
    output reg         write_committed, shift_reload, operation_written
);
    reg [15:0] registers [0:7];
    reg cycle_seen;
    wire [2:0] index = io_address[3:1];
    assign port_selected = io_address[15:4] == 12'h04a;
    wire mask_blocked = index == 4 && registers[1][14:13] != 0;
    wire accept = io_strobe && !cycle_seen && io_write && port_selected &&
                  egc_enable && |io_select && !mask_blocked;

    assign access_control = registers[0];
    assign color_select = registers[1];
    assign operation = registers[2];
    assign foreground = registers[3];
    assign pixel_mask = registers[4];
    assign background = registers[5];
    assign shift_control = registers[6];
    assign bit_length = registers[7];
    genvar plane;
    generate for (plane=0; plane<4; plane=plane+1) begin: colors
        assign foreground_words[16*plane +:16] = {16{foreground[plane]}};
        assign background_words[16*plane +:16] = {16{background[plane]}};
    end endgenerate

    always @(posedge clk) begin
        if (reset) begin
            registers[0] <= 16'hfff0;
            registers[1] <= 16'h00ff;
            registers[2] <= 0;
            registers[3] <= 0;
            registers[4] <= 16'hffff;
            registers[5] <= 0;
            registers[6] <= 0;
            registers[7] <= 16'h000f;
            cycle_seen <= 0;
            write_committed <= 0;
            shift_reload <= 0;
            operation_written <= 0;
        end else begin
            // A held legacy strobe represents one transaction. Do not replay
            // shift initialization on each wait cycle before acknowledgement.
            cycle_seen <= io_strobe;
            write_committed <= accept;
            shift_reload <= accept && (index == 6 || index == 7);
            operation_written <= accept && index == 2;
            if (accept) begin
                if (io_select[0]) registers[index][7:0] <= io_writedata[7:0];
                if (io_select[1]) registers[index][15:8] <= io_writedata[15:8];
            end
        end
    end
endmodule
