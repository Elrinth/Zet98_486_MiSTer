`timescale 1ns/1ps
module floppy_overlay_stream_tb;
    reg clk=0,reset=1,enabled=1;
    always #5 clk=!clk;
    reg [1:0] activity=0;
    reg [1:0] writing=0;
    reg [1:0] cd_activity=0;
    reg cd_enabled=1,hdd_enabled=1,hdd_activity=0,hdd_writing=0,icons_enabled=1;
    reg [11:0] crop_left=0,crop_top=0,crop_width=0,crop_height=0;
    reg in_ce=0,in_hs=0,in_vs=0,in_de=0;
    reg [7:0] in_r=0,in_g=0,in_b=0;
    wire out_ce,out_hs,out_vs,out_de;
    wire [7:0] out_r,out_g,out_b;
    floppy_overlay #(.ANIMATION_CYCLES(0),
        .FONT_FILE("rtl/assets/boot-font.mem"),.ICON_FILE("rtl/assets/overlay-icons.mem")) dut(.*);
    reg [23:0] expected_rgb=0,rgb_q[0:2];
    reg check_rgb=1;
    reg [2:0] ce_q=0,check_q=0,sync_q[0:2];
    integer n,checks=0;
    reg [26:0] held;
    function automatic [23:0] color(input [1:0] index);
        case(index)
            0:color=0;1:color=24'h0044ff;2:color=24'hffeeff;3:color=24'h777777;
        endcase
    endfunction
    always @(posedge clk) begin
        if(reset) begin ce_q=0;check_q=0;end
        else begin
            held={out_r,out_g,out_b,out_hs,out_vs,out_de};
            for(n=2;n>0;n=n-1) begin
                rgb_q[n]=rgb_q[n-1];sync_q[n]=sync_q[n-1];
            end
            rgb_q[0]=expected_rgb;sync_q[0]={in_hs,in_vs,in_de};
            ce_q={ce_q[1:0],in_ce};check_q={check_q[1:0],check_rgb};
            #1;
            if(out_ce!==ce_q[2]) $fatal(1,"stream CE mismatch");
            if(out_ce) begin
                checks=checks+1;
                if({out_hs,out_vs,out_de}!==sync_q[2]) $fatal(1,"stream sync mismatch");
                if(check_q[2] && {out_r,out_g,out_b}!==rgb_q[2])
                    $fatal(1,"stream RGB mismatch expected=%h got=%h",rgb_q[2],{out_r,out_g,out_b});
            end else if({out_r,out_g,out_b,out_hs,out_vs,out_de}!==held)
                $fatal(1,"stream output changed without CE");
        end
    end
    task frame(input integer animation,input bit gaps);
        integer x,y;
        begin
            for(y=0;y<104;y=y+1) for(x=0;x<136;x=x+1) begin
                @(negedge clk);
                in_ce=1;in_de=x<128 && y<96;in_hs=x>=130 && x<133;in_vs=y==98;
                {in_r,in_g,in_b}={8'(x),8'(y),8'(x^y)};
                expected_rgb={in_r,in_g,in_b};check_rgb=1;
                // Only the caption row may change; the separate test checks glyphs.
                if(animation>=0 && in_de && x>=18 && x<122 && y>=66 && y<74) check_rgb=0;
                if(animation>=0 && in_de && x>=90 && x<122 && y>=32 && y<64) check_rgb=0;   // icon
                if(gaps && (x*7+y*13)%5==0) begin
                    @(negedge clk);in_ce=0;
                    repeat((x+y)%3) @(negedge clk);
                end
            end
            @(negedge clk);in_ce=0;repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);reset=0;
        frame(-1,0);
        activity=1;repeat(4) @(negedge clk);
        frame(0,0);frame(1,1);frame(2,0);
        $display("PASS overlay continuous/bursty CE: %0d pixel and sync checks",checks);
        $finish;
    end
    initial begin #3000000;$fatal(1,"stream watchdog");end
endmodule
