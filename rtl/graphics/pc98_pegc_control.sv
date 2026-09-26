// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// PC-9821 PEGC packed-pixel register/address front end. CPU clock only.
// io_write and mem_write are ONE accepted bus beat, not a held request.
// No RAM, palette storage, rasterizer or planar drawing engine lives here.
// Integration must suppress legacy palette/MMIO/VRAM access when selected,
// and must NOT acknowledge framebuffer accesses before the RAM completes.
// Register semantics: SL9821 sl9821_tec5.html, MAME nec/pc9821.cpp and
// NP2kai io/gdc.c (references, independently implemented).
module pc98_pegc_control (
    input  wire clk, reset,
    input  wire [15:1] io_address,
    input  wire [1:0] io_select,
    input  wire io_write, io_read,
    input  wire [15:0] io_writedata,
    // Existing text GDC owns these flags. Snoop rather than duplicate them.
    input  wire analog16, display_enable, gdc_5mhz,
    output wire io_read_selected,
    output reg [7:0] io_readdata,
    output wire palette_selected,
    output wire palette_write,
    output reg [7:0] palette_index,
    output wire [1:0] palette_component, // 1=green, 2=red, 3=blue
    output wire [7:0] palette_data,

    input  wire [31:1] mem_address,
    input  wire [1:0] mem_select,
    input  wire mem_write,
    input  wire [15:0] mem_writedata,
    output wire mmio_selected,
    output reg [15:0] mmio_readdata,
    output wire vram_selected,
    output wire [18:1] vram_word_address,
    // Blocks fall-through to the old planes for unimplemented planar access
    // and the unused third window. Not a framebuffer request.
    output wire vram_unhandled,
    output reg mode256, single_page,
    output reg packed_mode, linear_enable
);
    wire [15:0] port_address = {io_address,1'b0};
    wire [31:0] byte_address = {mem_address,1'b0};
    reg ext_unlocked;
    reg [7:0] status_index;
    reg [3:0] bank0, bank1;

    assign palette_selected = mode256 && io_select[0] &&
                              port_address[15:3] == (16'h00a8 >> 3);
    assign palette_write = palette_selected && io_write &&
                           port_address[2:1] != 0 && !reset;
    assign palette_component = port_address[2:1];
    assign palette_data = io_writedata[7:0];
    assign io_read_selected = io_read && io_select[0] && port_address == 16'h09a0;
    always @* begin
        io_readdata = {6'b0,gdc_5mhz,1'b0};
        case (status_index)
            8'h03: io_readdata[0] = display_enable;
            8'h04: io_readdata[0] = analog16;
            8'h08: io_readdata[0] = ext_unlocked;
            8'h0a: io_readdata[0] = mode256;
            8'h0d: io_readdata[0] = single_page;
            default: ;
        endcase
    end

    assign mmio_selected = mode256 && byte_address[31:15] == (32'h000e0000 >> 15);
    always @* begin
        mmio_readdata = 0;
        case (byte_address[14:1])
            (15'h0004 >> 1): mmio_readdata[3:0] = bank0;
            (15'h0006 >> 1): mmio_readdata[3:0] = bank1;
            (15'h0100 >> 1): mmio_readdata[0] = !packed_mode;
            (15'h0102 >> 1): mmio_readdata[0] = linear_enable;
            default: ; // Planar drawing registers are not implemented yet.
        endcase
        if (!mem_select[0]) mmio_readdata[7:0] = 0;
    end

    wire linear_address = byte_address[31:19] == (32'h00f00000 >> 19) ||
                          byte_address[31:19] == (32'hfff00000 >> 19);
    wire window0 = byte_address[31:15] == (32'h000a8000 >> 15);
    wire window1 = byte_address[31:15] == (32'h000b0000 >> 15);
    wire window_unused = byte_address[31:15] == (32'h000b8000 >> 15);
    // Linear VRAM remains a byte array even in planar window mode. Its own
    // enable is separate from display mode; changing the display preserves RAM.
    wire linear_selected = linear_enable && linear_address;
    assign vram_selected = linear_selected || (mode256 && packed_mode && (window0 || window1));
    assign vram_word_address = linear_selected ? mem_address[18:1] :
                               {window1 ? bank1 : bank0,mem_address[14:1]};
    assign vram_unhandled = mode256 && (window_unused || (!packed_mode && (window0 || window1)));

    always @(posedge clk) begin
        if (reset) begin
            ext_unlocked <= 0; mode256 <= 0; single_page <= 0;
            packed_mode <= 1; linear_enable <= 0;
            bank0 <= 0; bank1 <= 0; status_index <= 0; palette_index <= 0;
        end else begin
            if (io_write && io_select[0]) begin
                if (port_address == 16'h006a) begin
                    case (io_writedata[7:0])
                        8'h06: ext_unlocked <= 0;
                        8'h07: ext_unlocked <= 1;
                        8'h20: if (ext_unlocked) mode256 <= 0;
                        8'h21: if (ext_unlocked) mode256 <= 1;
                        8'h68: single_page <= 0;
                        8'h69: single_page <= 1;
                        default: ;
                    endcase
                end
                if (port_address == 16'h09a0) status_index <= io_writedata[7:0];
                if (palette_selected && port_address[2:1] == 0)
                    palette_index <= io_writedata[7:0];
            end
            if (mem_write && mem_select[0] && mmio_selected) begin
                case (byte_address[14:1])
                    (15'h0004 >> 1): bank0 <= mem_writedata[3:0];
                    (15'h0006 >> 1): bank1 <= mem_writedata[3:0];
                    (15'h0100 >> 1): packed_mode <= !mem_writedata[0];
                    (15'h0102 >> 1): linear_enable <= mem_writedata[0];
                    default: ;
                endcase
            end
        end
    end
endmodule
