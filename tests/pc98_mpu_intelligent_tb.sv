`timescale 1ns/1ps
// MPU-PC98II intelligent-mode subset used by KAJA's MMD (Cyber Arms): every
// command is ACKed (FE), E0/E7 take a data byte, clock-to-host (95) sends FD
// at tempo x timebase / 60 internal clocks per second divided by the E7 rate,
// 94 stops it, and bytes after D0 ("want to send data") reach MIDI out.
module pc98_mpu_intelligent_tb;
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

    reg [7:0] wire_bytes[0:15];
    integer wire_count=0;
    always begin : wire_receiver
        reg [7:0] value;
        @(negedge midi_tx);
        #(16000);
        if (midi_tx !== 0) $fatal(1,"Invalid MIDI start bit");
        for(integer b=0;b<8;b=b+1) begin #(32000); value[b]=midi_tx; end
        #(32000);
        if (midi_tx !== 1) $fatal(1,"Invalid MIDI stop bit");
        if (wire_count<16) wire_bytes[wire_count]=value;
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
    // Write a command and wait (with a timeout, unlike MMD) for its ACK.
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
        $fatal(1,"command %02x was not ACKed (MMD would wait forever)",c);
    endtask
    // Count FD messages over a time window.
    task automatic count_fd(input integer ms,output integer n);
        reg [7:0] v;
        longint stop;
        n=0;
        stop=$time+longint'(ms)*1000000;
        while ($time<stop) begin
            rd(16'he0d2,v);
            if (!v[7]) begin
                rd(16'he0d0,v);
                if (v!==8'hfd) $fatal(1,"expected clock-to-host FD, got %02x",v);
                n=n+1;
            end
            repeat(200) @(negedge clk);
        end
    endtask
    initial begin
        integer n;
        repeat(10) @(negedge clk);
        reset=0;
        repeat(10) @(negedge clk);
        command(8'hff);
        command(8'hc5);                  // timebase 120
        command(8'he0); wr(16'he0d0,8'd100);   // 100 BPM: 200 internal clocks/s
        command(8'he7); wr(16'he0d0,8'd24);    // FD every 6 internal clocks
        command(8'h95);                  // clock to host on: ~33.3 FD/s
        count_fd(300,n);
        if (n<9 || n>11) $fatal(1,"clock-to-host: %0d FD in 300 ms, expected 10",n);
        command(8'he0); wr(16'he0d0,8'd200);   // double tempo: ~66.7 FD/s
        count_fd(300,n);
        if (n<19 || n>21) $fatal(1,"clock-to-host at 200 BPM: %0d FD in 300 ms, expected 20",n);
        command(8'h94);                  // clock to host off
        begin
            reg [7:0] v;
            repeat(20000) @(negedge clk);
            rd(16'he0d2,v);
            if (!v[7]) begin rd(16'he0d0,v); if (v===8'hfd) $fatal(1,"FD after 94 (clock to host off)"); end
        end
        command(8'hd0);                  // want to send data: a note on
        wr(16'he0d0,8'h90); wr(16'he0d0,8'h3c); wr(16'he0d0,8'h64);
        #(3000000);
        if (wire_count!=3 || wire_bytes[0]!==8'h90 || wire_bytes[1]!==8'h3c || wire_bytes[2]!==8'h64)
            $fatal(1,"want-to-send bytes not on MIDI out (%0d bytes)",wire_count);
        command(8'hff);
        $display("PASS MPU intelligent subset: ACK every command, clock-to-host rate follows tempo, 94 stops it, D0 data reaches MIDI out");
        $finish;
    end
    initial begin #2000000000; $fatal(1,"timeout"); end
endmodule
