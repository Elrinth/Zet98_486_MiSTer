// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Initial ao486 connection to Zet98's legacy memory/peripheral fabric.
// The legacy fabric implements the low 1 MB. Optional extended RAM uses DDR;
// other physical addresses read as FFFF and discard writes, never alias RAM.
// Instruction caching covers low RAM and optionally native upper conventional RAM.
module pc98_ao486 #(
    parameter ICACHE_ENABLE = 1'b1,
    parameter EXT_RAM_MB = 0,
    parameter EXT_RAM_READ_CACHE = 1'b1,
    parameter EXT_RAM_EARLY_READ_HIT = 1'b1,
    parameter LOWMEM_CACHE = 1'b0,
    parameter LOWMEM_CACHE_KB = 8,
    parameter UPPER_RAM_ICACHE = 0,
    parameter CLOCK_RATE_MHZ = 90,
    parameter PEGC_ENABLE = 0,
    parameter EARLY_WRITE_COMPLETE = 1'b1,
    parameter EARLY_MEMORY_GRANT = 1'b1,
`ifdef ZET98_NATIVE_DDR
    parameter NATIVE_DDR = 1,
`else
    parameter NATIVE_DDR = 0,
`endif
`ifdef ZET98_NATIVE_DDR_FB_ONLY
    parameter NATIVE_DDR_RAM = 0,
`else
    parameter NATIVE_DDR_RAM = 1,
`endif
    // Posted-write memory command queue (ao486_memory_queue): 2**N entries.
    // Off: measured on hardware (B222, 8 entries) it gave no gain for stores
    // mixed with ALU work (7257 -> 7252 KB/s) and cost 13% on VRAM copies
    // (3721 -> 3221 KB/s). One 16-bit fabric transfer (~22 clocks, the SDRAM
    // controller's clock-crossing round trip) is the limit, not the queue.
    parameter MEMORY_QUEUE_BITS = 0
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [1:0]  cpu_speed_sel,
    input  wire        cache_invalidate,
    input  wire        cache_upper_ram_native,
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
    output wire        unmapped_access,
    output wire [127:0] debug_snapshot,
    output wire [28:0] ddr_address,
    output wire [63:0] ddr_writedata,
    output wire [7:0]  ddr_byteenable, ddr_burstcount,
    output wire        ddr_read, ddr_write,
    input  wire        ddr_busy, ddr_readdatavalid,
    input  wire [63:0] ddr_readdata,
    input wire pegc_analog16, pegc_display_enable, pegc_gdc_5mhz,
    output wire pegc_mode256, pegc_single_page,
    input wire pegc_pixel_clk,
    input wire [7:0] pegc_palette_index,
    output wire [23:0] pegc_palette_rgb,
    // Line fetch client is already in CPU clock, not a raw pixel-domain bus.
    input wire [18:3] pegc_video_address,
    input wire [4:0] pegc_video_burstcount,
    input wire pegc_video_read,
    output wire pegc_video_busy, pegc_video_readdatavalid,
    output wire [63:0] pegc_video_readdata
);
    wire [29:0] avm_address;
    wire [31:0] avm_writedata, avm_readdata;
    wire [3:0] avm_byteenable, avm_burstcount;
    wire avm_read, avm_write, avm_waitrequest, avm_readdatavalid;
    wire fabric_busy, memory_write_complete;
    wire [29:0] wide_address;
    wire [31:0] wide_writedata, wide_readdata;
    wire [3:0] wide_byteenable, wide_burstcount;
    wire wide_read, wide_write, wide_waitrequest, wide_readdatavalid;
    wire wide_busy, wide_backend_busy, pegc_linear_enable;
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
    wire pegc_claimed, pegc_ack;
    wire [15:0] pegc_readdata;
    wire legacy_mapped = !pegc_claimed && (bus_io || physical_address[31:20] == 0 || reset_alias);
    wire extended_mapped, extended_ack;
    wire [15:0] extended_readdata;
    wire mapped = legacy_mapped || extended_mapped || pegc_claimed;
    assign bus_address = physical_address[19:1];
    wire legacy_request = physical_strobe && legacy_mapped;
    wire legacy_ack;
    wire [15:0] legacy_readdata;
    generate if(LOWMEM_CACHE) begin : lowmem_cache
        pc98_lowmem_cache #(.INDEX_BITS($clog2(LOWMEM_CACHE_KB*512))) cache (
            .clk(clk), .reset(cpu_reset), .invalidate(cache_invalidate),
            .address(bus_address), .select(bus_select), .write(bus_write), .io(bus_io),
            .writedata(bus_writedata),
            .strobe(legacy_request), .legacy_strobe(bus_strobe), .legacy_ack(bus_ack),
            .legacy_readdata(peripheral_read), .ack(legacy_ack), .readdata(legacy_readdata)
        );
    end else begin : no_lowmem_cache
        assign bus_strobe=legacy_request;
        assign legacy_ack=bus_ack;
        assign legacy_readdata=peripheral_read;
    end endgenerate
    assign unmapped_access = physical_strobe && !mapped;

    wire [28:0] ram_ddr_address;
    wire [63:0] ram_ddr_writedata;
    wire [7:0] ram_ddr_byteenable, ram_ddr_burstcount;
    wire ram_ddr_read, ram_ddr_write, ram_ddr_busy, ram_ddr_valid;
    wire [28:0] legacy_ram_address, native_ddr_address;
    wire [63:0] legacy_ram_writedata, native_ddr_writedata;
    wire [7:0] legacy_ram_byteenable, native_ddr_byteenable;
    wire legacy_ram_read, legacy_ram_write, legacy_ram_busy, legacy_ram_valid;
    wire native_ddr_read, native_ddr_write, native_ddr_busy, native_ddr_valid;
    wire native_request = native_ddr_read || native_ddr_write;
    reg ram_response_native=0, ram_read_pending=0, fb_read_pending=0;
    wire fb_command_read, fb_command_busy, fb_response_valid;
    // The legacy and native RAM clients share a DDR arbiter slot. The common
    // CPU bus serializes them; retain the response tag through CPU-only reset.
    wire ram_read_accept=ram_ddr_read && !ram_ddr_busy;
    wire ram_response_tag=ram_read_pending ? ram_response_native : native_request;
    always @(posedge clk) begin
        if(ram_ddr_valid) ram_read_pending<=0;
        if(ram_read_accept) begin
            ram_response_native<=native_request;
            ram_read_pending<=!ram_ddr_valid;
        end
        if(fb_response_valid) fb_read_pending<=0;
        if(fb_command_read && !fb_command_busy) fb_read_pending<=!fb_response_valid;
    end
    assign wide_backend_busy=wide_busy || ram_read_pending || fb_read_pending;
    assign ram_ddr_address=native_request ? native_ddr_address : legacy_ram_address;
    assign ram_ddr_writedata=native_request ? native_ddr_writedata : legacy_ram_writedata;
    assign ram_ddr_byteenable=native_request ? native_ddr_byteenable : legacy_ram_byteenable;
    assign ram_ddr_read=native_ddr_read || legacy_ram_read;
    assign ram_ddr_write=native_ddr_write || legacy_ram_write;
    assign ram_ddr_burstcount=1;
    assign native_ddr_busy=ram_ddr_busy || legacy_ram_read || legacy_ram_write;
    assign legacy_ram_busy=ram_ddr_busy || native_request;
    assign native_ddr_valid=ram_ddr_valid && ram_response_tag;
    assign legacy_ram_valid=ram_ddr_valid && !ram_response_tag;
    generate if(NATIVE_DDR && EXT_RAM_MB!=0) begin : native_ddr
        pc98_native_ddr_bridge #(.FRAMEBUFFER_ONLY(!NATIVE_DDR_RAM)) ram (
            .clk(clk),.reset(cpu_reset),.address(wide_address),.writedata(wide_writedata),
            .byteenable(wide_byteenable),.burstcount(wide_burstcount),
            .read(wide_read),.write(wide_write),.waitrequest(wide_waitrequest),
            .busy(wide_busy),.readdatavalid(wide_readdatavalid),.readdata(wide_readdata),
            .ddr_address(native_ddr_address),.ddr_writedata(native_ddr_writedata),
            .ddr_byteenable(native_ddr_byteenable),.ddr_read(native_ddr_read),.ddr_write(native_ddr_write),
            .ddr_busy(native_ddr_busy),.ddr_readdatavalid(native_ddr_valid),.ddr_readdata(ddr_readdata)
        );
    end else begin : no_native_ddr
        assign {native_ddr_address,native_ddr_writedata,native_ddr_byteenable,native_ddr_read,native_ddr_write}=0;
        assign {wide_busy,wide_readdatavalid,wide_readdata}=0;
        assign wide_waitrequest=1;
    end endgenerate
    generate if (EXT_RAM_MB != 0) begin : extended_ram
        // Native RAM stores bypass this bridge. Disable its private read
        // cache in that configuration so aperture-crossing reads cannot see
        // stale data. Framebuffer-only builds retain B240's RAM read cache.
        pc98_extmem_bridge #(.RAM_MB(EXT_RAM_MB),
            .READ_CACHE(EXT_RAM_READ_CACHE && !(NATIVE_DDR && NATIVE_DDR_RAM)),
            .EARLY_READ_HIT(EXT_RAM_EARLY_READ_HIT)) ram (
            .clk(clk), .reset(reset), .address(physical_address),
            .select(bus_select), .writedata(bus_writedata), .write(bus_write),
            .strobe(physical_strobe && !legacy_mapped && !pegc_claimed),
            .mapped(extended_mapped), .ack(extended_ack), .readdata(extended_readdata),
            .ddr_address(legacy_ram_address), .ddr_writedata(legacy_ram_writedata),
            .ddr_byteenable(legacy_ram_byteenable), .ddr_burstcount(),
            .ddr_read(legacy_ram_read), .ddr_write(legacy_ram_write), .ddr_busy(legacy_ram_busy),
            .ddr_readdatavalid(legacy_ram_valid), .ddr_readdata(ddr_readdata)
        );
    end else begin : no_extended_ram
        assign extended_mapped=0;
        assign extended_ack=0;
        assign extended_readdata=16'hffff;
        assign {legacy_ram_address,legacy_ram_writedata,legacy_ram_byteenable,legacy_ram_read,legacy_ram_write}=0;
    end endgenerate

    generate if(PEGC_ENABLE) begin : pegc
        wire [28:0] fb_address;
        wire [63:0] fb_writedata;
        wire [7:0] fb_byteenable;
        wire fb_read,fb_write,fb_busy,fb_valid;
        assign {fb_command_read,fb_command_busy,fb_response_valid}={fb_read,fb_busy,fb_valid};
        pc98_pegc_bus target (
            .clk(clk),.reset(reset),.bus_reset(cpu_reset),
            .address(physical_address),.select(bus_select),.writedata(bus_writedata),
            .write(bus_write),.io(bus_io),.strobe(physical_strobe),.legacy_ack(legacy_ack),
            .analog16(pegc_analog16),.display_enable(pegc_display_enable),.gdc_5mhz(pegc_gdc_5mhz),
            .claimed(pegc_claimed),.ack(pegc_ack),.readdata(pegc_readdata),
            .mode256(pegc_mode256),.single_page(pegc_single_page),.linear_enable(pegc_linear_enable),
            .ddr_address(fb_address),.ddr_writedata(fb_writedata),.ddr_byteenable(fb_byteenable),
            .ddr_read(fb_read),.ddr_write(fb_write),.ddr_busy(fb_busy),
            .ddr_readdatavalid(fb_valid),.ddr_readdata(ddr_readdata),
            .video_clk(pegc_pixel_clk),.video_index(pegc_palette_index),.video_rgb(pegc_palette_rgb)
        );
        pc98_pegc_ddr_arbiter arbiter (
            .clk(clk),.reset(reset),.ram_address(ram_ddr_address),.ram_writedata(ram_ddr_writedata),
            .ram_byteenable(ram_ddr_byteenable),.ram_read(ram_ddr_read),.ram_write(ram_ddr_write),
            .ram_busy(ram_ddr_busy),.ram_readdatavalid(ram_ddr_valid),
            .fb_address(fb_address),.fb_writedata(fb_writedata),.fb_byteenable(fb_byteenable),
            .fb_read(fb_read),.fb_write(fb_write),.fb_busy(fb_busy),.fb_readdatavalid(fb_valid),
            .video_address(pegc_video_address),.video_burstcount(pegc_video_burstcount),
            .video_read(pegc_video_read),.video_busy(pegc_video_busy),
            .video_readdatavalid(pegc_video_readdatavalid),.client_readdata(pegc_video_readdata),
            .ddr_address(ddr_address),.ddr_writedata(ddr_writedata),.ddr_byteenable(ddr_byteenable),
            .ddr_burstcount(ddr_burstcount),.ddr_read(ddr_read),.ddr_write(ddr_write),
            .ddr_busy(ddr_busy),.ddr_readdatavalid(ddr_readdatavalid),.ddr_readdata(ddr_readdata)
        );
    end else begin : no_pegc
        assign pegc_linear_enable=0;
        assign {fb_command_read,fb_command_busy,fb_response_valid}=0;
        assign {pegc_claimed,pegc_ack,pegc_readdata,pegc_mode256,pegc_single_page,pegc_palette_rgb}=0;
        assign pegc_video_busy=1;
        assign {pegc_video_readdatavalid,pegc_video_readdata}=0;
        assign ddr_address=ram_ddr_address;
        assign ddr_writedata=ram_ddr_writedata;
        assign ddr_byteenable=ram_ddr_byteenable;
        assign ddr_burstcount=ram_ddr_burstcount;
        assign ddr_read=ram_ddr_read;
        assign ddr_write=ram_ddr_write;
        assign ram_ddr_busy=ddr_busy;
        assign ram_ddr_valid=ddr_readdatavalid;
    end endgenerate

`ifdef ZET98_Z486
    wire [35:0] debug_cpu_state;
    wire [17:0] debug_gate;
    wire crash_tx;
    z486_pc98_adapter #(.EXT_RAM_MB(EXT_RAM_MB), .CLOCK_RATE_MHZ(CLOCK_RATE_MHZ)) cpu (
        .cpu_speed_sel(cpu_speed_sel),
        .fabric_idle(!fabric_busy),
        // A queued bridge can complete an older command. Only the direct
        // single-outstanding configuration can attribute this pulse to z486.
        .write_complete(EARLY_WRITE_COMPLETE && MEMORY_QUEUE_BITS == 0 && memory_write_complete),
        .debug_state(debug_cpu_state), .debug_gate(debug_gate),
        .crash_tx(crash_tx),
`else
    ao486 cpu (
`endif
        .clk(clk), .rst_n(!cpu_reset), .a20_enable(a20_enable), .cache_disable(!ICACHE_ENABLE),
        .cache_invalidate(cache_invalidate),
        .cache_upper_ram(UPPER_RAM_ICACHE && cache_upper_ram_native),
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
// The CPU snapshot (EIP, last I/O) also feeds the trace logger in trace builds.
`ifdef ZET98_Z486_DEBUG
`define ZET98_CPU_SNAPSHOT
`endif
`ifdef ZET98_CD_TRACE
`define ZET98_CPU_SNAPSHOT
`endif
`ifdef ZET98_CPU_SNAPSHOT
    reg [15:0] debug_completed, debug_io_address, debug_io_data;
    reg debug_previous_ack;
    reg debug_io_pulse, debug_io_write;      // one clock per completed I/O access (trace builds)
    always @(posedge clk) begin
        debug_io_pulse <= 0;
        if(reset) begin
            debug_completed <= 0; debug_previous_ack <= 0;
            debug_io_address <= 0; debug_io_data <= 0; debug_io_write <= 0;
        end else begin
            debug_previous_ack <= bus_ack;
            if(bus_ack && !debug_previous_ack && bus_strobe) begin
                debug_completed <= debug_completed+1'b1;
                if(bus_io) begin
                    debug_io_pulse <= 1; debug_io_write <= bus_write;
                    debug_io_address <= {bus_address[15:1],!bus_select[0]};
                    debug_io_data <= bus_write ? bus_writedata : bus_readdata;
                end
            end
        end
    end
`ifdef ZET98_CD_TRACE
    // The CD/IO trace streamer takes the IDT gate reads in place of the address.
    wire [30:0] snapshot_address = {debug_gate, 13'b0};
`else
    wire [30:0] snapshot_address = physical_address;
`endif
    assign debug_snapshot = {debug_cpu_state[35:4], snapshot_address,1'b0,
        debug_io_address,debug_io_data,debug_completed,
        debug_io_pulse,debug_io_write,2'b0,debug_cpu_state[3:0],
        cache_invalidate,cpu_reset,interrupt_do,interrupt_done,
        bus_strobe,bus_ack,bus_io,crash_tx};   // bit 0: crash recorder UART (z486_crash_recorder)
`else
    assign debug_snapshot = 0;
`endif
    // Proven against the vendored Avalon generator by run-memory-mask-contract.sh.
    ao486_bus_bridge #(.READ_MASK_ALWAYS_NONZERO(1'b1), .MEMORY_QUEUE_BITS(MEMORY_QUEUE_BITS),
                      .EARLY_MEMORY_GRANT(EARLY_MEMORY_GRANT),
                      .WIDE_RAM_MB(NATIVE_DDR ? EXT_RAM_MB : 0),
                      .WIDE_RAM_ENABLE(NATIVE_DDR_RAM)) bridge (
        .clk(clk), .reset(cpu_reset),
        .avm_address(avm_address), .avm_writedata(avm_writedata), .avm_byteenable(avm_byteenable),
        .avm_burstcount(avm_burstcount), .avm_write(avm_write), .avm_read(avm_read),
        .avm_waitrequest(avm_waitrequest), .avm_readdatavalid(avm_readdatavalid), .avm_readdata(avm_readdata),
        .avm_write_done(memory_write_complete),
        .io_read_do(io_read_do), .io_read_address(io_read_address), .io_read_length(io_read_length),
        .io_read_data(io_read_data), .io_read_done(io_read_done), .io_write_do(io_write_do),
        .io_write_address(io_write_address), .io_write_length(io_write_length),
        .io_write_data(io_write_data), .io_write_done(io_write_done), .busy(fabric_busy),
        .bus_address(physical_address), .bus_select(bus_select), .bus_writedata(bus_writedata),
        .bus_write(bus_write), .bus_strobe(physical_strobe), .bus_io(bus_io),
        .bus_readdata(pegc_claimed ? pegc_readdata : legacy_mapped ? legacy_readdata : extended_mapped ? extended_readdata : 16'hffff),
        .bus_ack((legacy_mapped && legacy_ack) || pegc_ack || extended_ack || unmapped_access),
        .wide_linear_enable(pegc_linear_enable),.wide_backend_busy(wide_backend_busy),
        .wide_address(wide_address),.wide_writedata(wide_writedata),
        .wide_byteenable(wide_byteenable),.wide_burstcount(wide_burstcount),
        .wide_read(wide_read),.wide_write(wide_write),.wide_waitrequest(wide_waitrequest),
        .wide_readdatavalid(wide_readdatavalid),.wide_readdata(wide_readdata)
    );
    // synthesis translate_off
    always @(posedge clk) if(native_request && (legacy_ram_read || legacy_ram_write))
        $fatal(1,"native and halfword RAM commands overlapped");
    // synthesis translate_on
endmodule
