// SPDX-License-Identifier: GPL-3.0-or-later
// Register pixel data, blanking and sync with their MiSTer clock enable.
// The diagnostic raster bypasses PC-98 text/graphics and SDRAM fetches while
// retaining the same 75 MHz video clock and MiSTer scaler/HDMI path.
module video_output (
    input wire clk, reset, test_pattern,
    input wire native_ce,
    input wire [7:0] native_r, native_g, native_b,
    input wire native_hs, native_vs, native_de,
    output reg ce,
    output reg [7:0] r, g, b,
    output reg hs, vs, de
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg test_meta, test_sync;
    reg test_active;
    reg [1:0] divider;
    reg [9:0] x, y;
    wire pattern_ce = divider == 2;
    wire [2:0] bar = x < 80 ? 7 : x < 160 ? 6 : x < 240 ? 5 :
                     x < 320 ? 4 : x < 400 ? 3 : x < 480 ? 2 : x < 560 ? 1 : 0;
    wire pattern_de = x < 640 && y < 480;
    // A white border makes clipped edges apparent on a physical display.
    wire border = x < 2 || x >= 638 || y < 2 || y >= 478;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            test_meta <= 0;
            test_sync <= 0;
            test_active <= 0;
            divider <= 0;
            x <= 0;
            y <= 0;
            ce <= 0;
            r <= 0; g <= 0; b <= 0;
            hs <= 0; vs <= 0; de <= 0;
        end else begin
            test_meta <= test_pattern;
            test_sync <= test_meta;
            divider <= pattern_ce ? 0 : divider + 1'b1;
            if (pattern_ce) begin
                if (x == 799) begin
                    x <= 0;
                    if (y == 524) begin
                        y <= 0;
                        test_active <= test_sync;
                    end else y <= y + 1'b1;
                end else x <= x + 1'b1;
            end
            ce <= test_active ? pattern_ce : native_ce;
            if (test_active && pattern_ce) begin
                hs <= x >= 656 && x < 752;
                vs <= y >= 490 && y < 492;
                de <= pattern_de;
                r <= {8{pattern_de && (border || bar[2])}};
                g <= {8{pattern_de && (border || bar[1])}};
                b <= {8{pattern_de && (border || bar[0])}};
            end else if (!test_active && native_ce) begin
                r <= native_r; g <= native_g; b <= native_b;
                hs <= native_hs; vs <= native_vs; de <= native_de;
            end
        end
    end
endmodule
