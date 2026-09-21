`timescale 1ns/1ps
module video_scale_int_tb;
    reg clk=0; always #5 clk=!clk;
    reg [11:0] width=1920,height=1080,source_width=640,source_height=400,arx=4,ary=3;
    reg [2:0] mode=1;
    wire [12:0] out_x,out_y;
    video_scale_int dut(clk,width,height,mode,source_width,source_height,arx,ary,out_x,out_y);
    task check(input integer x,y,input bit explicit_size);
        begin
            repeat(2000) @(negedge clk);
            if(out_x!=={explicit_size,12'(x)} || out_y!=={explicit_size,12'(y)})
                $fatal(1,"scaling %0dx%0d source%0dx%0d mode%0d: got %h/%h expected %0d/%0d",
                    width,height,source_width,source_height,mode,out_x,out_y,x,y);
            if(explicit_size && (x>width || y>height)) $fatal(1,"viewport exceeds HDMI output");
        end
    endtask
    initial begin
        check(1066,800,1); // 640x400, 4:3 pixels, exact 2x vertical.
        mode=4;check(1280,800,1); // Nearest whole horizontal multiplier.
        width=1280;height=720;check(640,400,1); // Target width below one source row.
        mode=1;check(533,400,1);
        width=1920;height=1080;source_height=480;check(1280,960,1);
        mode=4;check(1280,960,1);
        width=2560;height=1440;source_height=400;check(1280,1200,1); // Equal-distance tie prefers narrower.
        mode=1;check(1600,1200,1);
        width=1920;height=1080;arx=16;ary=9;check(1422,800,1);
        mode=0;check(16,9,0);
        arx=4;ary=3;mode=1;height=240;check(4,3,0); // No clipping if integer upscaling cannot fit.
        mode=0;arx=0;ary=0;check(0,0,0);
        $display("PASS HDMI integer viewports: 1080p/720p/1440p, 400/480 lines, aspect modes, small-output fallback");
        $finish;
    end
    initial begin #1000000;$fatal(1,"scaler watchdog");end
endmodule
