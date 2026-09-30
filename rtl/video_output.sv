// SPDX-License-Identifier: GPL-3.0-or-later
// Register pixel data, blanking and sync with their MiSTer clock enable.
// The diagnostic raster bypasses PC-98 text/graphics and SDRAM fetches while
// retaining the same video clock (63.158 MHz, 3 clocks per pixel) and
// MiSTer scaler/HDMI path. Its raster matches the PC-98 one: 848 x 440,
// 640 x 400 visible, 24.8 kHz / 56.4 Hz.
module video_output #(
    parameter BOOT_TEXT_FILE="../../rtl/assets/boot-text.mem",
    parameter BOOT_FONT_FILE="../../rtl/assets/boot-font.mem"
) (
    input wire clk, reset, test_pattern,
    input wire [2:0] boot_prompt,
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
    // Caller supplies a coherent snapshot in the video clock domain.
    reg [2:0] prompt_active;
    reg [1:0] divider;
    reg [9:0] x, y;
    wire pattern_ce = divider == 2;
    wire [2:0] bar = x < 80 ? 7 : x < 160 ? 6 : x < 240 ? 5 :
                     x < 320 ? 4 : x < 400 ? 3 : x < 480 ? 2 : x < 560 ? 1 : 0;
    wire pattern_de = x < 640 && y < 400;
    // A white border makes clipped edges apparent on a physical display.
    wire border = x < 2 || x >= 638 || y < 2 || y >= 398;
    // Two synchronous ROM reads complete within the three clocks per pixel.
    // Keep this prefetch separate from the RGB path and its raster selects.
    (* ramstyle="M10K" *) reg [6:0] boot_text[0:1023];
    (* ramstyle="M10K" *) reg [7:0] boot_font[0:1023];
    reg [6:0] character;
    reg [7:0] glyph_row;
    wire [1:0] page = prompt_active[1:0] - 2'd1;
    wire [8:0] text_x = x - 10'd64;
    wire [8:0] text_y = y - 10'd72;
    wire text_area = x>=64 && x<576 && y>=72 && y<328 && !text_y[4];
    wire ink = text_area && glyph_row[7-text_x[3:1]];
    initial begin
        $readmemh(BOOT_TEXT_FILE,boot_text);
        $readmemh(BOOT_FONT_FILE,boot_font);
    end
    always @(posedge clk) begin
        character <= boot_text[{page,text_y[7:5],text_x[8:4]}];
        glyph_row <= boot_font[{character,text_y[3:1]}];
    end
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            test_meta <= 0;
            test_sync <= 0;
            test_active <= 0;
            prompt_active <= 0;
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
                if (x == 847) begin
                    x <= 0;
                    if (y == 439) begin
                        y <= 0;
                        test_active <= test_sync || boot_prompt != 0;
                        prompt_active <= test_sync ? 3'd0 : boot_prompt;
                    end else y <= y + 1'b1;
                end else x <= x + 1'b1;
            end
            ce <= test_active ? pattern_ce : native_ce;
            if (test_active && pattern_ce) begin
                hs <= x >= 720 && x < 784;
                vs <= y >= 407 && y < 415;
                de <= pattern_de;
                if (prompt_active != 0) begin
                    r <= !pattern_de ? 0 : ink ? 8'he8 : 8'h08;
                    g <= !pattern_de ? 0 : ink ? 8'he8 : 8'h0c;
                    b <= !pattern_de ? 0 : ink ? 8'he8 : 8'h14;
                end else begin
                    r <= {8{pattern_de && (border || bar[2])}};
                    g <= {8{pattern_de && (border || bar[1])}};
                    b <= {8{pattern_de && (border || bar[0])}};
                end
            end else if (!test_active && native_ce) begin
                r <= native_r; g <= native_g; b <= native_b;
                hs <= native_hs; vs <= native_vs; de <= native_de;
            end
        end
    end
endmodule
