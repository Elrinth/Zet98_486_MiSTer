`timescale 1ps/1ps
module osd_video_tb;
parameter SYS_HALF_PS = 8333;
parameter VIDEO_PHASE_PS = 1000;
reg clk_sys=0, clk_video=0;
always #(SYS_HALF_PS) clk_sys=~clk_sys;
initial begin #(VIDEO_PHASE_PS); forever #6667 clk_video=~clk_video; end
reg io_osd=0, io_strobe=0;
reg [15:0] io_din=0;
reg [23:0] din=24'h102030;
reg de_in=0, vs_in=0, hs_in=0;
wire [23:0] actual, expected;
wire de_a,vs_a,hs_a,status_a,de_r,vs_r,hs_r,status_r;
osd dut(clk_sys,io_osd,io_strobe,io_din,clk_video,din,de_in,vs_in,hs_in,
        actual,de_a,vs_a,hs_a,status_a);
osd_legacy reference_osd(clk_sys,io_osd,io_strobe,io_din,clk_video,din,de_in,vs_in,hs_in,
        expected,de_r,vs_r,hs_r,status_r);

reg [131:0] expected_settings=0;
integer setting_checks=0, pixel_checks=0, drawn=0;
reg compare=0;
always @(posedge clk_video) begin
    if(dut.host_osd_settings.request_sync[1] != dut.host_osd_settings.acknowledge)
        expected_settings=dut.host_osd_settings.held_data;
    #1;
    if(dut.osd_config_video !== expected_settings) $fatal(1,"menu settings snapshot mismatch");
    setting_checks=setting_checks+1;
    if(compare) begin
        if({actual,de_a,vs_a,hs_a} !== {expected,de_r,vs_r,hs_r})
            $fatal(1,"menu pixel/sync mismatch after stable configuration at pixel %0d",pixel_checks);
        if(de_a && actual != 24'h102030) drawn=drawn+1;
        pixel_checks=pixel_checks+1;
    end
end
always @(negedge clk_sys)
    if(status_a !== status_r) $fatal(1,"menu CPU status changed");

task word(input [15:0] value);
begin
    @(negedge clk_sys); io_din=value; io_strobe=0;
    repeat(2) @(negedge clk_sys);
    io_strobe=1;
    repeat(2) @(negedge clk_sys);
    io_strobe=0;
end endtask
task end_command;
begin
    @(negedge clk_sys); io_osd=0;
    repeat(6) @(negedge clk_sys);
end endtask
task configure(input integer enabled, info_mode, rotation);
begin
    @(negedge clk_sys); io_osd=1;
    word(16'h40 | enabled | (info_mode<<2));
    word(20); word(24); word(16); word(8); word(rotation);
    end_command;
end endtask
task frame(input integer width,height);
integer x,y;
begin
    for(y=0;y<height+40;y=y+1) begin
        for(x=0;x<width+100;x=x+1) begin
            @(negedge clk_video);
            de_in=(x<width && y<height);
            hs_in=(x>=width+16 && x<width+40);
            vs_in=(y>=height+8 && y<height+12);
        end
    end
end endtask

integer page,b,i,width,height,before_drawn;
initial begin
    // Tests use a zero-power-up model of BOTH implementations. The original
    // OSD has no reset and otherwise remains X indefinitely in four-state RTL.
    // RAM is still filled through the real CPU command interface.
    repeat(8) @(negedge clk_sys);
    for(page=0;page<16;page=page+1) begin
        io_osd=1; word(16'h20 | page);
        for(b=0;b<256;b=b+1) word((b ^ page)&1 ? 8'hA5 : 8'h5A);
        end_command;
    end
    for(i=0;i<8;i=i+1) begin
        compare=0;
        width=i[0] ? 320 : 640;
        height=i[0] ? 200 : 400;
        configure(i!=7, i<4, i&3);
        repeat(6) frame(width,height);
        before_drawn=drawn;
        compare=1; frame(width,height); compare=0;
        if(i!=7 && drawn==before_drawn) $fatal(1,"case %0d never drew menu pixels",i);
        if(i==7 && drawn!=before_drawn) $fatal(1,"disabled menu drew pixels");
        $display("PASS menu case %0d rotation=%0d info=%0d %0dx%0d",i,i&3,i<4,width,height);
    end
    $display("PASS menu settings=%0d pixel/sync=%0d drawn=%0d sys_half=%0d phase=%0d",
             setting_checks,pixel_checks,drawn,SYS_HALF_PS,VIDEO_PHASE_PS);
    $finish;
end
initial begin #(64'd2000000000000); $fatal(1,"menu test timeout"); end
endmodule
