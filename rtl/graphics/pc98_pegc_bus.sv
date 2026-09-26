// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Full-physical-address PEGC target for ao486_bus_bridge's halfword bus.
// Claim is independent of strobe; the outer router MUST exclude claimed cycles
// from both legacy VRAM and ordinary extended RAM. Port 6A stays on the legacy
// bus and is snooped only when that bus acknowledges it. Registers/palette
// produce one side effect per held request, even if the ACK remains high.
// CPU-only reset cancels transactions but preserves display registers/palette.
module pc98_pegc_bus (
    input wire clk, reset, bus_reset,
    input wire [31:1] address,
    input wire [1:0] select,
    input wire [15:0] writedata,
    input wire write, io, strobe,
    input wire legacy_ack,
    input wire analog16, display_enable, gdc_5mhz,
    output wire claimed, ack,
    output reg [15:0] readdata,
    output wire mode256, single_page,
    output wire [28:0] ddr_address,
    output wire [63:0] ddr_writedata,
    output wire [7:0] ddr_byteenable,
    output wire ddr_read, ddr_write,
    input wire ddr_busy, ddr_readdatavalid,
    input wire [63:0] ddr_readdata,
    input wire video_clk,
    input wire [7:0] video_index,
    output wire [23:0] video_rgb
);
    wire abort_bus=reset || bus_reset;
    wire palette_selected, palette_write;
    wire [7:0] palette_index, palette_data, status_data;
    wire [1:0] palette_component;
    wire [23:0] palette_rgb;
    wire mmio_selected, vram_selected, vram_unhandled;
    wire [15:0] mmio_data, memory_data;
    wire [18:1] vram_address;
    wire status_selected=select[0] && address[15:1]==(16'h09a0 >> 1);
    assign claimed=io ? (palette_selected || status_selected) :
                        (mmio_selected || vram_selected || vram_unhandled);
    wire memory_selected=!io && vram_selected;
    wire memory_ack;
    reg register_ack=0, completed=0;
    assign ack=claimed && strobe && !abort_bus &&
               (memory_selected ? memory_ack : register_ack);
    wire accepted=strobe && !abort_bus && !completed && (claimed ? ack : legacy_ack);
    always @(posedge clk) begin
        if(abort_bus || !strobe) begin register_ack<=0;completed<=0;end
        else begin
            if(claimed && !memory_selected) register_ack<=1;
            if(accepted) completed<=1;
        end
    end
    pc98_pegc_control control (
        .clk(clk),.reset(reset),.io_address(address[15:1]),.io_select(select),
        .io_write(accepted && io && write),.io_read(io && !write),.io_writedata(writedata),
        .analog16(analog16),.display_enable(display_enable),.gdc_5mhz(gdc_5mhz),
        .io_read_selected(),.io_readdata(status_data),
        .palette_selected(palette_selected),.palette_write(palette_write),
        .palette_index(palette_index),.palette_component(palette_component),.palette_data(palette_data),
        .mem_address(address),.mem_select(select),.mem_write(accepted && !io && write),
        .mem_writedata(writedata),.mmio_selected(mmio_selected),.mmio_readdata(mmio_data),
        .vram_selected(vram_selected),.vram_word_address(vram_address),.vram_unhandled(vram_unhandled),
        .mode256(mode256),.single_page(single_page),.packed_mode(),.linear_enable()
    );
    pc98_pegc_palette palette (
        .cpu_clk(clk),.cpu_index(palette_index),.cpu_write(palette_write),
        .cpu_component(palette_component),.cpu_data(palette_data),.cpu_rgb(palette_rgb),
        .video_clk(video_clk),.video_index(video_index),.video_rgb(video_rgb)
    );
    pc98_pegc_memory memory (
        .clk(clk),.reset(abort_bus),.address(vram_address),.select(select),
        .writedata(writedata),.write(write),.strobe(strobe && memory_selected),
        .ack(memory_ack),.readdata(memory_data),.ddr_address(ddr_address),
        .ddr_writedata(ddr_writedata),.ddr_byteenable(ddr_byteenable),
        .ddr_read(ddr_read),.ddr_write(ddr_write),.ddr_busy(ddr_busy),
        .ddr_readdatavalid(ddr_readdatavalid),.ddr_readdata(ddr_readdata)
    );
    always @* begin
        readdata=16'hffff;
        if(!io) begin
            if(vram_selected) readdata=memory_data;
            else if(mmio_selected) readdata=mmio_data;
        end else if(status_selected) readdata={8'hff,status_data};
        else if(palette_selected) begin
            case(palette_component)
                0: readdata={8'hff,palette_index};
                1: readdata={8'hff,palette_rgb[15:8]};
                2: readdata={8'hff,palette_rgb[23:16]};
                3: readdata={8'hff,palette_rgb[7:0]};
            endcase
        end
    end
endmodule
