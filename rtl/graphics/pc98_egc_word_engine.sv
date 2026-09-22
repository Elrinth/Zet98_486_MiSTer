// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental aligned-word EGC client for SDRAMC's CPU read4/affine-RMW4 port.
// Not in the active QSF. Byte transactions report a fault without issuing SDRAM.
module pc98_egc_word_engine #(
    parameter integer ADDRESS_WIDTH = 22
) (
    input wire clk, reset, egc_enable,
    input wire [15:1] io_address,
    input wire [1:0] io_select,
    input wire [15:0] io_writedata,
    input wire io_strobe, io_write,
    input wire request, request_write,
    input wire [ADDRESS_WIDTH-1:0] request_address,
    input wire [1:0] request_bank, request_bytes,
    input wire [15:0] request_writedata,
    output wire busy,
    output reg acknowledge, fault,
    output reg [15:0] readdata,
    output reg [ADDRESS_WIDTH-1:0] memory_address,
    output reg [1:0] memory_bank,
    output wire memory_read4, memory_rmw4,
    output reg [1:0] memory_bytes,
    output reg [3:0] memory_planes,
    output reg [63:0] memory_base, memory_xor_mask,
    input wire memory_acknowledge,
    input wire [63:0] memory_readdata
);
    localparam [3:0] IDLE=0, READ_MEMORY=1, READ_RESULT=2,
        WRITE_SHIFT=3, WRITE_BUILD=4, WRITE_MEMORY=5, RELEASE=6, REJECT=7;
    reg [3:0] state;
    wire [15:0] access_control, color_select, operation, foreground, pixel_mask,
        background, shift_control, bit_length;
    wire [63:0] foreground_words, background_words;
    wire shift_reload;
    pc98_egc_registers registers (
        .clk(clk), .reset(reset), .egc_enable(egc_enable),
        .io_address(io_address), .io_select(io_select), .io_writedata(io_writedata),
        .io_strobe(io_strobe), .io_write(io_write), .port_selected(),
        .access_control(access_control), .color_select(color_select), .operation(operation),
        .foreground(foreground), .pixel_mask(pixel_mask), .background(background),
        .shift_control(shift_control), .bit_length(bit_length),
        .foreground_words(foreground_words), .background_words(background_words),
        .write_committed(), .shift_reload(shift_reload), .operation_written()
    );
    reg [15:0] transfer_operation, transfer_color, transfer_pixel_mask, transfer_cpu;
    reg [63:0] transfer_foreground, transfer_background;
    reg [1:0] transfer_plane;
    reg [63:0] pattern_latch, returned_words, retained_source;
    reg source_advanced;
    wire source_from_read = state == READ_MEMORY && memory_acknowledge && !transfer_operation[10];
    wire shift_advance = state == WRITE_SHIFT || source_from_read;
    wire [63:0] shift_input = state == WRITE_SHIFT ? {4{transfer_cpu}} : memory_readdata;
    wire [63:0] shifted_words;
    wire [15:0] shifted_clip;
    pc98_egc_shift shifter (
        .clk(clk), .reset(reset), .reload(shift_reload), .advance(shift_advance),
        .shift_control(shift_control), .bit_length(bit_length), .source_words(shift_input),
        .shifted_words(shifted_words), .clip_mask(shifted_clip), .result_valid()
    );
    // Register reload restarts alignment but does not discard the previously
    // latched source. The shifter's first real transfer may then prime a row.
    wire [63:0] selected_source = source_advanced ? shifted_words : retained_source;
    wire [15:0] selected_clip = source_advanced ? shifted_clip : 16'hffff;
    wire [63:0] next_base, next_mask;
    wire load_on_write, valid_configuration;
    pc98_egc_write write_operands (
        .operation(transfer_operation), .color_select(transfer_color),
        .cpu_writedata(transfer_cpu), .shifted_source(selected_source),
        .pattern_words(pattern_latch), .foreground_words(transfer_foreground),
        .background_words(transfer_background), .pixel_mask(transfer_pixel_mask),
        .clip_mask(selected_clip), .plane_enable(memory_planes), .byte_enable(memory_bytes),
        .base_words(next_base), .xor_mask_words(next_mask),
        .load_pattern_on_write(load_on_write), .configuration_valid(valid_configuration)
    );
    assign busy = state != IDLE;
    assign memory_read4 = state == READ_MEMORY;
    assign memory_rmw4 = state == WRITE_MEMORY;
    always @(posedge clk) begin
        if (reset) begin
            state<=IDLE; acknowledge<=0; fault<=0; readdata<=0;
            memory_address<=0; memory_bank<=0; memory_bytes<=0; memory_planes<=0;
            memory_base<=0; memory_xor_mask<=64'hffffffffffffffff;
            transfer_operation<=0; transfer_color<=0; transfer_pixel_mask<=0;
            transfer_cpu<=0; transfer_foreground<=0; transfer_background<=0;
            transfer_plane<=0; pattern_latch<=0; returned_words<=0;
            retained_source<=0; source_advanced<=0;
        end else begin
            acknowledge<=0; fault<=0;
            if (shift_reload) source_advanced<=0;
            else if (shift_advance) source_advanced<=1;
            case (state)
                IDLE: if (request) begin
                    // The CPU request may remain asserted until ACK; no live
                    // request metadata is used after this acceptance edge.
                    memory_address<={request_address[ADDRESS_WIDTH-1:2],2'b00};
                    memory_bank<=request_bank;
                    memory_bytes<=request_bytes;
                    memory_planes<=~access_control[3:0];
                    transfer_plane<=request_address[1:0];
                    transfer_cpu<=request_writedata;
                    transfer_operation<=operation; transfer_color<=color_select;
                    transfer_pixel_mask<=pixel_mask;
                    transfer_foreground<=foreground_words; transfer_background<=background_words;
                    if (!egc_enable || request_bytes != 2'b11) state<=REJECT;
                    else if (!request_write) state<=READ_MEMORY;
                    else if (operation[12:11] != 1 || operation[10]) state<=WRITE_SHIFT;
                    else state<=WRITE_BUILD;
                end
                READ_MEMORY: if (memory_acknowledge) begin
                    returned_words<=memory_readdata;
                    if (transfer_operation[9:8] == 1) pattern_latch<=memory_readdata;
                    state<=READ_RESULT;
                end
                READ_RESULT: begin
                    // NP2's native word-read convention. Compare-mode behavior
                    // differs in other references and remains an integration gate.
                    if (transfer_operation[13])
                        readdata<=returned_words[16*transfer_plane +:16];
                    else if (transfer_operation[10])
                        readdata<=returned_words[16*transfer_color[9:8] +:16];
                    else readdata<=selected_source[16*transfer_color[9:8] +:16];
                    if (!transfer_operation[10]) retained_source<=shifted_words;
                    acknowledge<=1; state<=RELEASE;
                end
                WRITE_SHIFT: state<=WRITE_BUILD;
                WRITE_BUILD: begin
                    // Coefficients stay held throughout arbitrary memory waits.
                    memory_base<=next_base; memory_xor_mask<=next_mask;
                    if (source_advanced) retained_source<=shifted_words;
                    if (valid_configuration) state<=WRITE_MEMORY;
                    else state<=REJECT;
                end
                WRITE_MEMORY: if (memory_acknowledge) begin
                    // SDRAMC returns the old destination used for this RMW,
                    // including when every byte/plane was masked from writing.
                    if (load_on_write) pattern_latch<=memory_readdata;
                    acknowledge<=1; state<=RELEASE;
                end
                RELEASE: if (!request) state<=IDLE;
                REJECT: begin acknowledge<=1; fault<=1; readdata<=16'hffff; state<=RELEASE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
