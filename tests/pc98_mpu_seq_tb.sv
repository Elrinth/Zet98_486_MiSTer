`timescale 1ns/1ps
// MPU-PC98II intelligent-mode sequencer as Arsys NMD (Star Cruiser II) uses
// it: Act Tr, conductor on, Start Play; the MPU requests conductor (F9) and
// track (F0) data, the host answers with a timing byte and an event, and each
// event reaches MIDI out when its track counts down to zero. Also: a conductor
// tempo change, running status in track data and in D0 messages, the FC track
// end, A0-AF requests and Stop Play.
module pc98_mpu_seq_tb;
    parameter integer CLOCK_MHZ=20;
    localparam integer CLOCK_HZ=CLOCK_MHZ*1000000;
    reg clk=0;
    always #(500.0/CLOCK_MHZ) clk=~clk;
    reg reset=1, enable=1;
    reg [15:0] io_address=0, io_writedata=0;
    reg [1:0] io_select=1;
    reg io_read=0, io_write=0;
    wire [7:0] io_readdata;
    wire io_oe, irq, midi_tx, rx_overrun, rx_framing_error, tx_overrun;
    wire midi_rx=1'b1;
    pc98_mpu_uart #(.CLOCK_HZ(CLOCK_HZ)) dut(.*);

    reg [7:0] wire_bytes[0:63];
    integer wire_count=0;
    always begin : wire_receiver
        reg [7:0] value;
        @(negedge midi_tx);
        #(16000);
        if (midi_tx !== 0) $fatal(1,"Invalid MIDI start bit");
        for(integer b=0;b<8;b=b+1) begin #(32000); value[b]=midi_tx; end
        #(32000);
        if (midi_tx !== 1) $fatal(1,"Invalid MIDI stop bit");
        if (wire_count<64) wire_bytes[wire_count]=value;
        wire_count=wire_count+1;
    end
    task automatic wr(input [15:0] addr,input [7:0] data);
        @(negedge clk);io_address=addr;io_writedata={8'h00,data};io_write=1;
        repeat(5) @(negedge clk);
        io_write=0;
        repeat(2) @(negedge clk);
    endtask
    task automatic rd(input [15:0] addr,output [7:0] data);
        @(negedge clk);io_address=addr;io_read=1;
        @(negedge clk);data=io_readdata;
        repeat(5) @(negedge clk);
        io_read=0;
        repeat(2) @(negedge clk);
    endtask
    task automatic command(input [7:0] c);
        reg [7:0] v;
        wr(16'he0d2,c);
        for (integer i=0;i<200;i=i+1) begin
            rd(16'he0d2,v);
            if (!v[7]) begin
                rd(16'he0d0,v);
                if (v!==8'hfe) $fatal(1,"command %02x: got %02x instead of ACK FE",c,v);
                return;
            end
        end
        $fatal(1,"command %02x was not ACKed",c);
    endtask
    // Wait for the next byte from the MPU (request or message), with a timeout.
    task automatic next_msg(input integer ms, output [7:0] v);
        longint stop;
        stop=$time+longint'(ms)*1000000;
        while ($time<stop) begin
            rd(16'he0d2,v);
            if (!v[7]) begin
                if (!irq) $fatal(1,"MPU has data but IRQ is low");
                rd(16'he0d0,v);
                return;
            end
            repeat(50) @(negedge clk);
        end
        $fatal(1,"no request from the MPU within %0d ms (NMD would wait forever)",ms);
    endtask
    task automatic expect_msg(input [7:0] want, input integer ms);
        reg [7:0] v;
        next_msg(ms,v);
        if (v!==want) $fatal(1,"expected %02x from the MPU, got %02x",want,v);
    endtask
    task automatic expect_wire(input integer n, input [7:0] b0, input [7:0] b1, input [7:0] b2);
        #(3000000);
        if (wire_count<n+3) $fatal(1,"MIDI out has %0d bytes, expected %0d",wire_count,n+3);
        if (wire_bytes[n]!==b0 || wire_bytes[n+1]!==b1 || wire_bytes[n+2]!==b2)
            $fatal(1,"MIDI out %02x %02x %02x, expected %02x %02x %02x",
                     wire_bytes[n],wire_bytes[n+1],wire_bytes[n+2],b0,b1,b2);
    endtask
    initial begin
        reg [7:0] v;
        longint t0, t1;
        repeat(10) @(negedge clk);
        reset=0;
        repeat(10) @(negedge clk);
        command(8'hff);
        command(8'hc5);                                   // timebase 120
        command(8'he0); wr(16'he0d0,8'd100);          // 200 internal clocks/s
        command(8'hec); wr(16'he0d0,8'h01);           // track 1 active
        command(8'h8f);                                   // conductor on
        command(8'hb8);                                   // clear play counters
        command(8'h0a);                                   // start play
        // Conductor first: wait 80 clocks, then set tempo 150 (300 clocks/s).
        expect_msg(8'hf9,50);
        wr(16'he0d0,8'd80); wr(16'he0d0,8'he0); wr(16'he0d0,8'd150);
        // Track 1: note on after 30 clocks.
        expect_msg(8'hf0,50);
        wr(16'he0d0,8'd30); wr(16'he0d0,8'h90); wr(16'he0d0,8'h3c); wr(16'he0d0,8'h64);
        t0=$time;
        expect_msg(8'hf0,500);
        t1=$time;
        // 30 clocks at 300/s = 100 ms.
        if (t1-t0 < 80000000 || t1-t0 > 120000000)
            $fatal(1,"track step of 30 clocks took %0d us, expected ~100000 (tempo 150)",(t1-t0)/1000);
        expect_wire(0,8'h90,8'h3c,8'h64);
        // Running status: note off (velocity 0) after 6 clocks.
        wr(16'he0d0,8'd6); wr(16'he0d0,8'h3c); wr(16'he0d0,8'h00);
        expect_msg(8'hf0,200);
        expect_wire(3,8'h90,8'h3c,8'h00);
        // End of track.
        wr(16'he0d0,8'd0); wr(16'he0d0,8'hfc);
        expect_msg(8'hfc,200);
        command(8'h05);                                   // stop play
        repeat(200000) @(negedge clk);
        rd(16'he0d2,v);
        if (!v[7]) begin rd(16'he0d0,v); $fatal(1,"request %02x after Stop Play",v); end
        // D0 messages keep running status.
        command(8'hd0); wr(16'he0d0,8'h91); wr(16'he0d0,8'h40); wr(16'he0d0,8'h7f);
        command(8'hd0); wr(16'he0d0,8'h40); wr(16'he0d0,8'h00);
        expect_wire(6,8'h91,8'h40,8'h7f);
        expect_wire(9,8'h91,8'h40,8'h00);
        // Arsys NMD MT-32 setup: the conductor issues DF (timing 5); its
        // SysEx follows at the next F9, then the next timing and command.
        command(8'hb8);
        command(8'h0a);
        expect_msg(8'hf9,50);
        wr(16'he0d0,8'd5); wr(16'he0d0,8'hdf);
        expect_msg(8'hf0,50);
        wr(16'he0d0,8'd5); wr(16'he0d0,8'hf8);
        expect_msg(8'hf9,500);
        begin
            reg [7:0] sx[0:9];
            sx[0]=8'hf0; sx[1]=8'h41; sx[2]=8'h10; sx[3]=8'h16; sx[4]=8'h12;
            sx[5]=8'h7f; sx[6]=8'h00; sx[7]=8'h00; sx[8]=8'h01; sx[9]=8'hf7;
            for (integer k=0;k<10;k=k+1) wr(16'he0d0,sx[k]);
            wr(16'he0d0,8'd5); wr(16'he0d0,8'hdf);
            #(5000000);
            if (wire_count<22) $fatal(1,"conductor SysEx: MIDI out has %0d bytes, expected 22",wire_count);
            for (integer k=0;k<10;k=k+1)
                if (wire_bytes[12+k]!==sx[k]) $fatal(1,"conductor SysEx byte %0d: %02x, expected %02x",k,wire_bytes[12+k],sx[k]);
        end
        expect_msg(8'hf0,500);
        command(8'h05);
        command(8'hac); expect_msg(8'h01,5);            // major version 1
        command(8'had); expect_msg(8'h00,5);            // minor version 0
        command(8'hff);
        $display("PASS MPU sequencer: conductor F9 and track F0 requests, tempo change, events and running status on MIDI out, FC end, A0-AF replies, Stop Play, D0 running status, conductor DF SysEx (NMD)");
        $finish;
    end
    initial begin #3000000000; $fatal(1,"timeout"); end
endmodule
