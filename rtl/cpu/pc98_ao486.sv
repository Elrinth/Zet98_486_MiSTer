// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Initial ao486 connection to Zet98's legacy memory/peripheral fabric.
// The existing fabric implements the low 1 MB. Reset ROM aliases are explicit;
// other physical addresses read as FFFF and discard writes, never alias RAM.
// Instruction caching is limited to fixed low RAM, with external invalidation.
module pc98_ao486 #(
    parameter ICACHE_ENABLE = 1'b1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        cache_invalidate,
    input  wire        interrupt_do,
    input  wire [7:0]  interrupt_vector,
    output wire        interrupt_done,
    output wire [19:1] bus_address,
    output wire [1:0]  bus_select,
    output wire [15:0] bus_writedata,
    output wire        bus_write,
    output wire        bus_strobe,
    output wire        bus_io,
    input  wire [15:0] bus_readdata,
    input  wire        bus_ack,
    output wire        unmapped_access
);
    wire [29:0] avm_address;
    wire [31:0] avm_writedata, avm_readdata;
    wire [3:0] avm_byteenable, avm_burstcount;
    wire avm_read, avm_write, avm_waitrequest, avm_readdatavalid;
    wire io_read_do, io_read_done, io_write_do, io_write_done;
    wire [15:0] io_read_address, io_write_address;
    wire [2:0] io_read_length, io_write_length;
    wire [31:0] io_read_data, io_write_data;
    wire [31:1] physical_address;
    wire physical_strobe;
    wire [15:0] peripheral_read;
    reg a20_enable;
    reg [3:0] reset_count;
    wire cpu_reset = reset || (reset_count != 0);

    // PC-98 CPU controls, based on NP2kai io/cpuio.c commit
    // 5939e0c6d5985c4c08fc70f289a83290e5d3e6f7 (reference, not copied code).
    // F0 writes reset the CPU only; F2 enables A20; F6 commands 02/03 set/clear it.
    wire control_write = bus_strobe && bus_ack && bus_io && bus_write && bus_select[0];
    always @(posedge clk) begin
        if (reset) begin
            a20_enable <= 0;
            reset_count <= 0;
        end else begin
            if (reset_count != 0) reset_count <= reset_count - 1'b1;
            if (control_write) begin
                case ({bus_address[15:1], 1'b0})
                    16'h00f0: begin a20_enable <= 0; reset_count <= 8; end
                    16'h00f2: a20_enable <= 1;
                    16'h00f6: case (bus_writedata[7:0])
                        8'h02: a20_enable <= 1;
                        8'h03: a20_enable <= 0;
                        default: ;
                    endcase
                    default: ;
                endcase
            end
        end
    end

    // F6 reports NMI disabled: the upstream ao486 has no NMI input.
    assign peripheral_read = !bus_io || !bus_select[0] ? bus_readdata :
        bus_address[15:1] == (16'h00f2 >> 1) ? {bus_readdata[15:8], 7'h7f, !a20_enable} :
        bus_address[15:1] == (16'h00f6 >> 1) ? {bus_readdata[15:8], 7'b0, !a20_enable} :
        bus_readdata;

    wire reset_alias = physical_address[31:21] == 11'h7ff && physical_address[19:16] == 4'hf;
    wire mapped = bus_io || physical_address[31:20] == 0 || reset_alias;
    assign bus_address = physical_address[19:1];
    assign bus_strobe = physical_strobe && mapped;
    assign unmapped_access = physical_strobe && !mapped;

    ao486 cpu (
        .clk(clk), .rst_n(!cpu_reset), .a20_enable(a20_enable), .cache_disable(!ICACHE_ENABLE),
        .cache_invalidate(cache_invalidate),
        .interrupt_do(interrupt_do), .interrupt_vector(interrupt_vector), .interrupt_done(interrupt_done),
        .avm_address(avm_address), .avm_writedata(avm_writedata), .avm_byteenable(avm_byteenable),
        .avm_burstcount(avm_burstcount), .avm_write(avm_write), .avm_read(avm_read),
        .avm_waitrequest(avm_waitrequest), .avm_readdatavalid(avm_readdatavalid), .avm_readdata(avm_readdata),
        .dma_address(24'b0), .dma_16bit(1'b0), .dma_write(1'b0), .dma_writedata(16'b0), .dma_read(1'b0),
        .dma_readdata(), .dma_readdatavalid(), .dma_waitrequest(),
        .io_read_do(io_read_do), .io_read_address(io_read_address), .io_read_length(io_read_length),
        .io_read_data(io_read_data), .io_read_done(io_read_done), .io_write_do(io_write_do),
        .io_write_address(io_write_address), .io_write_length(io_write_length),
        .io_write_data(io_write_data), .io_write_done(io_write_done)
    );
    ao486_bus_bridge bridge (
        .clk(clk), .reset(cpu_reset),
        .avm_address(avm_address), .avm_writedata(avm_writedata), .avm_byteenable(avm_byteenable),
        .avm_burstcount(avm_burstcount), .avm_write(avm_write), .avm_read(avm_read),
        .avm_waitrequest(avm_waitrequest), .avm_readdatavalid(avm_readdatavalid), .avm_readdata(avm_readdata),
        .io_read_do(io_read_do), .io_read_address(io_read_address), .io_read_length(io_read_length),
        .io_read_data(io_read_data), .io_read_done(io_read_done), .io_write_do(io_write_do),
        .io_write_address(io_write_address), .io_write_length(io_write_length),
        .io_write_data(io_write_data), .io_write_done(io_write_done), .busy(),
        .bus_address(physical_address), .bus_select(bus_select), .bus_writedata(bus_writedata),
        .bus_write(bus_write), .bus_strobe(physical_strobe), .bus_io(bus_io),
        .bus_readdata(mapped ? peripheral_read : 16'hffff),
        .bus_ack(bus_ack || unmapped_access)
    );
endmodule
