// Isolated timing microbenchmark. Not a core and not intended for hardware.
module segment_compare_timing #(parameter FORM=0)(
    input wire clk, offset_bit, limit_bit,
    input wire [1:0] size_in,
    output wire accepted
);
    (* preserve *) reg [31:0] offset_r, limit_r;
    (* preserve *) reg [1:0] size_r;
    (* preserve *) reg accepted_r;
    wire fits;
    vipt_segment_compare #(.STRUCTURED(FORM)) comparison(offset_r,limit_r,size_r,fits);
    always @(posedge clk) begin
        offset_r <= {offset_r[30:0],offset_bit};
        limit_r <= {limit_r[30:0],limit_bit};
        size_r <= size_in;
        accepted_r <= fits;
    end
    assign accepted=accepted_r;
endmodule
