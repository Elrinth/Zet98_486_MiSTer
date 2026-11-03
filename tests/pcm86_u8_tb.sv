// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Ultima VIII (PC-98, PCM9821.DLL) speech, port sequence from NP2kai. The
// first sound fills the FIFO above the threshold; each later sample starts
// with playback and interrupts already on: FIFO reset (A468h = BCh, B4h), then
// only 256 bytes against a 768-byte threshold. NP2kai interrupts as soon as
// that burst is written; the driver feeds the rest from its IRQ 12 handler,
// which loops IN/AND EF/OUT, OR 10/OUT while A468h bit 4 reads set. Without
// that interrupt the speech never continues and the intro stops on the
// Guardian's hand.
module pcm86_u8_tb;
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
    reg irr=0, irq_d=0;
    always @(posedge clk) begin
        irq_d<=irq;
        if(irq && !irq_d) irr<=1;
    end
    integer i,round,ints=0,early=0,spins;
    reg [7:0] v;
    reg bursting=0;
    always @(posedge clk) if(bursting && irq && !irq_d) early=early+1;
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
    task fill(input integer n);
        begin
            bursting=1;
            for(i=0;i<n;i=i+1) wr(16'ha46c,i[7:0]);
            bursting=0;
        end
    endtask
    // The driver's IRQ 12 handler (segments 0937h/0A7Fh in NP2kai's log).
    task isr;
        begin
            spins=0;
            rd(16'ha468,v);
            while(v[4]) begin
                rd(16'ha468,v); wr(16'ha468,v&8'hef); wr(16'ha468,v|8'h10);
                rd(16'ha468,v); spins=spins+1;
                if(spins>100000) $fatal(1,"IRQ handler never saw the request bit clear");
            end
            rd(16'ha468,v); wr(16'ha468,v&8'hef); wr(16'ha468,v|8'h10);
        end
    endtask
    task wait_irq(input integer limit);
        integer t;
        begin
            t=0;
            while(!irr) begin
                @(negedge clk); t=t+1;
                if(t>limit) $fatal(1,"no PCM interrupt %0d clocks after a %0s (round %0d, FIFO %0d, threshold %0d)",
                                   limit,round<0 ? "full start" : "below-threshold refill",round,dut.count,dut.threshold);
            end
            irr=0; ints=ints+1;
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);reset=0;
        // Stop and reset, 8-bit stereo, volume, 11.025 kHz, IRQ on, 768-byte threshold.
        rd(16'ha468,v); wr(16'ha468,8'h00); wr(16'ha468,8'h08); wr(16'ha468,8'h00);
        wr(16'ha46a,8'hf2); wr(16'ha466,8'ha3);
        wr(16'ha468,8'h04); wr(16'ha468,8'h34);
        rd(16'ha468,v); wr(16'ha468,8'h24); wr(16'ha468,8'h34);
        wr(16'ha46a,8'h05);
        if(dut.threshold!=768) $fatal(1,"threshold %0d",dut.threshold);
        // First sound: nearly full FIFO, then play. The interrupt comes at the threshold.
        round=-1;
        fill(4096);
        rd(16'ha468,v); wr(16'ha468,8'hb4);
        wait_irq(1000000);
        isr;
        // Speech samples: playing, FIFO reset, 256 bytes (below the threshold).
        for(round=0;round<6;round=round+1) begin
            rd(16'ha468,v); wr(16'ha468,8'hbc); wr(16'ha468,8'hb4);
            fill(256);
            // A few sample periods (~91 clocks each at 11.025 kHz here).
            wait_irq(600);
            if(dut.count>dut.threshold) $fatal(1,"interrupt above the threshold");
            isr;
        end
        if(early) $fatal(1,"%0d interrupt(s) in the middle of a FIFO burst",early);
        // A short sound written with playback off, then started with interrupts on: the
        // enable interrupts once (as before); the below-threshold arm must not add a second.
        wr(16'ha468,8'h04); wr(16'ha468,8'h0c); wr(16'ha468,8'h04);
        fill(100);
        irr=0;
        rd(16'ha468,v); wr(16'ha468,8'hb4);
        round=-2;
        wait_irq(600);
        isr;
        repeat(3000) @(negedge clk);
        if(irr) $fatal(1,"second interrupt after a short sound started with interrupts on");
        $display("PASS: Ultima VIII speech: interrupt after each below-threshold refill (%0d interrupts), none mid-burst, one for a started short sound",ints);
        $finish;
    end
    initial begin #200000000;$fatal(1,"Ultima VIII watchdog (interrupts %0d)",ints);end
endmodule
