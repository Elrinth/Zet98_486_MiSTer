// Self-authored isolated comparison experiment, not production CPU RTL.
module vipt_segment_compare #(parameter STRUCTURED=0)(
    input wire [31:0] offset, limit,
    input wire [1:0] size,
    output wire fits
);
genvar b;
generate if (!STRUCTURED) begin : sum_form
    wire [1:0] extra = size[1] ? 2'd3 : size;
    wire [32:0] last_byte = {1'b0,offset}+{31'b0,extra};
    assign fits = !last_byte[32] && last_byte[31:0] <= limit;
end else begin : parallel_form
    // Prepare boundary endpoints from the descriptor side. The late effective
    // address passes through byte comparisons/equality rather than an adder.
    wire [31:0] previous1=limit-32'd1, previous2=limit-32'd2;
    wire [3:0] gt, eq;
    for(b=0;b<4;b=b+1) begin : bytes
        assign gt[b]=offset[8*b+:8]>limit[8*b+:8];
        assign eq[b]=offset[8*b+:8]==limit[8*b+:8];
    end
    wire outside=gt[3] || (eq[3]&&gt[2]) ||
                 (&eq[3:2]&&gt[1]) || (&eq[3:1]&&gt[0]);
    wire crosses=((offset==limit)&&(size!=0)) ||
                 ((offset==previous1)&&size[1]) ||
                 ((offset==previous2)&&size[1]);
    assign fits=!outside&&!crosses;
end endgenerate
endmodule
