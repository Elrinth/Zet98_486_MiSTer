// SPDX-License-Identifier: GPL-3.0-or-later
// User-supplied rotating disk, drive label and cycling dots. A three-clock
// pipeline keeps ROM pixels, RGB, blanking, sync and CE aligned.
module floppy_overlay #(
    parameter HOLD_FRAMES=15,
    parameter ANIMATION_CYCLES=3000000, // 40 ms at the 75 MHz video clock.
    parameter TILE_MAP_FILE="../../rtl/assets/floppy-tile-map.mem",
    parameter TILE_PIXELS_FILE="../../rtl/assets/floppy-tile-pixels.mem"
) (
    input wire clk, reset, enabled,
    input wire [1:0] activity,
    input wire [11:0] crop_left, crop_top, crop_width, crop_height,
    input wire in_ce, in_hs, in_vs, in_de,
    input wire [7:0] in_r, in_g, in_b,
    output reg out_ce, out_hs, out_vs, out_de,
    output reg [7:0] out_r, out_g, out_b
);
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] activity_meta, activity_sync;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg enabled_meta, enabled_sync;
    reg prev_de,prev_vs,sized,drive;
    reg [11:0] x,y,max_width,width,height;
    reg [$clog2(HOLD_FRAMES+1)-1:0] hold_frames;
    reg [5:0] animation_frame;
    reg [13:0] frame_base;
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
    // The ROM only needs a bounded local address. Global box/enable tests
    // mask the output separately and must not lengthen the RAM address path.
    wire rom_in_range=dx>=19 && dx<69 && dy<56;
    wire disk_pixel=box && rom_in_range;
    wire [6:0] disk_x=dx-7'd19;
    wire [13:0] tile_address=rom_in_range ? frame_base + dy[6:2]*14'd13 + disk_x[6:2] : 14'd0;
    (* ramstyle="M10K" *) reg [8:0] tile_map[0:10737];
    (* ramstyle="M10K" *) reg [1:0] tile_pixels[0:7919];
    reg [8:0] tile;
    reg [3:0] tile_offset;
    reg [1:0] rom_pixel;
    initial $readmemb(TILE_MAP_FILE,tile_map);
    initial $readmemb(TILE_PIXELS_FILE,tile_pixels);
    always @(posedge clk) begin
        tile<=tile_map[tile_address];
        tile_offset<={dy[1:0],disk_x[1:0]};
        rom_pixel<=tile_pixels[{tile,tile_offset}];
    end

    // Five-column, seven-row caption font. Space and unused columns are blank.
    function automatic [34:0] glyph(input [3:0] position,input selected_drive,input [1:0] dots);
        begin
            case(position)
                0: glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111}; // L
                1: glyph={5'b00000,5'b00000,5'b01110,5'b10001,5'b10001,5'b10001,5'b01110}; // o
                2: glyph={5'b00000,5'b00000,5'b01110,5'b00001,5'b01111,5'b10001,5'b01111}; // a
                3: glyph={5'b00001,5'b00001,5'b01111,5'b10001,5'b10001,5'b10001,5'b01111}; // d
                4: glyph={5'b00100,5'b00000,5'b01100,5'b00100,5'b00100,5'b00100,5'b01110}; // i
                5: glyph={5'b00000,5'b00000,5'b11110,5'b10001,5'b10001,5'b10001,5'b10001}; // n
                6: glyph={5'b00000,5'b01111,5'b10001,5'b10001,5'b01111,5'b00001,5'b01110}; // g
                8: glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110}; // D
                9: glyph=selected_drive ?
                    {5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110} :
                    {5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                10,11,12: glyph=position-10<dots ? 35'b00100 : 35'b0;
                default: glyph=0;
            endcase
        end
    endfunction
    // Bounded six-pixel caption cells: divide the upper six offset bits by
    // three through a small combinational table. The low bit forms column
    // parity. This avoids a serial divider after the per-pixel subtraction.
    function automatic [5:0] caption_div3(input [5:0] half_offset);
        case(half_offset)
            6'd0: caption_div3=6'h00;
            6'd1: caption_div3=6'h01;
            6'd2: caption_div3=6'h02;
            6'd3: caption_div3=6'h04;
            6'd4: caption_div3=6'h05;
            6'd5: caption_div3=6'h06;
            6'd6: caption_div3=6'h08;
            6'd7: caption_div3=6'h09;
            6'd8: caption_div3=6'h0a;
            6'd9: caption_div3=6'h0c;
            6'd10: caption_div3=6'h0d;
            6'd11: caption_div3=6'h0e;
            6'd12: caption_div3=6'h10;
            6'd13: caption_div3=6'h11;
            6'd14: caption_div3=6'h12;
            6'd15: caption_div3=6'h14;
            6'd16: caption_div3=6'h15;
            6'd17: caption_div3=6'h16;
            6'd18: caption_div3=6'h18;
            6'd19: caption_div3=6'h19;
            6'd20: caption_div3=6'h1a;
            6'd21: caption_div3=6'h1c;
            6'd22: caption_div3=6'h1d;
            6'd23: caption_div3=6'h1e;
            6'd24: caption_div3=6'h20;
            6'd25: caption_div3=6'h21;
            6'd26: caption_div3=6'h22;
            6'd27: caption_div3=6'h24;
            6'd28: caption_div3=6'h25;
            6'd29: caption_div3=6'h26;
            6'd30: caption_div3=6'h28;
            6'd31: caption_div3=6'h29;
            6'd32: caption_div3=6'h2a;
            6'd33: caption_div3=6'h2c;
            6'd34: caption_div3=6'h2d;
            6'd35: caption_div3=6'h2e;
            6'd36: caption_div3=6'h30;
            6'd37: caption_div3=6'h31;
            6'd38: caption_div3=6'h32;
            6'd39: caption_div3=6'h34;
            6'd40: caption_div3=6'h35;
            6'd41: caption_div3=6'h36;
            6'd42: caption_div3=6'h38;
            6'd43: caption_div3=6'h39;
            6'd44: caption_div3=6'h3a;
            6'd45: caption_div3=6'h3c;
            6'd46: caption_div3=6'h3d;
            6'd47: caption_div3=6'h3e;
            6'd48: caption_div3=6'h00;
            6'd49: caption_div3=6'h01;
            6'd50: caption_div3=6'h02;
            6'd51: caption_div3=6'h04;
            6'd52: caption_div3=6'h05;
            6'd53: caption_div3=6'h06;
            6'd54: caption_div3=6'h08;
            6'd55: caption_div3=6'h09;
            6'd56: caption_div3=6'h0a;
            6'd57: caption_div3=6'h0c;
            6'd58: caption_div3=6'h0d;
            6'd59: caption_div3=6'h0e;
            6'd60: caption_div3=6'h10;
            6'd61: caption_div3=6'h11;
            6'd62: caption_div3=6'h12;
            6'd63: caption_div3=6'h14;
        endcase
    endfunction
    // Equivalent modulo 128 to (x-box_left)-5; precompute the origin in
    // vertical blank instead of putting two subtractions in the pixel path.
    wire [6:0] tx=x[6:0]-text_origin_x;
    wire [5:0] cell_parts=caption_div3(tx[6:1]);
    wire [3:0] character=cell_parts[5:2];
    wire [2:0] column={cell_parts[1:0],tx[0]};
    wire text_area=box && dx>=5 && dx<83 && dy>=60 && dy<67;
    // The caption has the same three clocks of latency as the tiled image.
    // Split coordinate division from glyph selection across its two internal
    // stages, instead of doing the whole font lookup before the first one.
    reg [3:0] text_character;
    reg [2:0] text_column,text_row;
    reg text_drive;
    reg [1:0] text_dots;
    wire [34:0] font=glyph(text_character,text_drive,text_dots);
    wire [5:0] font_index=6'd34-({3'd0,text_row}*6'd5+{3'd0,text_column});
    reg ce_pipe,hs_pipe,vs_pipe,de_pipe,box_pipe,disk_pipe,text_pipe;
    reg [23:0] rgb_pipe;
    reg ce_pipe2,hs_pipe2,vs_pipe2,de_pipe2,box_pipe2,disk_pipe2,text_pipe2;
    reg [23:0] rgb_pipe2;
    function automatic [23:0] palette(input [1:0] index);
        case(index)
            1: palette=24'h0044ff;
            2: palette=24'hffeeff;
            3: palette=24'h777777;
            default: palette=0;
        endcase
    endfunction
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            activity_meta<=0;activity_sync<=0;enabled_meta<=0;enabled_sync<=0;
            prev_de<=0;prev_vs<=0;sized<=0;drive<=0;
            position_pending<=0;crop_right_sum<=0;crop_bottom_sum<=0;crop_large<=0;
            right_edge<=0;bottom_edge<=0;box_left<=0;box_right<=0;box_top<=0;box_bottom<=0;
            text_origin_x<=7'd5;
            x<=0;y<=0;max_width<=0;width<=0;height<=0;hold_frames<=0;
            animation_frame<=0;frame_base<=0;animation_ticks<=0;dot_phase<=0;
            ce_pipe<=0;hs_pipe<=0;vs_pipe<=0;de_pipe<=0;rgb_pipe<=0;
            box_pipe<=0;disk_pipe<=0;text_pipe<=0;
            text_character<=0;text_column<=0;text_row<=0;text_drive<=0;text_dots<=0;
            ce_pipe2<=0;hs_pipe2<=0;vs_pipe2<=0;de_pipe2<=0;rgb_pipe2<=0;
            box_pipe2<=0;disk_pipe2<=0;text_pipe2<=0;
            out_ce<=0;out_hs<=0;out_vs<=0;out_de<=0;out_r<=0;out_g<=0;out_b<=0;
        end else begin
            activity_meta<=activity;activity_sync<=activity_meta;
            enabled_meta<=enabled;enabled_sync<=enabled_meta;
            position_pending<={position_pending[0],frame_start};
            if(frame_start) begin
                crop_right_sum<={1'b0,crop_left}+{1'b0,crop_width};
                crop_bottom_sum<={1'b0,crop_top}+{1'b0,crop_height};
                crop_large<=crop_width>=96 && crop_height>=78;
            end
            if(position_pending[0]) begin
                right_edge<=crop_valid ? crop_right_sum[11:0] : width;
                bottom_edge<=crop_valid ? crop_bottom_sum[11:0] : height;
            end
            if(position_pending[1]) begin
                box_left<=right_edge-12'd92; box_right<=right_edge-12'd4;
                text_origin_x<=right_edge[6:0]-7'd87;
                box_top<=bottom_edge-12'd74; box_bottom<=bottom_edge-12'd4;
            end
            if(activity_sync!=0) hold_frames<=HOLD_FRAMES;
            else if(frame_start && hold_frames!=0) hold_frames<=hold_frames-1'b1;
            if(activity_sync==1) drive<=0;
            else if(activity_sync==2) drive<=1;
            if(hold_frames==0) begin
                animation_frame<=0;frame_base<=0;animation_ticks<=0;dot_phase<=0;
            end else if(frame_start && animation_ticks >= (animation_frame==0 ? ANIMATION_CYCLES*2 : ANIMATION_CYCLES)) begin
                animation_ticks<=0;dot_phase<=dot_phase+1'b1;
                if(animation_frame==58) begin animation_frame<=0;frame_base<=0;end
                else begin animation_frame<=animation_frame+1'b1;frame_base<=frame_base+14'd182;end
            end else if(animation_ticks<ANIMATION_CYCLES*2) animation_ticks<=animation_ticks+1'b1;
            if(in_ce) begin
                prev_de<=in_de;prev_vs<=in_vs;
                if(frame_start) begin
                    width<=max_width;height<=y;sized<=max_width>=96 && y>=78;
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
                box_pipe<=box;disk_pipe<=disk_pixel;text_pipe<=text_area;
                text_character<=character;text_column<=column;text_row<=dy-7'd60;
                text_drive<=drive;text_dots<=dot_phase[4:3];
            end
            ce_pipe2<=ce_pipe;
            if(ce_pipe) begin
                hs_pipe2<=hs_pipe;vs_pipe2<=vs_pipe;de_pipe2<=de_pipe;rgb_pipe2<=rgb_pipe;
                box_pipe2<=box_pipe;disk_pipe2<=disk_pipe;
                text_pipe2<=text_pipe && text_column<5 && font[font_index];
            end
            out_ce<=ce_pipe2;
            if(ce_pipe2) begin
                out_hs<=hs_pipe2;out_vs<=vs_pipe2;out_de<=de_pipe2;
                if(!box_pipe2) {out_r,out_g,out_b}<=rgb_pipe2;
                else if(text_pipe2) {out_r,out_g,out_b}<=24'h0044ff;
                else if(disk_pipe2) {out_r,out_g,out_b}<=palette(rom_pixel);
                else {out_r,out_g,out_b}<=0;
            end
        end
    end
endmodule
