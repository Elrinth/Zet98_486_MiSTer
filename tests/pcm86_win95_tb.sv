// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Windows 95 NEC73PCM.DRV wave playback (port sequence from NP2kai, ISR code
// at segment 1 offset 1A96h): IN/AND EF/OUT (acknowledge), IN/AND CF/OR 10/OUT
// (IRQ off), refill, IN/OR 30/OUT (IRQ on). VPICD masks IRQ12 during the ISR;
// the 8259 still latches edges. An interrupt with the FIFO above the
// threshold makes the driver find no queued wave buffer and stop playback.
module pcm86_win95_tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [15:0] address=0;
    reg read=0,write=0;
    reg [7:0] writedata=0;
    wire [7:0] readdata;
    wire selected,irq,opna_extended,opna_muted,sample_valid;
    wire signed [15:0] audio_l,audio_r;
    pcm86 #(.CLOCK_HZ(1000000)) dut(.*);
    // 8259 input: edge-triggered, latched even while masked.
    reg irr=0, masked=0, irq_d=0;
    always @(posedge clk) begin
        irq_d<=irq;
        if(irq && !irq_d) irr<=1;
    end
    integer i,round,spurious=0,ints=0;
    reg [7:0] v;
    task wr(input [15:0] a,input [7:0] d);
        begin
            @(negedge clk);address=a;writedata=d;write=1;
            @(negedge clk);write=0;
            @(negedge clk);
        end
    endtask
    task rd(input [15:0] a,output [7:0] d);
        begin
            @(negedge clk);address=a;read=1;
            #1;d=readdata;
            @(negedge clk);read=0;
        end
    endtask
    // NEC73PCM delay: watch A466 bit 0 (sample clock) change state.
    task delay;
        reg [7:0] a,b;
        integer k;
        begin
            for(k=0;k<3;k=k+1) begin
                rd(16'ha466,a);
                b=a;
                while(b[0]==a[0]) rd(16'ha466,b);
            end
        end
    endtask
    task fill(input integer n);
        for(i=0;i<n;i=i+1) wr(16'ha46c,i[7:0]);
    endtask
    initial begin
        repeat(4) @(negedge clk);reset=0;
        // Driver open/start as logged: 22.05 kHz, 8-bit stereo, threshold 2048.
        wr(16'ha468,8'h1a); delay;
        wr(16'ha468,8'h12); delay;
        wr(16'ha46a,8'hf2); delay;
        rd(16'ha468,v); wr(16'ha468,8'h32);
        wr(16'ha46a,8'h0f); delay;
        rd(16'ha468,v); wr(16'ha468,8'h12);
        fill(4096);
        rd(16'ha468,v); wr(16'ha468,8'h22); delay;
        rd(16'ha468,v); wr(16'ha468,v|8'h90);
        if(dut.threshold!=2048) $fatal(1,"threshold %0d",dut.threshold);
        for(round=0;round<12;round=round+1) begin
            while(!(irr && !masked)) @(negedge clk);
            irr=0; masked=1; ints=ints+1;
            if(dut.count>dut.threshold) begin
                spurious=spurious+1;
                $display("spurious interrupt %0d: FIFO %0d above threshold %0d",ints,dut.count,dut.threshold);
            end
            rd(16'ha468,v);
            if(!v[4]) $fatal(1,"interrupt %0d without the PCM request bit",ints);
            wr(16'ha468,v&8'hef);
            delay;
            rd(16'ha468,v); wr(16'ha468,(v&8'hcf)|8'h10);
            delay;
            fill(4096);
            rd(16'ha468,v); wr(16'ha468,v|8'h30);
            masked=0;
        end
        if(spurious) $fatal(1,"%0d of %0d interrupts arrived with the FIFO refilled (Windows 95 stops the sound)",spurious,ints);
        $display("PASS: NEC73PCM (Windows 95) refill: %0d interrupts, each at the threshold, none after a refill",ints);
        $finish;
    end
    initial begin #400000000;$fatal(1,"Windows 95 refill watchdog (interrupts stopped after %0d)",ints);end
endmodule
