// SPDX-License-Identifier: GPL-3.0-or-later
// One shared activity badge, using the scaler's existing raster counters.
// Pixel/sync/CE latency is two clocks, including the single packed ROM read.
module storage_activity #(
    parameter HOLD_FRAMES=15,
    parameter ROM_FILE="../../rtl/assets/activity.mem"
) (
    input wire clk, reset,
    input wire enabled,
    input wire [1:0] floppy_read, floppy_write,
    input wire cd_read, hdd_read, hdd_write,
    input wire [11:0] x, y, width, height,
    input wire [11:0] crop_left, crop_top, crop_width, crop_height,
    input wire in_ce, in_hs, in_vs, in_de,
    input wire [7:0] in_r, in_g, in_b,
    output reg out_ce, out_hs, out_vs, out_de,
    output reg [7:0] out_r, out_g, out_b
);
    // Independent level flags, held throughout a device request. Synchronize
    // only their first destination stage asynchronously in the SDC.
    (* preserve, altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [7:0] request_meta, request_sync;
    always @(posedge clk) begin
        if (reset) begin request_meta<=0; request_sync<=0; end
        else begin
            request_meta<={enabled,hdd_write,hdd_read,cd_read,floppy_write,floppy_read};
            request_sync<=request_meta;
        end
    end
    // 0/1 loading D0/D1, 2/3 writing D0/D1, 4 CD, 5 HDD read, 6 HDD write.
    reg [2:0] selected, active;
    reg [6:0] pending;
    wire [6:0] requests=pending | request_sync[6:0];
    wire any_request=|requests;
    always @* begin
        if (requests[2]) selected=2;
        else if (requests[3]) selected=3;
        else if (requests[6]) selected=6;
        else if (requests[0]) selected=0;
        else if (requests[1]) selected=1;
        else if (requests[4]) selected=4;
        else selected=5;
    end
    reg [$clog2(HOLD_FRAMES+1)-1:0] hold_frames;
    // In this encoding bit 1 marks writes. Keep a short write visible even
    // when the controller immediately reads back data or reports busy.
    wire keep_write=active[1] && !selected[1] && hold_frames>1;
    reg old_vs;
    wire frame_start=in_ce && in_vs && !old_vs;
    reg [3:0] animation;
    reg [11:0] origin_x, origin_y;
    reg sized;
    wire cropped=|crop_width && |crop_height;
    wire [11:0] view_width=cropped ? crop_width : width;
    wire [11:0] view_height=cropped ? crop_height : height;
    always @(posedge clk) begin
        if (reset) begin
            old_vs<=0; hold_frames<=0; active<=0; animation<=0; pending<=0;
            origin_x<=0; origin_y<=0; sized<=0;
        end else begin
            if (in_ce) old_vs<=in_vs;
            pending<=frame_start ? 7'd0 : requests;
            if (frame_start && any_request && !keep_write) begin active<=selected; hold_frames<=HOLD_FRAMES; end
            else if (frame_start && hold_frames!=0) hold_frames<=hold_frames-1'b1;
            if (hold_frames==0) animation<=0;
            else if (frame_start) animation<=animation+1'b1;
            if (frame_start) begin
                origin_x<=(cropped ? crop_left : 12'd0)+view_width-12'd152;
                origin_y<=(cropped ? crop_top : 12'd0)+view_height-12'd52;
                sized<=view_width>=152 && view_height>=52;
            end
        end
    end
    wire [11:0] dx=x-origin_x, dy=y-origin_y;
    wire badge=request_sync[7] && sized && hold_frames!=0 && in_de;
    wire icon_area=badge && dx<32 && dy<32;
    wire text_area=badge && dx>=36 && dx<148 && dy>=12 && dy<20;
    wire [6:0] tx=dx[6:0]-7'd36;
    wire [3:0] character=tx[6:3];
    wire [2:0] row=dy[2:0]-3'd4;
    wire [1:0] kind=active<4 ? 2'd0 : active==4 ? 2'd1 : 2'd2;
    // Glyph order matches make_activity_rom.py: " LOADINGWRTEHC.01".
    function automatic [4:0] glyph(input [3:0] pos, input [2:0] device);
        reg wr, ld;
        begin
            wr=device==2 || device==3 || device==6;
            ld=device<2;
            case (pos)
                0: glyph=ld ? 1 : wr ? 8 : 9;  // L/W/R
                1: glyph=ld ? 2 : wr ? 9 : 11; // O/R/E
                2: glyph=wr ? 5 : 3;          // I/A
                3: glyph=wr ? 10 : 4;         // T/D
                4: glyph=5; 5: glyph=6; 6: glyph=7;
                8: glyph=device<4 ? 4 : device==4 ? 13 : 12;
                9: glyph=device<4 ? (device[0] ? 16 : 15) : 4;
                10: glyph=device>=5 ? 4 : 14;
                11,12: glyph=14;
                13: glyph=device>=5 ? 14 : 0;
                default: glyph=0;
            endcase
        end
    endfunction
    wire [1:0] bank=kind+2'd1;
    wire [9:0] rom_address=icon_area ?
        {bank,animation[3:2],dy[4:1],dx[4:3]} : {2'b00,glyph(character,active),row};
    (* ramstyle="M10K" *) reg [7:0] pixels[0:1023];
    initial $readmemh(ROM_FILE,pixels);
    reg [7:0] rom_data;
    always @(posedge clk) rom_data<=pixels[rom_address];
    function automatic [23:0] palette(input [1:0] k, input [1:0] pixel);
        case ({k,pixel})
            4'b0001: palette=24'ha0a0a8; 4'b0010: palette=24'h1c50ff;
            4'b0011: palette=24'hf4f4ff; 4'b0101: palette=24'hb894d8;
            4'b0110: palette=24'h40e0a0; 4'b0111: palette=24'he8e4f4;
            4'b1001: palette=24'h505058; 4'b1010: palette=24'hc0c0c8;
            default: palette=24'h40ff40;
        endcase
    endfunction
    reg ce1, icon1, text1;
    reg [2:0] sync1, column1;
    reg [23:0] rgb1;
    reg [1:0] kind1, pixel1;
    wire [1:0] icon_pixel=icon1 ? (rom_data >> {~pixel1,1'b0}) : 2'd0;
    wire text_pixel=text1 && rom_data[3'd7-column1];
    always @(posedge clk) begin
        if (reset) begin
            ce1<=0; out_ce<=0;
            sync1<=0; {out_hs,out_vs,out_de}<=0;
            rgb1<=0; {out_r,out_g,out_b}<=0;
            icon1<=0; text1<=0; column1<=0;
            kind1<=0; pixel1<=0;
        end else begin
            ce1<=in_ce; out_ce<=ce1;
            if (in_ce) begin
                sync1<={in_hs,in_vs,in_de}; rgb1<={in_r,in_g,in_b};
                icon1<=icon_area; text1<=text_area; column1<=tx[2:0];
                kind1<=kind; pixel1<=dx[2:1];
            end
            if (ce1) begin
                {out_hs,out_vs,out_de}<=sync1;
                {out_r,out_g,out_b}<=icon_pixel!=0 ? palette(kind1,icon_pixel) :
                    text_pixel ? 24'he8e8ff : rgb1;
            end
        end
    end
endmodule
