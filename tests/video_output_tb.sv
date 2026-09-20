`timescale 1ns/1ps
module video_output_tb;
    reg clk = 0, reset = 1, pattern = 0;
    always #5 clk = !clk;
    reg native_ce = 0;
    reg [7:0] nr=0, ng=0, nb=0;
    reg nh=0, nv=0, nd=0;
    wire ce, hs, vs, de;
    wire [7:0] r,g,b;
    video_output dut(clk,reset,pattern,native_ce,nr,ng,nb,nh,nv,nd,ce,r,g,b,hs,vs,de);
    integer i, pixels, active_pixels, hsync_pixels, vsync_pixels, line_pixels;
    integer active_lines, line_active, enable_spacing;
    reg last_vs;
    reg [26:0] held;
    task tick;
        begin @(posedge clk); #1; end
    endtask
    initial begin
        tick; reset = 0;
        // Native data and sync must be transferred as one pixel and held
        // throughout gaps in CE, even if native inputs change in those gaps.
        for (i=0;i<60;i=i+1) begin
            @(negedge clk);
            native_ce = (i%3)==0;
            nr=i; ng=~i; nb=i*7; nh=i[0]; nv=i[1]; nd=i[2];
            tick;
            if (ce !== native_ce) $fatal(1,"Native pixel enable mismatch");
            if (native_ce) begin
                if ({r,g,b,hs,vs,de} !== {nr,ng,nb,nh,nv,nd})
                    $fatal(1,"Native data/sync alignment mismatch");
                held={r,g,b,hs,vs,de};
            end else if ({r,g,b,hs,vs,de} !== held)
                $fatal(1,"Pixel changed without clock enable");
        end
        @(negedge clk); native_ce=0; pattern=1;
        // Observe one complete raster from VS rising to the next VS rising.
        // Counts verify the public output timing rather than internal counters.
        last_vs=0;
        begin : find_frame
            for (i=0;i<4000000;i=i+1) begin
                tick;
                if (ce) begin
                    if (vs && !last_vs) disable find_frame;
                    last_vs=vs;
                end
            end
            $fatal(1,"Diagnostic raster did not start");
        end
        pixels=0; active_pixels=0; hsync_pixels=0; vsync_pixels=0;
        active_lines=0; line_pixels=0; line_active=0; enable_spacing=0;
        last_vs=1;
        begin : frame
            for (i=0;i<1300000;i=i+1) begin
                tick; enable_spacing=enable_spacing+1;
                if (ce) begin
                    if (enable_spacing!=3) $fatal(1,"Diagnostic CE must divide clock by 3");
                    enable_spacing=0;
                    pixels=pixels+1;
                    active_pixels=active_pixels+de;
                    hsync_pixels=hsync_pixels+hs;
                    vsync_pixels=vsync_pixels+vs;
                    if (!de && {r,g,b} !== 24'b0) $fatal(1,"Nonblack blanking pixel");
                    if (vs && !last_vs) disable frame;
                    last_vs=vs;
                end
            end
            $fatal(1,"Diagnostic raster did not complete");
        end
        if (pixels!=800*525 || active_pixels!=640*480 ||
            hsync_pixels!=96*525 || vsync_pixels!=2*800)
            $fatal(1,"Raster totals: pixels=%0d active=%0d HS=%0d VS=%0d",
                   pixels,active_pixels,hsync_pixels,vsync_pixels);
        $display("PASS: registered native pixels; diagnostic 800x525 total, 640x480 active raster");
        $finish;
    end
endmodule
