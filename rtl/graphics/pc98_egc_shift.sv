// SPDX-License-Identifier: GPL-3.0-or-later
// Four-plane EGC word shifter. Native CPU byte order, not display bit order.
// advance is one accepted source word (VRAM read or CPU write, chosen upstream).
// The result/mask stays latched until the next advance or explicit reload.
module pc98_egc_shift (
    input  wire        clk, reset, reload, advance,
    input  wire [15:0] shift_control, bit_length,
    input  wire [63:0] source_words,
    output reg  [63:0] shifted_words,
    output reg  [15:0] clip_mask,
    output reg         result_valid
);
    // At most fifteen unconsumed pixels remain after a word is emitted.
    // Keep them in traversal order, bit zero being the next source pixel.
    reg [15:0] pending [0:3];
    reg [4:0] pending_count;
    reg [3:0] source_skip, destination_skip;
    reg [12:0] remaining;
    wire reverse = shift_control[12];
    wire [4:0] needed = 5'd16 - {1'b0, destination_skip};
    wire [5:0] available = {1'b0, pending_count} +
                            (6'd16 - {2'b0, source_skip});
    wire enough = available >= {1'b0, needed};
    wire row_done = remaining <= {8'b0, needed};
    wire [63:0] traversed;
    wire [31:0] joined [0:3];
    wire [15:0] positioned [0:3];
    wire [63:0] next_words;
    wire [15:0] traversal_mask, next_mask;

    genvar p, b;
    generate for (p=0; p<4; p=p+1) begin: planes
        for (b=0; b<16; b=b+1) begin: pixels
            // Forward: low byte MSB first, then high byte MSB first.
            // Reverse: high byte LSB first, then low byte LSB first.
            localparam integer FORWARD_BIT = (b < 8) ? 7-b : 23-b;
            localparam integer REVERSE_BIT = (b < 8) ? b+8 : b-8;
            assign traversed[16*p+b] = reverse ?
                source_words[16*p+REVERSE_BIT] : source_words[16*p+FORWARD_BIT];
            assign next_words[16*p+b] = reverse ?
                positioned[p][REVERSE_BIT] : positioned[p][FORWARD_BIT];
        end
        assign joined[p] = {16'b0, pending[p]} |
            ({16'b0, (traversed[16*p +:16] >> source_skip)} << pending_count);
        assign positioned[p] = joined[p][15:0] << destination_skip;
    end
    for (b=0; b<16; b=b+1) begin: masks
        localparam integer FORWARD_BIT = (b < 8) ? 7-b : 23-b;
        localparam integer REVERSE_BIT = (b < 8) ? b+8 : b-8;
        assign traversal_mask[b] = (b >= destination_skip) &&
                                   ((b - destination_skip) < remaining);
        assign next_mask[b] = reverse ? traversal_mask[REVERSE_BIT] :
                                      traversal_mask[FORWARD_BIT];
    end endgenerate

    integer plane;
    always @(posedge clk) begin
        if (reset || reload) begin
            for (plane=0; plane<4; plane=plane+1) pending[plane] <= 0;
            pending_count <= 0;
            source_skip <= shift_control[3:0];
            destination_skip <= shift_control[7:4];
            remaining <= {1'b0, bit_length[11:0]} + 13'd1;
            shifted_words <= 0;
            clip_mask <= 0;
            result_valid <= 0;
        end else if (advance) begin
            if (!enough) begin
                // Priming read: retain all pixels and leave destination intact.
                for (plane=0; plane<4; plane=plane+1)
                    pending[plane] <= joined[plane][15:0];
                pending_count <= available[4:0];
                source_skip <= 0;
                clip_mask <= 0;
                result_valid <= 0;
            end else begin
                shifted_words <= next_words;
                clip_mask <= next_mask;
                result_valid <= 1;
                if (row_done) begin
                    // The final result remains available for its VRAM write,
                    // while the input state is ready for the next scanline.
                    for (plane=0; plane<4; plane=plane+1) pending[plane] <= 0;
                    pending_count <= 0;
                    source_skip <= shift_control[3:0];
                    destination_skip <= shift_control[7:4];
                    remaining <= {1'b0, bit_length[11:0]} + 13'd1;
                end else begin
                    for (plane=0; plane<4; plane=plane+1)
                        pending[plane] <= joined[plane] >> needed;
                    pending_count <= available - {1'b0, needed};
                    source_skip <= 0;
                    destination_skip <= 0;
                    remaining <= remaining - {8'b0, needed};
                end
            end
        end
    end
endmodule
