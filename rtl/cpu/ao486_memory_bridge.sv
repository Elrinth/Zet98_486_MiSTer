// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// ao486 memory master to a single-transfer, 16-bit memory fabric.
//
// Interface contract: MiSTer ao486 9d888c485bcf2e781824b303588668529a02015e.
// avm_address is DWORD addressed, bus_address is WORD addressed. Retain all
// physical address bits here; PC-98 address decoding/BIOS aliases belong outside.
// ao486 emits read bursts of 1..8 DWORDs and only SINGLE-beat writes. On writes
// burstcount can reflect a pending read, so it must be ignored. Its code
// fetches always use eight DWORDs and their byte enables are not reliable.
// Multi-beat data reads also share one initial mask across the whole burst.
// Only single-beat reads have a usable mask: omit an unused halfword there.
// Return FFFF in an omitted halfword. A zero mask retains the full-read fallback.
// Writes honour every byte enable, including skipping empty halfwords.
//
// One command is outstanding at a time. Writes are accepted into this module
// before the legacy transfer completes. Integration must drain outstanding
// memory writes before allowing a later I/O command to reach the peripherals.
// ACK must fall between legacy transfers. All ports share clk; this module
// does not provide CDC, arbitration, cache/DMA coherence or address mapping.
// Used by the opt-in ao486 build; the default CPU remains Zet.
module ao486_memory_bridge #(
    parameter NARROW_READS = 1'b1,
    parameter SKIP_EMPTY_HALVES = 1'b1,
    parameter READ_MASK_ALWAYS_NONZERO = 1'b0
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
    output reg         avm_readdatavalid,
    output reg  [31:0] avm_readdata,
    output wire        busy,

    output wire [31:1] bus_address,
    output wire [1:0]  bus_select,
    output wire [15:0] bus_writedata,
    output wire        bus_write,
    output wire        bus_strobe,
    input  wire [15:0] bus_readdata,
    input  wire        bus_ack
);
    localparam IDLE = 2'd0, TRANSFER = 2'd1, RELEASE = 2'd2;
    reg [1:0] state;
    reg [29:0] address;
    reg [31:0] write_data;
    reg [3:0] byte_enable;
    reg [3:0] remaining;
    reg write_request;
    reg high_half;
    reg [15:0] read_low;
    wire [1:0] half_select = high_half ? byte_enable[3:2] : byte_enable[1:0];
    wire skip_half = half_select == 0;
    wire [3:0] request_enable = avm_write ||
        (NARROW_READS && avm_burstcount == 1 &&
         (READ_MASK_ALWAYS_NONZERO || avm_byteenable != 0))
        ? avm_byteenable : 4'b1111;
    // The actual ao486 Avalon generator never emits an empty read mask.
    // Its length-dependent upper lanes need not reach the first-half decision.
    // Keep the zero-mask fallback for other masters/default configurations.
    wire first_high_half = SKIP_EMPTY_HALVES && avm_byteenable[1:0] == 0 &&
        (avm_write || (NARROW_READS && avm_burstcount == 1 &&
                      (READ_MASK_ALWAYS_NONZERO || avm_byteenable[3:2] != 0)));
    wire last_half = high_half || (SKIP_EMPTY_HALVES && byte_enable[3:2] == 0);

    assign busy = state != IDLE;
    assign avm_waitrequest = reset || busy || bus_ack;
    assign bus_address = {address, high_half};
    assign bus_strobe = state == TRANSFER && !skip_half && !reset;
    assign bus_select = !bus_strobe ? 2'b00 : write_request ? half_select : 2'b11;
    assign bus_writedata = high_half ? write_data[31:16] : write_data[15:0];
    assign bus_write = write_request;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            address <= 0;
            write_data <= 0;
            byte_enable <= 0;
            remaining <= 0;
            write_request <= 0;
            high_half <= 0;
            read_low <= 0;
            avm_readdata <= 0;
            avm_readdatavalid <= 0;
        end else begin
            avm_readdatavalid <= 0;
            case (state)
                IDLE: if ((avm_read || avm_write) && !avm_waitrequest) begin
                    address <= avm_address;
                    write_data <= avm_writedata;
                    byte_enable <= request_enable;
                    remaining <= avm_write ? 4'd1 : avm_burstcount;
                    write_request <= avm_write;
                    // Byte/word operations need no transfer/release states
                    // for a halfword that has no selected bytes. ACK release
                    // is still required after every actual legacy transfer.
                    high_half <= first_high_half;
                    read_low <= 16'hffff;
                    state <= TRANSFER;
                end
                TRANSFER: if (skip_half || bus_ack) begin
                    if (!write_request) begin
                        if (!high_half) read_low <= skip_half ? 16'hffff : bus_readdata;
                        if (last_half) begin
                            avm_readdata <= high_half ?
                                {skip_half ? 16'hffff : bus_readdata, read_low} :
                                {16'hffff, skip_half ? 16'hffff : bus_readdata};
                            avm_readdatavalid <= 1;
                        end
                    end
                    high_half <= !last_half;
                    if (last_half) begin
                        remaining <= remaining - 1'b1;
                        address <= address + 1'b1;
                    end
                    state <= RELEASE;
                end
                RELEASE: if (!bus_ack)
                    state <= remaining == 0 ? IDLE : TRANSFER;
                default: state <= IDLE;
            endcase
        end
    end

    // synthesis translate_off
    always @(posedge clk) if (!avm_waitrequest && (avm_read || avm_write)) begin
        if (avm_read && avm_write) $fatal(1, "simultaneous memory read/write");
        if (avm_read && (avm_burstcount == 0 || avm_burstcount > 8))
            $fatal(1, "ao486 read burst must contain 1..8 DWORDs");
        if (READ_MASK_ALWAYS_NONZERO && avm_read && avm_byteenable == 0)
            $fatal(1, "ao486 nonzero read-mask contract violated");
    end
    // synthesis translate_on
endmodule
