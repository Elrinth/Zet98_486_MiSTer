`timescale 1ns/1ps
// Compare the actual caption-coordinate path with the original arithmetic
// over all low-bit coordinate/origin combinations, including wrapped offsets.
module floppy_caption_tb;
    reg clk=0,reset=1,enabled=0;
    always #5 clk=~clk;
    reg [1:0] activity=0;
    reg [11:0] crop_left=0,crop_top=0,crop_width=0,crop_height=0;
    reg in_ce=0,in_hs=0,in_vs=0,in_de=0;
    reg [7:0] in_r=0,in_g=0,in_b=0;
    wire out_ce,out_hs,out_vs,out_de;
    wire [7:0] out_r,out_g,out_b;
    floppy_overlay #(.TILE_MAP_FILE("rtl/assets/floppy-tile-map.mem"),
        .TILE_PIXELS_FILE("rtl/assets/floppy-tile-pixels.mem")) dut(.*);
    reg [11:0] test_x=0,test_right=0;
    integer i,j,offset,checks=0;
    initial begin
        repeat(3) @(negedge clk);reset=0;
        force dut.x=test_x;
        force dut.right_edge=test_right;
        for(i=0;i<4096;i=i+1) begin
            @(negedge clk);test_right=i;
            force dut.position_pending=2'b10;
            @(negedge clk);release dut.position_pending;
            for(j=0;j<128;j=j+1) begin
                test_x=j;#1;
                offset=((j-((i-92)&127))-5)&127;
                if(dut.character!==((offset/6)&15) || dut.column!==(offset%6))
                    $fatal(1,"caption coordinate mismatch right=%0d x=%0d",i,j);
                checks=checks+1;
            end
        end
        release dut.x;release dut.right_edge;
        $display("PASS caption coordinates: %0d original-division comparisons",checks);
        $finish;
    end
endmodule
