// SPDX-License-Identifier: GPL-3.0-or-later
// EGC boolean operation kernel. Plane order is B,R,G,E in ascending words.
// EGC's operation-bit index is {source, destination, pattern}.
// This kernel is not yet connected to the core's bus or advertised as EGC.
module pc98_egc_rop (
    input  wire [7:0]  operation,
    input  wire [63:0] source_words, pattern_words, destination_words,
    input  wire [15:0] bit_mask,
    input  wire [1:0]  byte_enable,
    input  wire [3:0]  plane_enable,
    output wire [63:0] base_words, xor_mask_words,
    output wire [63:0] result_words
);
    wire [15:0] enabled_bits = bit_mask &
        {{8{byte_enable[1]}}, {8{byte_enable[0]}}};
    genvar bit_index;
    generate for (bit_index=0; bit_index<64; bit_index=bit_index+1) begin: bits
        wire enabled = plane_enable[bit_index/16] & enabled_bits[bit_index%16];
        wire when_zero = operation[{source_words[bit_index], 1'b0, pattern_words[bit_index]}];
        wire when_one  = operation[{source_words[bit_index], 1'b1, pattern_words[bit_index]}];
        // For fixed source/pattern, every boolean operation is affine in its
        // one destination bit: f(D)=f(0) XOR (D AND (f(0) XOR f(1))). This lets
        // future bus integration snapshot operands before the SDRAM RMW read.
        assign base_words[bit_index] = enabled & when_zero;
        assign xor_mask_words[bit_index] = !enabled | (when_zero ^ when_one);
    end endgenerate
    assign result_words = base_words ^ (destination_words & xor_mask_words);
endmodule
