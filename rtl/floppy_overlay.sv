// SPDX-License-Identifier: GPL-3.0-or-later
// Drive access captions with cycling dots: "READING D0..." / "WRITING D1..."
// at the lower right while a floppy is accessed, "READING CD..." while the
// CD-ROM reads data or plays CD audio, and "READING HDD..." / "WRITING HDD..."
// while the IDE hard disk is accessed: HDD lower left, CD left of the floppy,
// all on the same rows (the second layout was removed to free FPGA area). A
// 16x16 eight-frame icon (turning floppy, spinning CD, hard disk with a blinking
// LED; scripts/make_overlay_icons.py), shown at 2x, goes with each caption.
// Each device has its own enable (core menu). (WRITING while the drive's image is
// being written back). (The animated disk icon was removed to
// free FPGA area.) A three-clock pipeline keeps font pixels, RGB, blanking,
// sync and CE aligned.
module floppy_overlay #(
    parameter HOLD_FRAMES=15,
    parameter ANIMATION_CYCLES=3000000, // 40 ms at the 75 MHz video clock.
    parameter FONT_FILE="../../rtl/assets/boot-font.mem",
    parameter ICON_FILE="../../rtl/assets/overlay-icons.mem"
) (
    input wire clk, reset, enabled, cd_enabled, hdd_enabled,
    input wire icons_enabled,      // off: captions only
    input wire [1:0] activity,
    input wire [1:0] writing,      // image write-back per drive (subset of activity)
    input wire [1:0] cd_activity,  // CD-ROM: [0] data read, [1] CD audio playing
    input wire hdd_activity, hdd_writing,   // IDE hard-disk image requests
    input wire [11:0] crop_left, crop_top, crop_width, crop_height,
    input wire in_ce, in_hs, in_vs, in_de,
    input wire [7:0] in_r, in_g, in_b,
    output reg out_ce, out_hs, out_vs, out_de,
    output reg [7:0] out_r, out_g, out_b
);
    (* preserve, altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] activity_meta, activity_sync, writing_meta, writing_sync, cd_meta, cd_sync;
    reg [1:0] hdd_meta, hdd_sync, en_meta, en_sync;
    reg icons_meta, icons_sync;
    reg [$clog2(HOLD_FRAMES+1)-1:0] cd_hold, hdd_hold;
    reg hdd_write_mode;
    reg [11:0] hbox_left, hbox_right, hicon_left, hicon_right;
    reg [6:0] hdd_origin_x;
    reg [11:0] left_edge, cd_left, cd_right;
    reg [6:0] cd_origin_x;
    reg [11:0] ficon_left, ficon_right, cicon_left, cicon_right, icon_top, icon_bottom;
    reg write_mode;
    (* preserve, altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg enabled_meta, enabled_sync;
    reg prev_de,prev_vs,sized,drive;
    reg [11:0] x,y,max_width,width,height;
    reg [$clog2(HOLD_FRAMES+1)-1:0] hold_frames;
    reg [22:0] animation_ticks;
    reg [4:0] dot_phase;
    wire frame_start=in_ce && in_vs && !prev_vs;
    // Position changes only in vertical blank. Pipeline crop validation and
    // rectangle arithmetic before the per-pixel font/ROM path; combining all
    // three made the crop-to-caption path exceed the 75 MHz clock period.
    reg [1:0] position_pending;
    reg [12:0] crop_right_sum,crop_bottom_sum;
    reg crop_large;
    reg [11:0] right_edge,bottom_edge,box_left,box_right,box_top,box_bottom;
    reg [6:0] text_origin_x;
    wire crop_valid=crop_large && crop_right_sum<=width && crop_bottom_sum<=height;
    wire box=enabled_sync && sized && hold_frames!=0 && in_de &&
        x>=box_left && x<box_right && y>=box_top && y<box_bottom;
    wire cd_box=en_sync[0] && sized && cd_hold!=0 && in_de &&
        x>=cd_left && x<cd_right && y>=box_top && y<box_bottom;
    wire hdd_box=en_sync[1] && sized && hdd_hold!=0 && in_de &&
        x>=hbox_left && x<hbox_right && y>=box_top && y<box_bottom;
    wire [6:0] dx=x-(hdd_box ? hbox_left : cd_box ? cd_left : box_left);
    wire [6:0] dy=y-box_top;
    wire icon_rows=icons_sync && sized && in_de && y>=icon_top && y<icon_bottom;
    wire ficon=icon_rows && enabled_sync && hold_frames!=0 && x>=ficon_left && x<ficon_right;
    wire cicon=icon_rows && en_sync[0] && cd_hold!=0 && x>=cicon_left && x<cicon_right;
    wire hicon=icon_rows && en_sync[1] && hdd_hold!=0 && x>=hicon_left && x<hicon_right;
    wire [4:0] icon_x=x[4:0]-(cicon ? cicon_left[4:0] : hicon ? hicon_left[4:0] : ficon_left[4:0]);
    wire [4:0] icon_y=y[4:0]-icon_top[4:0];
    // Reuse the core boot-help font, with one byte per 8x8 character row.
    // The caption background stays transparent.
    function automatic [6:0] caption_ascii(input [3:0] position,
        input selected_drive,input write,input [1:0] dots,input cd,input hdd);
        case(position)
            0: caption_ascii=write ? "W" : "R";
            1: caption_ascii=write ? "R" : "E";
            2: caption_ascii=write ? "I" : "A";
            3: caption_ascii=write ? "T" : "D";
            4: caption_ascii="I";
            5: caption_ascii="N";
            6: caption_ascii="G";
            8: caption_ascii=hdd ? "H" : cd ? "C" : "D";
            9: caption_ascii=hdd || cd ? "D" : selected_drive ? "1" : "0";
            10: caption_ascii=hdd ? "D" : dots!=0 ? "." : " ";
            11,12: caption_ascii=position-(hdd ? 11 : 10)<dots ? "." : " ";
            13: caption_ascii=hdd && dots==3 ? "." : " ";
            default: caption_ascii=" ";
        endcase
    endfunction
    wire [6:0] tx=x[6:0]-(hdd_box ? hdd_origin_x : cd_box ? cd_origin_x : text_origin_x);
    wire [3:0] character=tx[6:3];
    wire [2:0] column=tx[2:0];
    wire [2:0] font_row_address=dy[2:0];
    wire [6:0] font_character=caption_ascii(character,drive,
        hdd_box ? hdd_write_mode : write_mode && !cd_box,dot_phase[4:3],cd_box,hdd_box);
    wire text_area=(box || cd_box || hdd_box) && dx>=2 && dx<(hdd_box ? 114 : 106) && dy<8;
    (* ramstyle="M10K" *) reg [7:0] boot_font[0:1023];
    reg [7:0] font_row;
    reg [2:0] text_column;
    initial $readmemh(FONT_FILE,boot_font);
    always @(posedge clk) font_row<=boot_font[{font_character,font_row_address}];
    // {icon, frame, row, column}; 2x scaled; 8 frames over 32 animation steps.
    (* ramstyle="M10K" *) reg [1:0] icons[0:6143];
    reg [1:0] icon_pixel;
    initial $readmemh(ICON_FILE,icons);
    wire [1:0] icon_kind={hicon,cicon};     // 0 floppy, 1 CD, 2 HDD
    always @(posedge clk) icon_pixel<=icons[{icon_kind,dot_phase[4:2],icon_y[4:1],icon_x[4:1]}];
    reg icon_pipe;
    reg [1:0] icon_kind_pipe, icon_kind_pipe2;
    reg [1:0] icon_pipe2;
    // Per-icon palettes: floppy grey/blue/white, CD lilac/rainbow/silver,
    // HDD dark grey/silver/green LED.
    function automatic [23:0] icon_color(input [1:0] kind, input [1:0] index);
        case({kind,index})
            4'b0001: icon_color=24'ha0a0a8;
            4'b0010: icon_color=24'h1c50ff;
            4'b0011: icon_color=24'hf4f4ff;
            4'b0101: icon_color=24'hb894d8;
            4'b0110: icon_color=24'h40e0a0;
            4'b0111: icon_color=24'he8e4f4;
            4'b1001: icon_color=24'h505058;
            4'b1010: icon_color=24'hc0c0c8;
            default: icon_color=24'h40ff40;
        endcase
    endfunction
    reg ce_pipe,hs_pipe,vs_pipe,de_pipe,box_pipe,text_pipe;
    reg [23:0] rgb_pipe;
    reg ce_pipe2,hs_pipe2,vs_pipe2,de_pipe2,box_pipe2,text_pipe2;
    reg [23:0] rgb_pipe2;
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            activity_meta<=0;activity_sync<=0;enabled_meta<=0;enabled_sync<=0;
            writing_meta<=0;writing_sync<=0;write_mode<=0;
            cd_meta<=0;cd_sync<=0;cd_hold<=0;
            left_edge<=0;cd_left<=0;cd_right<=0;cd_origin_x<=7'd6;
            ficon_left<=0;ficon_right<=0;cicon_left<=0;cicon_right<=0;icon_top<=0;icon_bottom<=0;
            icon_pipe<=0;icon_pipe2<=0;icon_kind_pipe<=0;icon_kind_pipe2<=0;
            hdd_meta<=0;hdd_sync<=0;en_meta<=0;en_sync<=0;icons_meta<=0;icons_sync<=0;
            hdd_hold<=0;hdd_write_mode<=0;
            hbox_left<=0;hbox_right<=0;hicon_left<=0;hicon_right<=0;
            hdd_origin_x<=0;
            prev_de<=0;prev_vs<=0;sized<=0;drive<=0;
            position_pending<=0;crop_right_sum<=0;crop_bottom_sum<=0;crop_large<=0;
            right_edge<=0;bottom_edge<=0;box_left<=0;box_right<=0;box_top<=0;box_bottom<=0;
            text_origin_x<=7'd2;
            x<=0;y<=0;max_width<=0;width<=0;height<=0;hold_frames<=0;
            animation_ticks<=0;dot_phase<=0;
            ce_pipe<=0;hs_pipe<=0;vs_pipe<=0;de_pipe<=0;rgb_pipe<=0;
            box_pipe<=0;text_pipe<=0;
            text_column<=0;
            ce_pipe2<=0;hs_pipe2<=0;vs_pipe2<=0;de_pipe2<=0;rgb_pipe2<=0;
            box_pipe2<=0;text_pipe2<=0;
            out_ce<=0;out_hs<=0;out_vs<=0;out_de<=0;out_r<=0;out_g<=0;out_b<=0;
        end else begin
            activity_meta<=activity;activity_sync<=activity_meta;
            writing_meta<=writing;writing_sync<=writing_meta;
            cd_meta<=cd_activity;cd_sync<=cd_meta;
            hdd_meta<={hdd_writing,hdd_activity};hdd_sync<=hdd_meta;
            en_meta<={hdd_enabled,cd_enabled};en_sync<=en_meta;
            icons_meta<=icons_enabled;icons_sync<=icons_meta;
            enabled_meta<=enabled;enabled_sync<=enabled_meta;
            position_pending<={position_pending[0],frame_start};
            if(frame_start) begin
                crop_right_sum<={1'b0,crop_left}+{1'b0,crop_width};
                crop_bottom_sum<={1'b0,crop_top}+{1'b0,crop_height};
                crop_large<=crop_width>=116 && crop_height>=94;
            end
            if(position_pending[0]) begin
                right_edge<=crop_valid ? crop_right_sum[11:0] : width;
                bottom_edge<=crop_valid ? crop_bottom_sum[11:0] : height;
                left_edge<=crop_valid ? crop_left : 12'd0;
            end
            if(position_pending[1]) begin
                box_left<=right_edge-12'd112; box_right<=right_edge-12'd4;
                text_origin_x<=right_edge[6:0]-7'd110;
                // CD just left of the floppy, icon right-aligned with it; HDD
                // at the lower left, icon left-aligned. Same rows as the floppy.
                cd_left<=right_edge-12'd228; cd_right<=right_edge-12'd120;
                cd_origin_x<=right_edge[6:0]-7'd226;
                cicon_left<=right_edge-12'd154; cicon_right<=right_edge-12'd122;
                hbox_left<=left_edge+12'd4; hbox_right<=left_edge+12'd120;
                hdd_origin_x<=left_edge[6:0]+7'd6;
                hicon_left<=left_edge+12'd6; hicon_right<=left_edge+12'd38;
                ficon_left<=right_edge-12'd38; ficon_right<=right_edge-12'd6;   // right-aligned
                icon_top<=bottom_edge-12'd64; icon_bottom<=bottom_edge-12'd32;
                // Leave the bottom 16-pixel DOS function-key row plus four pixels clear.
                box_top<=bottom_edge-12'd30; box_bottom<=bottom_edge-12'd20;
            end
            if(cd_sync!=0) cd_hold<=HOLD_FRAMES;
            else if(frame_start && cd_hold!=0) cd_hold<=cd_hold-1'b1;
            if(hdd_sync[0]) hdd_hold<=HOLD_FRAMES;
            else if(frame_start && hdd_hold!=0) hdd_hold<=hdd_hold-1'b1;
            if(hdd_sync[1]) hdd_write_mode<=1;
            else if(hdd_hold==0) hdd_write_mode<=0;
            if(activity_sync!=0) hold_frames<=HOLD_FRAMES;
            else if(frame_start && hold_frames!=0) hold_frames<=hold_frames-1'b1;
            if(activity_sync==1) drive<=0;
            else if(activity_sync==2) drive<=1;
            // A new access starts as READING; any write-back in the hold
            // window switches the caption to WRITING until it expires.
            if(writing_sync!=0) write_mode<=1;
            else if(hold_frames==0) write_mode<=0;
            if(hold_frames==0 && cd_hold==0 && hdd_hold==0) begin
                animation_ticks<=0;dot_phase<=0;
            end else if(frame_start && animation_ticks >= ANIMATION_CYCLES) begin
                animation_ticks<=0;dot_phase<=dot_phase+1'b1;
            end else if(animation_ticks<ANIMATION_CYCLES) animation_ticks<=animation_ticks+1'b1;
            if(in_ce) begin
                prev_de<=in_de;prev_vs<=in_vs;
                if(frame_start) begin
                    width<=max_width;height<=y;sized<=max_width>=116 && y>=94;
                    x<=0;y<=0;max_width<=0;
                end else if(in_de) x<=x+1'b1;
                else begin
                    x<=0;
                    if(prev_de) begin y<=y+1'b1;if(x>max_width) max_width<=x;end
                end
            end
            ce_pipe<=in_ce;
            if(in_ce) begin
                hs_pipe<=in_hs;vs_pipe<=in_vs;de_pipe<=in_de;rgb_pipe<={in_r,in_g,in_b};
                box_pipe<=box || cd_box || hdd_box;text_pipe<=text_area;
                icon_pipe<=ficon || cicon || hicon; icon_kind_pipe<=icon_kind;
                text_column<=column;
            end
            ce_pipe2<=ce_pipe;
            if(ce_pipe) begin
                hs_pipe2<=hs_pipe;vs_pipe2<=vs_pipe;de_pipe2<=de_pipe;rgb_pipe2<=rgb_pipe;
                box_pipe2<=box_pipe;
                icon_pipe2<=icon_pipe ? icon_pixel : 2'd0; icon_kind_pipe2<=icon_kind_pipe;
                text_pipe2<=text_pipe && font_row[3'd7-text_column];
            end
            out_ce<=ce_pipe2;
            if(ce_pipe2) begin
                out_hs<=hs_pipe2;out_vs<=vs_pipe2;out_de<=de_pipe2;
                if(icon_pipe2!=0) {out_r,out_g,out_b}<=icon_color(icon_kind_pipe2,icon_pipe2);
                else if(!box_pipe2) {out_r,out_g,out_b}<=rgb_pipe2;
                else if(text_pipe2) {out_r,out_g,out_b}<=24'h0044ff;
                else {out_r,out_g,out_b}<=rgb_pipe2;
            end
        end
    end
endmodule
