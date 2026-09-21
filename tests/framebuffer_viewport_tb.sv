`timescale 1ps/1ps
module framebuffer_viewport_tb;
    parameter integer SYS_HALF_PS=8333;
    reg clk_vid=0,clk_sys=0;
    always #6667 clk_vid=~clk_vid;
    always #(SYS_HALF_PS) clk_sys=~clk_sys;
    reg LFB_EN=0;
    reg [11:0] LFB_HMIN=0,LFB_HMAX=0,LFB_VMIN=0,LFB_VMAX=0;
    reg [11:0] WIDTH=1920,HEIGHT=1080,HSET=0,VSET=0;
    reg FREESCALE=0;
    reg [12:0] ARX=0,ARY=0,arc1x=0,arc1y=0,arc2x=0,arc2y=0;
    viewport dut(.*);
    reg [48:0] previous_inputs=0,expected;
    integer cases=0,stages=0;
    always @(posedge clk_vid) begin
        expected=previous_inputs;
        previous_inputs={LFB_EN,LFB_HMIN,LFB_HMAX,LFB_VMIN,LFB_VMAX};
        #1;
        if(dut.lfb_viewport_video !== expected)
            $fatal(1,"framebuffer settings pipeline mismatch");
        stages=stages+1;
    end
    task rectangle(input integer x0,x1,y0,y1);
        begin
            repeat(400) @(negedge clk_vid);
            if({dut.hmin,dut.hmax,dut.vmin,dut.vmax} !==
                {12'(x0),12'(x1),12'(y0),12'(y1)})
                $fatal(1,"viewport got %0d,%0d,%0d,%0d expected %0d,%0d,%0d,%0d",
                    dut.hmin,dut.hmax,dut.vmin,dut.vmax,x0,x1,y0,y1);
            cases=cases+1;
        end
    endtask
    integer i;
    initial begin
        rectangle(0,1919,0,1079);
        @(negedge clk_sys);ARX=4;ARY=3;
        rectangle(240,1679,0,1079);
        @(negedge clk_sys);ARX=4096+1728;ARY=4096+1080;
        rectangle(96,1823,0,1079);
        @(negedge clk_sys);ARX=4096+1280;ARY=4096+800;
        rectangle(320,1599,140,939);
        @(negedge clk_sys);ARX=1;ARY=0;arc1x=4096+1280;arc1y=4096+800;
        rectangle(320,1599,140,939);
        for(i=0;i<64;i=i+1) begin
            @(negedge clk_sys);
            LFB_EN=1;
            LFB_HMIN=17+i;LFB_HMAX=1500-i;
            LFB_VMIN=31+i;LFB_VMAX=1000-i;
            rectangle(17+i,1500-i,31+i,1000-i);
        end
        @(negedge clk_sys);LFB_EN=0;
        rectangle(320,1599,140,939);
        @(negedge clk_sys);FREESCALE=1;HSET=1600;VSET=900;
        rectangle(160,1759,90,989);
        @(negedge clk_sys);HSET=0;VSET=0;WIDTH=1280;HEIGHT=720;
        rectangle(0,1279,0,719);
        @(negedge clk_sys);FREESCALE=0;ARX=16;ARY=10;
        rectangle(64,1215,0,719);
        $display("PASS actual HDMI viewport: %0d rectangles, %0d stage checks, sys half=%0d ps",cases,stages,SYS_HALF_PS);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"viewport watchdog");end
endmodule
