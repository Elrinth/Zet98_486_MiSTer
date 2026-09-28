`timescale 1ns/1ps
module pcm86_tb;
    reg clk=0,reset=1;
    always #5 clk=!clk;
    reg [15:0] address=0;
    reg read=0,write=0;
    reg [7:0] writedata=0;
    wire [7:0] readdata;
    wire selected,irq,opna_extended,opna_muted,sample_valid;
    wire signed [15:0] audio_l,audio_r;
    pcm86 #(.CLOCK_HZ(1000000)) dut(.*);
    integer n,mode,frames=0,stream_index=0;
    reg stream_check=0;
    reg [7:0] expected_byte;
    task wr(input reg [15:0] a,input reg [7:0] d,input integer hold=1);
        begin
            @(negedge clk);address=a;writedata=d;write=1;
            repeat(hold) @(negedge clk);
            write=0;
            @(negedge clk);
        end
    endtask
    task rd(input reg [15:0] a,input reg [7:0] mask,value);
        begin
            @(negedge clk); address=a;read=1; #1;
            if(!selected || (readdata&mask)!==value) $fatal(1,"PCM read %h returned %h expected %h mask %h",a,readdata,value,mask);
            @(negedge clk);read=0;
        end
    endtask
    task fifo_reset;
        begin wr(16'ha468,8'h08);wr(16'ha468,0); end
    endtask
    task sample(input reg [15:0] l,r);
        begin
            @(negedge clk);
            while(!sample_valid) @(negedge clk);
            if(audio_l!==l || audio_r!==r) $fatal(1,"PCM sample L/R %h/%h expected %h/%h format %h",audio_l,audio_r,l,r,dut.format);
            frames=frames+1;
        end
    endtask
    always @(negedge clk) if(sample_valid && stream_check) begin
        expected_byte=stream_index<32768 ? (stream_index^8'ha5) : ((stream_index-32768)^8'h80);
        if(audio_l!=={expected_byte,8'b0} || audio_r!==0)
            $fatal(1,"PCM FIFO order/wrap failure sample %0d",stream_index);
        stream_index=stream_index+1;
    end
    initial begin
        repeat(4) @(negedge clk); reset=0;
        rd(16'ha460,8'hff,8'h40);
        wr(16'ha460,3); rd(16'ha460,8'hff,8'h43);
        if(!opna_extended || !opna_muted) $fatal(1,"OPNA control flags");
        address=16'ha461;read=1;#1;
        if(selected) $fatal(1,"PCM decoded an odd PC-98 port");
        read=0;
        wr(16'ha466,8'ha0); // maximum PCM volume
        for(mode=1;mode<8;mode=mode+1) if(mode!=4) begin
            fifo_reset;
            wr(16'ha46a,(mode<<4)|2);
            rd(16'ha46a,8'hff,(mode<<4)|2);
            wr(16'ha46c,8'h81,5); // held write must enqueue once
            if(dut.count!=1) $fatal(1,"held PCM write repeated");
            if(mode==1 || mode==2 || mode==3 || mode==7) wr(16'ha46c,8'h23);
            if(mode==3) begin wr(16'ha46c,8'h45);wr(16'ha46c,8'h67); end
            wr(16'ha468,8'h80);
            case(mode)
                1:sample(0,16'h8123); 2:sample(16'h8123,0);
                3:sample(16'h8123,16'h4567); 5:sample(0,16'h8100);
                6:sample(16'h8100,0); 7:sample(16'h8100,16'h2300);
            endcase
            rd(16'ha466,8'hc0,8'h40);
            repeat(50) @(negedge clk);
            if(dut.count!=0) $fatal(1,"FIFO underrun wrapped count");
            wr(16'ha66e,1);
            if(audio_l!==0 || audio_r!==0) $fatal(1,"PCM mute failed");
            wr(16'ha66e,0);
        end
        // Refill interrupt, acknowledgement, masking, and reset.
        fifo_reset;
        wr(16'ha46a,8'h62); // signed 8-bit left
        wr(16'ha468,8'h20);wr(16'ha46a,0); // 128-byte threshold
        for(n=0;n<200;n=n+1) wr(16'ha46c,n);
        wr(16'ha468,8'hb0);
        while(dut.count>132) begin
            @(negedge clk);
            if(irq) $fatal(1,"PCM IRQ arrived above threshold");
        end
        while(!irq) @(negedge clk);
        if(dut.count>128) $fatal(1,"PCM IRQ threshold mismatch");
        rd(16'ha468,8'h10,8'h10);
        wr(16'ha468,8'ha0); // acknowledge: bit 4 1 -> 0
        // Still below the threshold, so the request comes back; A468h writes
        // that leave bit 4 at 0 are not acknowledgements and must keep it.
        while(!irq) @(negedge clk);
        wr(16'ha468,8'ha0); wr(16'ha468,8'ha0);
        if(!irq) $fatal(1,"PCM IRQ lost on a non-acknowledging A468h write");
        wr(16'ha468,8'h10); wr(16'ha468,0); // stop, mask and acknowledge
        if(irq) $fatal(1,"PCM IRQ did not clear");
        fifo_reset;
        // Whole physical FIFO, full rejection, concurrent refill and pointer wrap.
        wr(16'ha46a,8'h62);
        for(n=0;n<32768;n=n+1) wr(16'ha46c,n^8'ha5);
        rd(16'ha466,8'hc0,8'h80);
        wr(16'ha46c,8'hff);
        if(dut.count!=32768) $fatal(1,"FIFO overflow changed size");
        stream_check=1;
        wr(16'ha468,8'h80);
        wait(stream_index>=128);
        for(n=0;n<100;n=n+1) wr(16'ha46c,n^8'h80);
        wait(stream_index==32868);
        stream_check=0;
        repeat(50) @(negedge clk);
        rd(16'ha466,8'hc0,8'h40);
        if(dut.count!=0 || irq) $fatal(1,"FIFO empty/masked IRQ failed");
        wr(16'ha468,0);wr(16'ha46c,1);wr(16'ha468,8'h08);
        if(dut.count!=0 || audio_l!==0 || audio_r!==0) $fatal(1,"FIFO reset did not clear sample/state");
        $display("PASS: PCM86 six formats, signed big-endian samples, 32 KB FIFO, held writes, wrap/concurrent refill, full/empty, IRQ threshold/ack (bit 4 1->0 only)/mask, mute/reset; %0d stream samples",stream_index);
        $finish;
    end
    initial begin #20000000; $fatal(1,"PCM FIFO watchdog"); end
endmodule
