`timescale 1ns/1ps
module floppy_overlay_tb;
    reg clk=0,reset=1,enabled=1;
    reg [1:0] activity=0;
    reg [1:0] writing=0;
    reg [1:0] cd_activity=0;
    reg cd_enabled=1,hdd_enabled=1,hdd_activity=0,hdd_writing=0,icons_enabled=1;
    reg [11:0] crop_left=0,crop_top=0,crop_width=0,crop_height=0;
    integer expected_right=0,expected_bottom=0;
    always #5 clk=!clk;
    reg in_ce=0,in_hs=0,in_vs=0,in_de=0;
    reg [7:0] in_r=8'h11,in_g=8'h22,in_b=8'h33;
    wire out_ce,out_hs,out_vs,out_de;
    wire [7:0] out_r,out_g,out_b;
    floppy_overlay #(.HOLD_FRAMES(3),.ANIMATION_CYCLES(0),
        .FONT_FILE("rtl/assets/boot-font.mem"),.ICON_FILE("rtl/assets/overlay-icons.mem")) dut(.*);
    reg [23:0] screen[0:12287];
    reg [26:0] held;
    integer changed,px,py,frames=0,frame_number=0;
    integer i,j,different;
    reg [63:0] digit0,digit1;
    reg [7:0] reference_font[0:1023];
    initial $readmemh("rtl/assets/boot-font.mem",reference_font);
    reg [1:0] reference_icons[0:6143];
    initial $readmemh("rtl/assets/overlay-icons.mem",reference_icons);
    integer ix0,iy0;
    reg expected_drive=0,expected_write=0;
    integer cd_mode=0;   // expected CD caption: 0 none, 1 data read, 2 CD audio (both READING CD)
    reg [23:0] expected_pixel;
    reg [1:0] source_pixel;
    integer bx,by,cx,cy,char_index,char_code;
    reg [111:0] caption;
    integer hdd_mode=0;   // expected HDD caption: 0 none, 1 READING HDD, 2 WRITING HDD
    integer dot_start,text_width,kind;

    function automatic [23:0] color(input [1:0] index);
        case(index)
            0:color=24'h112233;1:color=24'h0044ff;2:color=24'hffeeff;3:color=24'h777777;
        endcase
    endfunction
    task frame(input integer w,h, input integer animation, input integer dots, input bit bounds);
        integer local_x,local_y;
        begin
            changed=0;
            if(activity==1) expected_drive=0;
            if(activity==2) expected_drive=1;
            caption={expected_write ? "WRITING D0..." : "READING D0...", " "};
            if(expected_drive) caption[39:32]="1";
            dot_start=10;text_width=106;kind=0;
            bx=(expected_right ? expected_right : w)-112;
            by=(expected_bottom ? expected_bottom : h)-30;
            ix0=bx+74;   // floppy icon right-aligned with the caption
            iy0=by-34;
            if(cd_mode!=0) begin
                caption={"READING CD...", " "};   // data reads and CD audio alike
                bx=w-228;ix0=w-154;                          // left of the floppy
                kind=1;
            end
            if(hdd_mode!=0) begin
                caption=hdd_mode==2 ? "WRITING HDD..." : "READING HDD...";
                bx=4;ix0=6;                                             // lower left
                dot_start=11;text_width=114;kind=2;
            end
            for(py=0;py<h+8;py=py+1) begin
                for(px=0;px<w+8;px=px+1) begin
                    @(negedge clk);in_ce=1;in_de=px<w && py<h;
                    in_hs=px>=w+2 && px<w+5;in_vs=py==h+2;
                    held={out_r,out_g,out_b,out_hs,out_vs,out_de};
                    @(posedge clk);#1;
                    if(out_ce || {out_r,out_g,out_b,out_hs,out_vs,out_de}!==held)
                        $fatal(1,"ROM pipeline changed output without delayed CE");
                    @(negedge clk);in_ce=0;
                    @(posedge clk);#1;
                    if(out_ce) $fatal(1,"early tile output CE");
                    @(negedge clk);in_ce=0;
                    @(posedge clk);#1;
                    if(!out_ce || {out_hs,out_vs,out_de}!=={in_hs,in_vs,in_de})
                        $fatal(1,"overlay changed sync/blanking alignment");
                    if(w==128 && h==96 && in_de) screen[py*128+px]={out_r,out_g,out_b};
                    if({out_r,out_g,out_b}!==24'h112233) begin
                        changed=changed+1;
                        if(!in_de) $fatal(1,"overlay drew in blanking");
                        if(bounds && hdd_mode!=0 && !(px>=4 && px<120 && py>=h-64 && py<h-20))
                            $fatal(1,"overlay outside lower-left rectangle");
                        if(bounds && cd_mode==0 && hdd_mode==0 && !(px>=(expected_right ? expected_right : w)-112 &&
                            px<(expected_right ? expected_right : w)-4 &&
                            py>=(expected_bottom ? expected_bottom : h)-64 &&
                            py<(expected_bottom ? expected_bottom : h)-20))
                            $fatal(1,"overlay outside bottom-right rectangle frame%0d x%0d y%0d cd%0d hdd%0d w%0d",frames,px,py,cd_mode,hdd_mode,w);
                        if(bounds && cd_mode!=0 && !(px>=w-228 && px<w-120) &&
                            py>=h-64 && py<h-20)
                            $fatal(1,"overlay outside CD rectangle");
                    end
                    if(animation>=0) begin
                        expected_pixel=24'h112233;
                        local_x=px-bx;local_y=py-by;
                        if(in_de && local_x>=2 && local_x<text_width && local_y>=0 && local_y<8) begin
                            cx=local_x-2;cy=local_y;char_index=cx/8;
                            char_code=caption[111-char_index*8 -:8];
                            if(char_index>=dot_start && char_index-dot_start>=dots) char_code=" ";
                            if(reference_font[char_code*8+cy][7-(cx%8)]) expected_pixel=24'h0044ff;
                        end
                        // 2x icon above the caption; frame = dot phase bit 3
                        if(icons_enabled && in_de && px>=ix0 && px<ix0+32 && py>=iy0 && py<iy0+32)
                            case({2'(kind),reference_icons[{2'(kind),dut.dot_phase[4:2],4'((py-iy0)/2),4'((px-ix0)/2)}]})
                                4'b0001: expected_pixel=24'ha0a0a8;
                                4'b0010: expected_pixel=24'h1c50ff;
                                4'b0011: expected_pixel=24'hf4f4ff;
                                4'b0101: expected_pixel=24'hb894d8;
                                4'b0110: expected_pixel=24'h40e0a0;
                                4'b0111: expected_pixel=24'he8e4f4;
                                4'b1001: expected_pixel=24'h505058;
                                4'b1010: expected_pixel=24'hc0c0c8;
                                4'b1011: expected_pixel=24'h40ff40;
                                default: ;
                            endcase
                        if({out_r,out_g,out_b}!==expected_pixel)
                            $fatal(1,"overlay pixel mismatch frame%0d x%0d y%0d expected%h got%h",animation,px,py,expected_pixel,{out_r,out_g,out_b});
                    end
                end
            end
            frames=frames+1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);reset=0;
        frame(128,96,-1,-1,1);if(changed) $fatal(1,"idle indicator visible");
        activity=1;
        // Caption with every dot phase and its wrap over 56 frames (ends on phase 3).
        for(i=0;i<56;i=i+1) begin
            frame(128,96,i,(i/8)%4,1);
            if(changed<60 || changed>=108*10) $fatal(1,"overlay caption incomplete %0d",changed);
            if(i==0) begin
                for(j=0;j<64;j=j+1) digit0[j]=screen[(66+j/8)*128+90+j%8]==24'h0044ff;
            end
        end
        activity=2;frame(128,96,1,3,1);
        for(j=0;j<64;j=j+1) digit1[j]=screen[(66+j/8)*128+90+j%8]==24'h0044ff;
        if(digit0===digit1) $fatal(1,"drive label did not change from D0 to D1");
        activity=3;frame(128,96,2,3,1);
        for(j=0;j<64;j=j+1)
            if(digit1[j] !== (screen[(66+j/8)*128+90+j%8]==24'h0044ff))
                $fatal(1,"simultaneous requests changed retained drive");
        enabled=0;frame(128,96,-1,-1,1);if(changed) $fatal(1,"disabled overlay visible");
        enabled=1;activity=0;frame(128,96,-1,-1,1);
        if(changed==0) $fatal(1,"activity hold missing");
        repeat(4) frame(128,96,-1,-1,1);
        if(changed) $fatal(1,"indicator failed to expire");
        // Image write-back switches the caption to WRITING until the hold expires.
        activity=1;writing=1;expected_write=1;frame(128,96,0,0,1);
        writing=0;frame(128,96,1,0,1);
        activity=0;repeat(5) frame(128,96,-1,-1,1);
        if(changed) $fatal(1,"write indicator failed to expire");
        activity=1;expected_write=0;frame(128,96,0,0,1);
        activity=0;repeat(5) frame(128,96,-1,-1,1);
        // CD-ROM caption left of the floppy: audio, then a data read.
        frame(256,96,-1,-1,0);   // adopt the wider raster first
        cd_activity=2;cd_mode=2;frame(256,96,0,0,1);frame(256,96,1,0,1);
        if(changed<60) $fatal(1,"CD caption missing during CD audio");
        cd_activity=3;cd_mode=1;frame(256,96,0,0,1);
        cd_activity=0;repeat(5) frame(256,96,-1,-1,1);
        if(changed) $fatal(1,"CD caption failed to expire");
        cd_mode=0;
        // Each device has its own menu switch.
        cd_enabled=0;cd_activity=2;frame(256,96,-1,-1,1);
        if(changed) $fatal(1,"CD overlay visible while switched off");
        cd_activity=0;repeat(5) frame(256,96,-1,-1,1);cd_enabled=1;   // hold runs out first
        // HDD caption and icon at the lower left; writes switch to WRITING HDD.
        hdd_activity=1;hdd_mode=1;frame(256,96,0,0,1);frame(256,96,1,0,1);
        if(changed<60) $fatal(1,"HDD caption missing");
        hdd_writing=1;hdd_mode=2;frame(256,96,0,0,1);
        hdd_writing=0;hdd_activity=0;hdd_mode=2;frame(256,96,1,0,1);
        repeat(5) frame(256,96,-1,-1,1);
        if(changed) $fatal(1,"HDD caption failed to expire");
        hdd_enabled=0;hdd_activity=1;hdd_mode=0;frame(256,96,-1,-1,1);
        if(changed) $fatal(1,"HDD overlay visible while switched off");
        hdd_activity=0;repeat(5) frame(256,96,-1,-1,1);hdd_enabled=1;
        // Access icons off: the caption stays, the icon goes.
        icons_enabled=0;hdd_activity=1;hdd_mode=1;frame(256,96,0,0,1);frame(256,96,1,0,1);
        hdd_activity=0;repeat(5) frame(256,96,-1,-1,1);icons_enabled=1;hdd_mode=0;
        activity=1;frame(160,120,-1,-1,0);frame(160,120,-1,-1,1);
        if(changed<60 || changed>=108*10) $fatal(1,"mode-change placement failed");
        crop_left=20;crop_top=10;crop_width=120;crop_height=100;
        // A new crop is adopted at VS; the current picture retains its bounds.
        frame(160,120,-1,-1,1);
        expected_right=140;expected_bottom=110;
        frame(160,120,-1,-1,1);
        if(changed<60 || changed>=108*10) $fatal(1,"cropped viewport clipped loading caption");
        // Ignore invalid crop dimensions, including stale mode-change data.
        crop_width=200;
        frame(160,120,-1,-1,1);
        expected_right=0;expected_bottom=0;
        frame(160,120,-1,-1,1);
        if(changed<60 || changed>=108*10) $fatal(1,"invalid crop did not use native bounds");
        $display("PASS floppy caption: READING/WRITING D0/D1, READING CD and READING/WRITING HDD boot-font text, per-device switches, icons off, 2x eight-frame turning floppy / spinning CD icons, dot phases/wrap, transparent backgrounds, 16-pixel lift, dots, D0/D1, idle/disable/hold, bounds, CE/sync, two rasters (%0d frames)",frames);
        $finish;
    end
    initial begin #100000000; $fatal(1,"floppy overlay watchdog");end
endmodule
