// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// AVSDRV performs IN A468 / AND AL,EF / OUT A468 before and after refilling.
module pcm86_driver_refill_tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [15:0] address=0;
    reg read=0,write=0;
    reg [7:0] writedata=0;
    wire [7:0] readdata;
    wire selected,irq,opna_extended,opna_muted,sample_valid;
    wire signed [15:0] audio_l,audio_r;
    pcm86 #(.CLOCK_HZ(1000000)) dut(.*);
    integer i,round;
    reg [7:0] value;
    task wr(input [15:0] a,input [7:0] d);
        begin
            @(negedge clk);address=a;writedata=d;write=1;
            @(negedge clk);write=0;
            @(negedge clk);
        end
    endtask
    task driver_ack;
        begin
            @(negedge clk);address=16'ha468;read=1;
            #1;value=readdata & 8'hef;
            @(negedge clk);read=0;
            wr(16'ha468,value);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);reset=0;
        wr(16'ha468,8'h03);
        wr(16'ha46a,8'hb2); // 16-bit stereo
        wr(16'ha468,8'h33);
        wr(16'ha46a,8'h08); // 1152 bytes
        for(i=0;i<4096;i=i+1) wr(16'ha46c,i);
        wr(16'ha468,8'hb3); // initial acknowledgement bit set
        for(round=0;round<4;round=round+1) begin
            wait(irq);
            driver_ack;
            // Non-acknowledging control writes while low must keep a refill request.
            wait(irq);
            wr(16'ha468,8'ha3);
            if(!irq) $fatal(1,"low-FIFO control write lost request");
            for(i=0;i<4096;i=i+1) wr(16'ha46c,i^round);
            if(dut.count<=dut.threshold) $fatal(1,"test refill did not raise count");
            driver_ack;
            #1;
            if(irq || readdata[4])
                $fatal(1,"AVSDRV post-refill acknowledgement left stale PCM request round=%0d count=%0d",round,dut.count);
        end
        $display("PASS: repeated AVSDRV read/clear/write acknowledgements after refill, low-FIFO request preservation");
        $finish;
    end
    initial begin #10000000;$fatal(1,"driver refill watchdog");end
endmodule
