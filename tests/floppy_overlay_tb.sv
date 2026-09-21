`timescale 1ns/1ps
module floppy_overlay_tb;
    reg clk=0, reset=1, enabled=1, activity=0;
    always #5 clk=!clk;
    reg in_ce=0, in_hs=0, in_vs=0, in_de=0;
    reg [7:0] in_r=8'h11, in_g=8'h22, in_b=8'h33;
    wire out_ce, out_hs, out_vs, out_de;
    wire [7:0] out_r,out_g,out_b;
    floppy_overlay #(.HOLD_FRAMES(3), .ROTATE_FRAME_BITS(0)) dut(.*);
    reg [23:0] sprite[0:255], previous[0:255];
    reg [26:0] held;
    integer changed, px, py, i, j, frames=0;
    task frame(input integer w,h, input bit check_bounds);
        begin
            changed=0;
            for (i=0;i<256;i=i+1) sprite[i]=24'h112233;
            for (py=0;py<h+8;py=py+1) begin
                for (px=0;px<w+8;px=px+1) begin
                    @(negedge clk);
                    in_ce=1; in_de=px<w && py<h;
                    in_hs=px>=w+2 && px<w+5; in_vs=py==h+2;
                    @(posedge clk); #1;
                    if (!out_ce || {out_hs,out_vs,out_de} !== {in_hs,in_vs,in_de})
                        $fatal(1,"overlay changed video timing");
                    if ({out_r,out_g,out_b} !== 24'h112233) begin
                        changed=changed+1;
                        if (!in_de) $fatal(1,"overlay drew into blanking");
                        if (check_bounds && !(px>=w-20 && px<w-4 && py>=h-20 && py<h-4))
                            $fatal(1,"icon outside bottom-right box: %0d,%0d",px,py);
                    end
                    if (px>=w-20 && px<w-4 && py>=h-20 && py<h-4)
                        sprite[(py-h+20)*16+px-w+20]={out_r,out_g,out_b};
                    held={out_r,out_g,out_b,out_hs,out_vs,out_de};
                    @(negedge clk); in_ce=0;
                    @(posedge clk); #1;
                    if (out_ce || {out_r,out_g,out_b,out_hs,out_vs,out_de} !== held)
                        $fatal(1,"overlay changed a pixel without CE");
                end
            end
            frames=frames+1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);
        reset=0;
        frame(64,32,1);
        if (changed) $fatal(1,"idle floppy icon was visible");
        activity=1;
        frame(64,32,1);
        if (changed<150) $fatal(1,"activity did not show floppy icon");
        for(i=0;i<256;i=i+1) previous[i]=sprite[i];
        frame(64,32,1);
        for(i=0;i<16;i=i+1)
            for(j=0;j<16;j=j+1)
                if(sprite[i*16+j] !== previous[(15-j)*16+i])
                    $fatal(1,"floppy did not rotate one quarter turn");
        enabled=0;
        frame(64,32,1);
        if (changed) $fatal(1,"disabled icon changed the picture");
        enabled=1; activity=0;
        frame(64,32,1);
        if (changed<150) $fatal(1,"brief activity was not held visibly");
        repeat(4) frame(64,32,1);
        if (changed) $fatal(1,"floppy icon did not expire after activity");
        activity=1;
        frame(80,40,0); // First frame learns the changed dimensions.
        frame(80,40,1);
        if (changed<150) $fatal(1,"icon missing after a mode change");
        $display("PASS: floppy overlay: %0d frames, timing/CE, idle/disable/expiry, rotation, two raster sizes",frames);
        $finish;
    end
    initial begin #10000000; $fatal(1,"floppy overlay watchdog"); end
endmodule
