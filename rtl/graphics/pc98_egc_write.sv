// SPDX-License-Identifier: GPL-3.0-or-later
// EGC write operands -> held affine SDRAM request. Not connected to the core yet.
// The caller supplies the already-advanced source shifter and its clip mask.
module pc98_egc_write (
    input wire [15:0] operation, color_select, cpu_writedata,
    input wire [63:0] shifted_source, pattern_words,
    input wire [63:0] foreground_words, background_words,
    input wire [15:0] pixel_mask, clip_mask,
    input wire [3:0] plane_enable,
    input wire [1:0] byte_enable,
    output wire [63:0] base_words, xor_mask_words,
    output wire load_pattern_on_write, configuration_valid
);
    wire [1:0] write_mode = operation[12:11];
    wire [1:0] pattern_load = operation[9:8];
    wire [1:0] color_mode = color_select[14:13];
    // Reserved encodings are observable to the caller and preserve VRAM.
    // They must not silently become ordinary CPU writes during integration.
    assign configuration_valid = write_mode != 3 && pattern_load != 3 && color_mode != 3;
    assign load_pattern_on_write = configuration_valid && pattern_load == 2;

    wire [63:0] selected_source = write_mode == 0 ? {4{cpu_writedata}} : shifted_source;
    // NP2's ROP read-load path uses the shifted source as P. Its pattern-only
    // write path uses the retained raw pattern. Keep that distinction explicit.
    wire [63:0] selected_pattern = color_mode == 1 ? background_words :
        color_mode == 2 ? foreground_words :
        (write_mode == 1 && pattern_load == 1) ? shifted_source : pattern_words;
    wire [7:0] selected_operation = write_mode == 0 ? 8'hf0 :
        write_mode == 1 ? operation[7:0] : 8'haa;

    // Loading a pattern at the destination write means P is the fresh D that
    // SDRAMC will read, not a CPU-side word left over from a previous access.
    // Substitute P=D in the truth table before computing coefficients. This
    // keeps the current memory-side read/modify/write transaction sufficient.
    wire destination_pattern = color_mode == 0 && pattern_load == 2;
    wire [7:0] effective_operation = destination_pattern ?
        { {2{selected_operation[7]}}, {2{selected_operation[4]}},
          {2{selected_operation[3]}}, {2{selected_operation[0]}} } : selected_operation;
    wire [63:0] unused_result;
    pc98_egc_rop raster (
        .operation(effective_operation), .source_words(selected_source),
        .pattern_words(selected_pattern), .destination_words(64'b0),
        .bit_mask(pixel_mask & clip_mask), .byte_enable(byte_enable),
        .plane_enable(plane_enable & {4{configuration_valid}}),
        .base_words(base_words), .xor_mask_words(xor_mask_words),
        .result_words(unused_result)
    );
endmodule
