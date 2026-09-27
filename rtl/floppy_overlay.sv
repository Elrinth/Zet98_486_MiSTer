// SPDX-License-Identifier: GPL-3.0-or-later
// "READING D0..." / "WRITING D1..." caption with cycling dots at the lower
// right while a floppy is accessed (WRITING while the drive's image is
// being written back). (The animated disk icon was removed to
// free FPGA area.) A three-clock pipeline keeps font pixels, RGB, blanking,
// sync and CE aligned.
module floppy_overlay #(
    parameter HOLD_FRAMES=15,
    parameter ANIMATION_CYCLES=3000000, // 40 ms at the 75 MHz video clock.
    parameter FONT_FILE="../../rtl/assets/boot-font.mem"
) (
    input wire clk, reset, enabled,
    input wire [1:0] activity,
    input wire [1:0] writing,      // image write-back per drive (subset of activity)
    input wire [11:0] crop_left, crop_top, crop_width, crop_height,
    input wire in_ce, in_hs, in_vs, in_de,
    input wire [7:0] in_r, in_g, in_b,
    output reg out_ce, out_hs, out_vs, out_de,
    output reg [7:0] out_r, out_g, out_b
);
    (* preserve, altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] activity_meta, activity_sync, writing_meta, writing_sync;
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
    wire [6:0] dx=x-box_left, dy=y-box_top;
    // Reuse the core boot-help font, with one byte per 8x8 character row.
    // The caption background stays transparent.
    function automatic [6:0] caption_ascii(input [3:0] position,
        input selected_drive,input write,input [1:0] dots);
        case(position)
            0: caption_ascii=write ? "W" : "R";
            1: caption_ascii=write ? "R" : "E";
            2: caption_ascii=write ? "I" : "A";
            3: caption_ascii=write ? "T" : "D";
            4: caption_ascii="I";
            5: caption_ascii="N";
            6: caption_ascii="G";
            8: caption_ascii="D";
            9: caption_ascii=selected_drive ? "1" : "0";
            10,11,12: caption_ascii=position-10<dots ? "." : " ";
            default: caption_ascii=" ";
        endcase
    endfunction
    wire [6:0] tx=x[6:0]-text_origin_x;
    wire [3:0] character=tx[6:3];
    wire [2:0] column=tx[2:0];
    wire [2:0] font_row_address=dy[2:0];
    wire [6:0] font_character=caption_ascii(character,drive,write_mode,dot_phase[4:3]);
    wire text_area=box && dx>=2 && dx<106 && dy<8;
    (* ramstyle="M10K" *) reg [7:0] boot_font[0:1023];
    reg [7:0] font_row;
    reg [2:0] text_column;
    initial $readmemh(FONT_FILE,boot_font);
    always @(posedge clk) font_row<=boot_font[{font_character,font_row_address}];
    reg ce_pipe,hs_pipe,vs_pipe,de_pipe,box_pipe,text_pipe;
    reg [23:0] rgb_pipe;
    reg ce_pipe2,hs_pipe2,vs_pipe2,de_pipe2,box_pipe2,text_pipe2;
    reg [23:0] rgb_pipe2;
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            activity_meta<=0;activity_sync<=0;enabled_meta<=0;enabled_sync<=0;
            writing_meta<=0;writing_sync<=0;write_mode<=0;
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
            end
            if(position_pending[1]) begin
                box_left<=right_edge-12'd112; box_right<=right_edge-12'd4;
                text_origin_x<=right_edge[6:0]-7'd110;
                // Leave the bottom 16-pixel DOS function-key row plus four pixels clear.
                box_top<=bottom_edge-12'd30; box_bottom<=bottom_edge-12'd20;
            end
            if(activity_sync!=0) hold_frames<=HOLD_FRAMES;
            else if(frame_start && hold_frames!=0) hold_frames<=hold_frames-1'b1;
            if(activity_sync==1) drive<=0;
            else if(activity_sync==2) drive<=1;
            // A new access starts as READING; any write-back in the hold
            // window switches the caption to WRITING until it expires.
            if(writing_sync!=0) write_mode<=1;
            else if(hold_frames==0) write_mode<=0;
            if(hold_frames==0) begin
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
                box_pipe<=box;text_pipe<=text_area;
                text_column<=column;
            end
            ce_pipe2<=ce_pipe;
            if(ce_pipe) begin
                hs_pipe2<=hs_pipe;vs_pipe2<=vs_pipe;de_pipe2<=de_pipe;rgb_pipe2<=rgb_pipe;
                box_pipe2<=box_pipe;
                text_pipe2<=text_pipe && font_row[3'd7-text_column];
            end
            out_ce<=ce_pipe2;
            if(ce_pipe2) begin
                out_hs<=hs_pipe2;out_vs<=vs_pipe2;out_de<=de_pipe2;
                if(!box_pipe2) {out_r,out_g,out_b}<=rgb_pipe2;
                else if(text_pipe2) {out_r,out_g,out_b}<=24'h0044ff;
                else {out_r,out_g,out_b}<=rgb_pipe2;
            end
        end
    end
endmodule
