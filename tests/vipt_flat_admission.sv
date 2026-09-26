// Self-authored formal model of the test-only flat-descriptor admission rule.
module vipt_flat_admission(
    input wire [31:0] offset,
    input wire [19:0] raw_limit,
    input wire granularity,
    input wire [1:0] size,
    output wire reference_fits,
    output wire candidate_fits,
    output wire flat_descriptor
);
    wire [31:0] effective_limit = granularity
        ? {raw_limit,12'hfff} : {12'h000,raw_limit};
    wire [1:0] extra = size[1] ? 2'd3 : size;
    wire [32:0] last_byte = {1'b0,offset}+{31'b0,extra};
    assign reference_fits = !last_byte[32] &&
                            last_byte[31:0] <= effective_limit;
    assign flat_descriptor = granularity && (&raw_limit);
    wire no_wrap = (size == 2'd0) ||
                   ((size == 2'd1) && offset != 32'hffffffff) ||
                   (size[1] && offset <= 32'hfffffffc);
    assign candidate_fits = flat_descriptor && no_wrap;
endmodule
