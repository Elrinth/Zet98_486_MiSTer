// SPDX-License-Identifier: GPL-3.0-or-later
// Monochrome LCD/plasma display (OSD). PC-98 laptops and plasma models show
// colours as grey levels; games such as YU-NO offer a palette made for them.
// Same mapping as NP2kai's LCD mode (vram/palettes.c pal_initlcdtable): each
// channel's top four bits give three levels (thresholds 4 and 11), the 27
// combinations select one of 15 grey shades. Combinational: no added latency.
module lcd_mono (
    input  wire enable,
    input  wire [7:0] in_r, in_g, in_b,
    output wire [7:0] out_r, out_g, out_b
);
    function automatic [1:0] level(input [3:0] c);
        level = c >= 4'd11 ? 2'd2 : c >= 4'd4 ? 2'd1 : 2'd0;
    endfunction
    wire [4:0] index = level(in_b[7:4]) + 5'd3*level(in_r[7:4]) + 5'd9*level(in_g[7:4]);
    reg [3:0] shade;
    always @* begin
        case (index)  // NP2kai lcdpal_a
            5'd0: shade=0;  5'd1: shade=1;  5'd2: shade=2;  5'd3: shade=3;
            5'd4: shade=5;  5'd5: shade=2;  5'd6: shade=4;  5'd7: shade=4;
            5'd8: shade=6;  5'd9: shade=7;  5'd10: shade=9; 5'd11: shade=2;
            5'd12: shade=11; 5'd13: shade=13; 5'd14: shade=2; 5'd15: shade=4;
            5'd16: shade=4; 5'd17: shade=6; 5'd18: shade=8; 5'd19: shade=8;
            5'd20: shade=10; 5'd21: shade=8; 5'd22: shade=8; 5'd23: shade=10;
            5'd24: shade=12; 5'd25: shade=12; 5'd26: shade=14;
            default: shade=14;
        endcase
    end
    // 15 levels from black to white: shade * 255 / 14, rounded.
    wire [7:0] grey = {shade,4'b0} + {3'b0,shade,1'b0} + (shade >> 2);
    assign out_r = enable ? grey : in_r;
    assign out_g = enable ? grey : in_g;
    assign out_b = enable ? grey : in_b;
endmodule
