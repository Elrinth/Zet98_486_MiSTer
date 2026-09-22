/*
 * Copyright (c) 2014, Aleksander Osman
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

module decode_regs(
    input               clk,
    input               rst_n,
    
    input               dec_reset,
    
    input       [3:0]   fetch_valid,
    input       [63:0]  fetch,
    
    input       [3:0]   prefix_count,
    input       [3:0]   consume_count,
    input               consume_enabled,
    
    output      [3:0]   dec_acceptable,
    
    output reg  [95:0]  decoder,
    output reg  [3:0]   decoder_count
);

// The instruction-length and shift work is computed before the late
// microcode-ready decision. Selecting a completed result adds no pipeline
// stage and preserves the original buffer bits, count and fetch acceptance.
function [103:0] buffer_step;
    input [95:0] decoder;
    input [3:0] decoder_count, consume_count, prefix_count, fetch_valid;
    input [63:0] fetch;
    input dec_reset;
    reg [3:0] after_consume_count, acceptable_1, acceptable_2, dec_acceptable;
    reg [3:0] available, unsaturated_count;
    reg [4:0] total_count;
    reg [95:0] after_consume, decoder_next;
    reg [3:0] next_count;
    begin
        after_consume_count = decoder_count - consume_count;

        total_count         = prefix_count + decoder_count;

        //------------------------------------------------------------------------------

        // acceptable by decoder
        acceptable_1     = 4'd12 - decoder_count + consume_count;

        // acceptable by total instruction length
        acceptable_2     = (total_count < 5'd15)? 4'd15 - total_count[3:0] : 4'd0;

        dec_acceptable   = (dec_reset)?                      4'd0 :
                                  (acceptable_1 < acceptable_2)?    acceptable_1 : acceptable_2;

        // Prefix/fetch limits do not depend on the late consume count.
        // If buffer capacity wins, after_consume_count + acceptable_1 is
        // exactly 12 modulo 16, including otherwise unreachable encodings.
        // Select that constant after the capacity comparison instead of
        // putting another adder after the accepted-byte mux.
        available = (acceptable_2 < fetch_valid) ? acceptable_2 : fetch_valid;
        unsaturated_count = after_consume_count + available;

        //------------------------------------------------------------------------------

        after_consume =
            (consume_count == 4'd0)?            decoder :
            (consume_count == 4'd1)?  { 8'd0,   decoder[95:8] } :
            (consume_count == 4'd2)?  { 16'd0,  decoder[95:16] } :
            (consume_count == 4'd3)?  { 24'd0,  decoder[95:24] } :
            (consume_count == 4'd4)?  { 32'd0,  decoder[95:32] } :
            (consume_count == 4'd5)?  { 40'd0,  decoder[95:40] } :
            (consume_count == 4'd6)?  { 48'd0,  decoder[95:48] } :
            (consume_count == 4'd7)?  { 56'd0,  decoder[95:56] } :
            (consume_count == 4'd8)?  { 64'd0,  decoder[95:64] } :
            (consume_count == 4'd9)?  { 72'd0,  decoder[95:72] } :
            (consume_count == 4'd10)? { 80'd0,  decoder[95:80] } :
                                      { 88'd0,  decoder[95:88] };

        decoder_next =
            (after_consume_count == 4'd0)?   { 32'd0,fetch } :
            (after_consume_count == 4'd1)?   { 24'd0,fetch,       after_consume[7:0] } :
            (after_consume_count == 4'd2)?   { 16'd0,fetch,       after_consume[15:0] } :
            (after_consume_count == 4'd3)?   { 8'd0, fetch,       after_consume[23:0] } :
            (after_consume_count == 4'd4)?   {       fetch,       after_consume[31:0] } :
            (after_consume_count == 4'd5)?   {       fetch[55:0], after_consume[39:0] } :
            (after_consume_count == 4'd6)?   {       fetch[47:0], after_consume[47:0] } :
            (after_consume_count == 4'd7)?   {       fetch[39:0], after_consume[55:0] } :
            (after_consume_count == 4'd8)?   {       fetch[31:0], after_consume[63:0] } :
            (after_consume_count == 4'd9)?   {       fetch[23:0], after_consume[71:0] } :
            (after_consume_count == 4'd10)?  {       fetch[15:0], after_consume[79:0] } :
            (after_consume_count == 4'd11)?  {       fetch[7:0],  after_consume[87:0] } :
                                                                  after_consume;


        next_count = dec_reset ? 4'd0 :
                     (acceptable_1 < available) ? 4'd12 : unsaturated_count;
        buffer_step = {dec_acceptable, next_count, decoder_next};
    end
endfunction

wire [103:0] consume_step = buffer_step(decoder,decoder_count,consume_count,prefix_count,fetch_valid,fetch,dec_reset);
wire [103:0] stalled_step = buffer_step(decoder,decoder_count,4'd0,prefix_count,fetch_valid,fetch,dec_reset);
wire [103:0] selected_step = consume_enabled ? consume_step : stalled_step;
assign dec_acceptable = selected_step[103:100];
always @(posedge clk) begin
    if(!rst_n) begin
        decoder <= 96'd0;
        decoder_count <= 4'd0;
    end else begin
        decoder <= selected_step[95:0];
        decoder_count <= selected_step[99:96];
    end
end
endmodule
