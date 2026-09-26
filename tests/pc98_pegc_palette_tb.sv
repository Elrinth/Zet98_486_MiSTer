// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module pc98_pegc_palette_tb;
    parameter CPU_HALF_PS=5556, VIDEO_HALF_PS=19861, VIDEO_PHASE_PS=1300;
    reg cpu_clk=0,video_clk=0;
    always #(CPU_HALF_PS/1000.0) cpu_clk=~cpu_clk;
    initial begin #(VIDEO_PHASE_PS/1000.0);forever #(VIDEO_HALF_PS/1000.0) video_clk=~video_clk;end
    reg [7:0] ci=0,cd=0,vi=0;
    reg [1:0] cc=0;
    reg cw=0;
    wire [23:0] cr,vr;
    reg [23:0] expected[0:255];
    integer i,c,checks=0;
    pc98_pegc_palette dut(.cpu_clk(cpu_clk),.cpu_index(ci),.cpu_write(cw),
        .cpu_component(cc),.cpu_data(cd),.cpu_rgb(cr),
        .video_clk(video_clk),.video_index(vi),.video_rgb(vr));
    task check(input bit ok,input string msg);
        begin checks=checks+1;if(!ok)$fatal(1,"PEGC palette: %s",msg);end
    endtask
    task set_component(input [7:0] idx,input [1:0] component,input [7:0] value);
        begin
            @(negedge cpu_clk);ci=idx;cc=component;cd=value;cw=1;
            @(negedge cpu_clk);cw=0;
            case(component)
                1:expected[idx][15:8]=value;
                2:expected[idx][23:16]=value;
                3:expected[idx][7:0]=value;
                default:;
            endcase
        end
    endtask
    task read_cpu(input [7:0] idx);
        begin @(negedge cpu_clk);ci=idx;@(posedge cpu_clk);#0.001;
            check(cr===expected[idx],"CPU readback");end
    endtask
    task read_video(input [7:0] idx);
        reg [23:0] old_rgb;
        begin @(negedge video_clk);old_rgb=vr;vi=idx;#0.001;
            check(vr===old_rgb,"asynchronous pixel output");
            @(posedge video_clk);#0.001;check(vr===expected[idx],"video RGB888/index");end
    endtask
    initial begin
        for(i=0;i<256;i=i+1)expected[i]=0;
        // Every palette index, including high-bit aliases, starts black.
        for(i=0;i<256;i=i+1)begin read_cpu(i);read_video(i);end
        for(i=0;i<256;i=i+1)begin
            set_component(i,1,i^8'ha5);
            set_component(i,2,i);
            set_component(i,3,255-i);
            set_component(i,0,8'hff); // Index-select is not a component write.
        end
        for(i=255;i>=0;i=i-1)begin read_video(i);read_cpu(i);end
        // Pixel stream concurrently reads the lower half; CPU modifies upper
        // half. This avoids undefined same-cell collisions, but detects a live
        // CPU lookup mux or a single-port/time-sharing implementation.
        fork
            begin
                for(integer w=128;w<256;w=w+1)begin
                    set_component(w,1,w+17);set_component(w,2,w+31);set_component(w,3,w+79);
                end
            end
            begin
                for(integer r=0;r<512;r=r+1)read_video(r%128);
            end
        join
        for(i=0;i<256;i=i+1)begin read_cpu(i);read_video(i);end
        // Back-to-back pixel requests must each produce their own index.
        for(i=0;i<256;i=i+1)read_video((i*73)&255);
        $display("PASS: PEGC palette %0d checks at CPU half=%0d ps/video phase=%0d ps",checks,CPU_HALF_PS,VIDEO_PHASE_PS);
        $finish;
    end
    initial begin #1000000;$fatal(1,"PEGC palette timeout");end
endmodule
