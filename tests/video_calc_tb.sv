`timescale 1ps/1ps
module video_calc_tb;
    parameter integer SYS_HALF_PS=8333;
    reg clk100=0, vidclk=0, sysclk=0;
    always #5000 clk100=~clk100;
    always #6667 vidclk=~vidclk;
    always #(SYS_HALF_PS) sysclk=~sysclk;
    integer div=0, x=0, y=0, active_width=64, total_width=80;
    reg mode=0;
    wire ce=(div==0);
    wire de=(x<active_width && y>=2 && y<10);
    wire hs=(x>=total_width-8);
    wire vs=(y>=12);
    always @(posedge vidclk) begin
        div <= (div==2) ? 0 : div+1;
        if(ce) begin
            if(x==total_width-1) begin x<=0; y<=(y==13) ? 0 : y+1; end
            else x<=x+1;
        end
    end
    reg [3:0] par=0;
    wire [15:0] dout;
    video_calc dut(clk100,vidclk,sysclk,ce,de,hs,vs,vs,1'b0,mode,par,dout);
    task read_check(input integer p, input integer expected, input integer tolerance);
        begin
            @(negedge sysclk); par=p;
            @(posedge sysclk); #1;
            if($isunknown(dout) || dout<expected-tolerance || dout>expected+tolerance)
                $fatal(1,"video parameter %0d got %0d expected %0d +/- %0d",p,dout,expected,tolerance);
        end
    endtask
    task check_mode;
        begin
            read_check(2,active_width,0); read_check(3,0,0);
            read_check(4,8,0); read_check(5,0,0);
            read_check(6,total_width*4,1); read_check(7,0,0);
            read_check(8,total_width*14*4,1); read_check(9,0,0);
            read_check(10,active_width*4,1); read_check(11,0,0);
            read_check(12,total_width*14*4,1); read_check(13,0,0);
            read_check(0,0,0); read_check(14,0,0); read_check(15,0,0);
            @(negedge sysclk);par=1;@(posedge sysclk);#1;
            if(dout==0 || dout[15:8]!=0) $fatal(1,"resolution-change counter not reported: %h",dout);
        end
    endtask
    initial begin
        repeat(40) @(negedge vs);
        #1000000;check_mode();
        @(negedge vs);@(negedge vidclk);active_width=80;total_width=96;mode=1;
        repeat(40) @(negedge vs);
        #1000000;check_mode();
        $display("PASS: actual video_calc reports two widths, height, line/frame/pixel times and mode changes, sys half=%0d ps",SYS_HALF_PS);
        $finish;
    end
    initial begin #10000000000;$fatal(1,"video_calc watchdog");end
endmodule
