// SPDX-License-Identifier: GPL-3.0-or-later
// User-supplied rotating disk, drive label and cycling dots. A two-clock
// pipeline keeps ROM pixels, RGB, blanking, sync and CE aligned.
module floppy_overlay #(
    parameter HOLD_FRAMES=15,
    parameter ANIMATION_CYCLES=3000000, // 40 ms at the 75 MHz video clock.
    parameter ROM_FILE="../../rtl/assets/floppy-animation.hex"
) (
    input wire clk, reset, enabled,
    input wire [1:0] activity,
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
    reg [17:0] frame_base;
    reg [22:0] animation_ticks;
    reg [4:0] dot_phase;
    wire frame_start=in_ce && in_vs && !prev_vs;
    wire box=enabled_sync && sized && hold_frames!=0 && in_de &&
        x>=width-92 && x<width-4 && y>=height-74 && y<height-4;
    wire [6:0] dx=x-(width-92), dy=y-(height-74);
    wire disk_pixel=box && dx>=19 && dx<69 && dy<56;
    wire [17:0] rom_address=disk_pixel ? frame_base + dy*18'd50 + (dx-18'd19) : 18'd0;
    (* ramstyle="M10K" *) reg [1:0] pixels[0:165199];
    reg [1:0] rom_pixel;
    initial $readmemh(ROM_FILE,pixels);
    always @(posedge clk) rom_pixel<=pixels[rom_address];

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
    wire [6:0] tx=dx-7'd5;
    wire [3:0] character=tx/6;
    wire [2:0] column=tx%6;
    wire [34:0] font=glyph(character,drive,dot_phase[4:3]);
    wire text_pixel=box && dx>=5 && dx<83 && dy>=60 && dy<67 && column<5 &&
                    font[34-((dy-60)*5+column)];
    reg ce_pipe,hs_pipe,vs_pipe,de_pipe,box_pipe,disk_pipe,text_pipe;
    reg [23:0] rgb_pipe;
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
            x<=0;y<=0;max_width<=0;width<=0;height<=0;hold_frames<=0;
            animation_frame<=0;frame_base<=0;animation_ticks<=0;dot_phase<=0;
            ce_pipe<=0;hs_pipe<=0;vs_pipe<=0;de_pipe<=0;rgb_pipe<=0;
            box_pipe<=0;disk_pipe<=0;text_pipe<=0;
            out_ce<=0;out_hs<=0;out_vs<=0;out_de<=0;out_r<=0;out_g<=0;out_b<=0;
        end else begin
            activity_meta<=activity;activity_sync<=activity_meta;
            enabled_meta<=enabled;enabled_sync<=enabled_meta;
            if(activity_sync!=0) hold_frames<=HOLD_FRAMES;
            else if(frame_start && hold_frames!=0) hold_frames<=hold_frames-1'b1;
            if(activity_sync==1) drive<=0;
            else if(activity_sync==2) drive<=1;
            if(hold_frames==0) begin
                animation_frame<=0;frame_base<=0;animation_ticks<=0;dot_phase<=0;
            end else if(frame_start && animation_ticks >= (animation_frame==0 ? ANIMATION_CYCLES*2 : ANIMATION_CYCLES)) begin
                animation_ticks<=0;dot_phase<=dot_phase+1'b1;
                if(animation_frame==58) begin animation_frame<=0;frame_base<=0;end
                else begin animation_frame<=animation_frame+1'b1;frame_base<=frame_base+18'd2800;end
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
                box_pipe<=box;disk_pipe<=disk_pixel;text_pipe<=text_pixel;
            end
            out_ce<=ce_pipe;
            if(ce_pipe) begin
                out_hs<=hs_pipe;out_vs<=vs_pipe;out_de<=de_pipe;
                if(!box_pipe) {out_r,out_g,out_b}<=rgb_pipe;
                else if(text_pipe) {out_r,out_g,out_b}<=24'h0044ff;
                else if(disk_pipe) {out_r,out_g,out_b}<=palette(rom_pixel);
                else {out_r,out_g,out_b}<=0;
            end
        end
    end
endmodule
