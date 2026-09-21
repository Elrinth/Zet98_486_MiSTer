`timescale 1ns/1ps
module pc98_video_scale_tb;
    reg clk=0; always #5 clk=!clk;
    reg reset=1, ce=0, vs=0, de=0;
    reg [11:0] width=1920, height=1080, custom_x=16, custom_y=9;
    reg [2:0] mode=0;
    wire [12:0] arx, ary;
    wire [11:0] left, top, crop_w, crop_h;
    wire captured;
    pc98_video_scale dut(clk,reset,ce,vs,de,width,height,mode,custom_x,custom_y,
                        arx,ary,left,top,crop_w,crop_h);
    pc98_hdmi_crop crop(clk,reset,ce,vs,de,left,top,crop_w,crop_h,captured);
    integer source_w=640, source_h=400;
    integer sx=0, sy=0, capture_pixels=0, source_pixels=0;
    integer expect_left=0, expect_top=0, expect_w=640, expect_h=400;
    reg inspect=0;
    always @(posedge clk) if (inspect && ce && de) begin
        source_pixels=source_pixels+1;
        if (captured) capture_pixels=capture_pixels+1;
        if (captured !== (sx>=expect_left && sx<expect_left+expect_w &&
                          sy>=expect_top && sy<expect_top+expect_h))
            $fatal(1,"capture DE mismatch at source pixel %0d,%0d",sx,sy);
    end
    task frame(input bit check_mask);
        integer x,y;
        begin
            @(negedge clk); ce=1; vs=1; de=0;
            repeat(3) @(negedge clk);
            vs=0; inspect=check_mask; capture_pixels=0; source_pixels=0;
            for(y=0;y<source_h;y=y+1) begin
                for(x=0;x<source_w;x=x+1) begin
                    @(negedge clk); ce=1; de=1; sx=x; sy=y;
                    // CE stalls do not change the captured pixel coordinate.
                    if ((x%31)==7) begin
                        @(negedge clk); ce=0;
                        @(negedge clk); ce=0;
                    end
                end
                @(negedge clk); ce=1; de=0;
                repeat(3) @(negedge clk);
            end
            inspect=0;
            if(check_mask && (capture_pixels!=expect_w*expect_h || source_pixels!=source_w*source_h))
                $fatal(1,"crop/native pixel totals %0d/%0d",capture_pixels,source_pixels);
            vs=1; repeat(3) @(negedge clk); vs=0;
            repeat(10000) @(negedge clk);
        end
    endtask
    task check(input integer x,y,input bit explicit_size,input integer l,t,w,h);
        begin
            repeat(10000) @(negedge clk);
            if(arx!=={explicit_size,12'(x)} || ary!=={explicit_size,12'(y)} ||
               left!==12'(l) || top!==12'(t) || crop_w!==12'(w) || crop_h!==12'(h))
                $fatal(1,"mode%0d source%0dx%0d HDMI%0dx%0d got AR%h/%h crop%0d,%0d %0dx%0d",
                       mode,source_w,source_h,width,height,arx,ary,left,top,crop_w,crop_h);
            if(explicit_size && (x>width || y>height)) $fatal(1,"oversized viewport");
        end
    endtask
    initial begin
        repeat(5) @(negedge clk); reset=0;
        frame(1); check(640,400,0,0,0,0,0);
        mode=1; check(1280,800,1,0,0,0,0);
        mode=2; check(1920,1080,1,0,20,640,360);
        expect_top=20; expect_h=360; frame(1);
        mode=0; check(640,400,0,0,0,0,0);
        expect_top=0; expect_h=400; frame(1);
        mode=3; check(0,0,0,0,0,0,0);
        mode=4; check(4,3,0,0,0,0,0);
        mode=5; check(16,9,0,0,0,0,0);
        width=1280; height=720; mode=1; check(640,400,1,0,0,0,0);
        mode=2; check(1280,720,1,0,20,640,360);
        width=2560; height=1440; mode=1; check(1920,1200,1,0,0,0,0);
        mode=2; check(2560,1440,1,0,20,640,360);
        width=1920; height=1080; source_w=320; source_h=200;
        mode=0; frame(0); check(320,200,0,0,0,0,0);
        mode=1; check(1600,1000,1,0,0,0,0);
        mode=2; check(1920,1080,1,0,10,320,180);
        expect_left=0; expect_top=10; expect_w=320; expect_h=180; frame(1);
        source_h=240; mode=0; frame(0);
        mode=1; check(1280,960,1,0,0,0,0);
        mode=2; check(1600,1080,1,0,12,320,216);
        source_w=640; source_h=480; mode=0; frame(0);
        mode=1; check(1280,960,1,0,0,0,0);
        mode=2; check(1920,1080,1,0,60,640,360);
        expect_left=0; expect_top=60; expect_w=640; expect_h=360; frame(1);
        source_w=320; source_h=200; mode=0; frame(0);
        width=500; mode=2; check(500,400,1,35,0,250,200);
        expect_left=35; expect_top=0; expect_w=250; expect_h=200; frame(1);
        // Exact fit must not unnecessarily jump to the next integer.
        width=1920; height=1200; check(1920,1200,1,0,0,0,0);
        // A source larger than the output uses a safe fractional fallback.
        source_w=640; source_h=400; width=320; height=240; mode=0; frame(0);
        mode=1; check(640,400,0,0,0,0,0);
        mode=2; check(640,400,0,0,0,0,0);
        width=0; height=0; check(640,400,0,0,0,0,0);
        $display("PASS native fit/integer fit/integer crop/stretch/CRT/custom; 640x400, 320x200, 320x240, 640x480; HDMI-only crop pixel coordinates and CE stalls");
        $finish;
    end
    initial begin #100000000; $fatal(1,"watchdog"); end
endmodule
