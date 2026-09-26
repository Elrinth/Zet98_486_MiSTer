`timescale 1ns/1ps
module floppy_overlay_tb;
    reg clk=0,reset=1,enabled=1;
    reg [1:0] activity=0;
    reg [11:0] crop_left=0,crop_top=0,crop_width=0,crop_height=0;
    integer expected_right=0,expected_bottom=0;
    always #5 clk=!clk;
    reg in_ce=0,in_hs=0,in_vs=0,in_de=0;
    reg [7:0] in_r=8'h11,in_g=8'h22,in_b=8'h33;
    wire out_ce,out_hs,out_vs,out_de;
    wire [7:0] out_r,out_g,out_b;
    floppy_overlay #(.HOLD_FRAMES(3),.ANIMATION_CYCLES(0),
        .TILE_MAP_FILE("rtl/assets/floppy-tile-map.mem"),
        .TILE_PIXELS_FILE("rtl/assets/floppy-tile-pixels.mem"),
        .FONT_FILE("rtl/assets/boot-font.mem")) dut(.*);
    reg [1:0] reference_pixels[0:165199];
    initial $readmemb("rtl/assets/floppy-animation.mem",reference_pixels);
    reg [23:0] screen[0:12287];
    reg [26:0] held;
    integer changed,px,py,frames=0,frame_number=0;
    integer i,j,different;
    reg [63:0] digit0,digit1;
    reg [7:0] reference_font[0:1023];
    initial $readmemh("rtl/assets/boot-font.mem",reference_font);
    reg expected_drive=0;
    reg [23:0] expected_pixel;
    reg [1:0] source_pixel;
    integer bx,by,cx,cy,char_index,char_code;
    reg [103:0] caption;

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
            caption="LOADING D0...";
            if(expected_drive) caption[31:24]="1";
            bx=(expected_right ? expected_right : w)-112;
            by=(expected_bottom ? expected_bottom : h)-90;
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
                        if(bounds && !(px>=(expected_right ? expected_right : w)-112 &&
                            px<(expected_right ? expected_right : w)-4 &&
                            py>=(expected_bottom ? expected_bottom : h)-90 &&
                            py<(expected_bottom ? expected_bottom : h)-20))
                            $fatal(1,"overlay outside bottom-right rectangle");
                    end
                    if(animation>=0) begin
                        expected_pixel=24'h112233;
                        local_x=px-bx;local_y=py-by;
                        if(in_de && local_x>=29 && local_x<79 && local_y>=0 && local_y<56)
                            expected_pixel=color(reference_pixels[animation*2800+local_y*50+local_x-29]);
                        if(in_de && local_x>=2 && local_x<106 && local_y>=60 && local_y<68) begin
                            cx=local_x-2;cy=local_y-60;char_index=cx/8;
                            char_code=caption[103-char_index*8 -:8];
                            if(char_index>=10 && char_index-10>=dots) char_code=" ";
                            if(reference_font[char_code*8+cy][7-(cx%8)]) expected_pixel=24'h0044ff;
                        end
                        if({out_r,out_g,out_b}!==expected_pixel)
                            $fatal(1,"overlay pixel mismatch frame%0d x%0d y%0d expected%h got%h",animation,px,py,expected_pixel,{out_r,out_g,out_b});
                    end
                end
            end
            frames=frames+1;
        end
    endtask
    integer preview;
    initial begin
        repeat(3) @(negedge clk);reset=0;
        frame(128,96,-1,-1,1);if(changed) $fatal(1,"idle indicator visible");
        activity=1;
        // Every original animation frame must be reproduced, and wrap to 0.
        for(i=0;i<60;i=i+1) begin
            frame(128,96,i%59,(i/8)%4,1);
            if(changed<100 || changed>=108*70) $fatal(1,"overlay rectangle incomplete %0d",changed);
            if(i==0) begin
                for(j=0;j<64;j=j+1) digit0[j]=screen[(66+j/8)*128+90+j%8]==24'h0044ff;
                preview=$fopen("build/floppy-animation/overlay-sim.ppm","w");
                if(preview) begin
                    $fwrite(preview,"P3\n128 96\n255\n");
                    for(j=0;j<12288;j=j+1) $fwrite(preview,"%0d %0d %0d\n",screen[j][23:16],screen[j][15:8],screen[j][7:0]);
                    $fclose(preview);
                end
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
        activity=1;frame(160,120,-1,-1,0);frame(160,120,-1,-1,1);
        if(changed<100 || changed>=108*70) $fatal(1,"mode-change placement failed");
        crop_left=20;crop_top=10;crop_width=120;crop_height=100;
        // A new crop is adopted at VS; the current picture retains its bounds.
        frame(160,120,-1,-1,1);
        expected_right=140;expected_bottom=110;
        frame(160,120,-1,-1,1);
        if(changed<100 || changed>=108*70) $fatal(1,"cropped viewport clipped loading caption");
        // Ignore invalid crop dimensions, including stale mode-change data.
        crop_width=200;
        frame(160,120,-1,-1,1);
        expected_right=0;expected_bottom=0;
        frame(160,120,-1,-1,1);
        if(changed<100 || changed>=108*70) $fatal(1,"invalid crop did not use native bounds");
        $display("PASS floppy animation: all 59 frames/wrap, boot-font captions, transparent backgrounds, 16-pixel lift, dots, D0/D1, idle/disable/hold, bounds, CE/sync, two rasters (%0d frames)",frames);
        $finish;
    end
    initial begin #100000000; $fatal(1,"floppy overlay watchdog");end
endmodule
