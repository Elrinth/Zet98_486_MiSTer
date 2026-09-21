`timescale 1ns/1ps
module pc98_mpu_uart_tb;
    parameter integer CLOCK_MHZ=50;
    localparam integer CLOCK_HZ=CLOCK_MHZ*1000000;
    localparam integer TICKS=CLOCK_HZ/31250;
    reg clk=0;
    always #(500.0/CLOCK_MHZ) clk=~clk;
    reg reset=1, enable=1;
    reg [15:0] io_address=0, io_writedata=0;
    reg [1:0] io_select=1;
    reg io_read=0, io_write=0;
    wire [7:0] io_readdata;
    wire io_oe, irq, midi_tx, rx_overrun, rx_framing_error, tx_overrun;
    reg external_rx=1, loopback=0;
    wire midi_rx=loopback ? midi_tx : external_rx;
    pc98_mpu_uart #(.CLOCK_HZ(CLOCK_HZ)) dut(.*);

    reg [7:0] expected[0:511];
    integer expected_count=0, sent_count=0, checks=0;
    reg monitor=1;
    // Independent wire decoder: samples the actual MIDI line, with no access
    // to serializer counters, and checks start/stop bits and full byte order.
    always begin : wire_receiver
        reg [7:0] value;
        @(negedge midi_tx);
        if (monitor) begin
            #(16000);
            if (midi_tx !== 0) $fatal(1,"Invalid MIDI start bit");
            for(integer b=0;b<8;b=b+1) begin
                #(32000); value[b]=midi_tx;
            end
            #(32000);
            if (midi_tx !== 1) $fatal(1,"Invalid MIDI stop bit");
            if (sent_count>=expected_count || value!==expected[sent_count])
                $fatal(1,"MIDI byte %0d got %02x expected %02x (queued %0d)",
                       sent_count,value,expected[sent_count],expected_count);
            sent_count=sent_count+1;
        end
    end
    task automatic wr(input [15:0] addr,input [7:0] data,input integer hold=5);
        @(negedge clk);io_address=addr;io_writedata={8'h55,data};io_write=1;
        repeat(hold) @(negedge clk);
        io_write=0;
        repeat(2) @(negedge clk);
    endtask
    task automatic rd(input [15:0] addr,output [7:0] data,input integer hold=5);
        @(negedge clk);io_address=addr;io_read=1;
        @(negedge clk);data=io_readdata;
        if(!io_oe) $fatal(1,"Decoded MPU read did not drive the low byte");
        repeat(hold) begin
            @(negedge clk);
            if(io_readdata!==data) $fatal(1,"Read data changed during held RD");
        end
        io_read=0;
        repeat(2) @(negedge clk);
        checks=checks+1;
    endtask
    task automatic expect_read(input [15:0] addr,input [7:0] wanted);
        reg [7:0] got;
        rd(addr,got,17);
        if(got!==wanted) $fatal(1,"Port %04x got %02x expected %02x",addr,got,wanted);
    endtask
    task automatic uart_init;
        wr(16'he0d2,8'hff,29);
        if(!irq) $fatal(1,"Reset ACK did not raise IRQ6 source");
        expect_read(16'he0d2,8'h00);
        expect_read(16'he0d0,8'hfe);
        if(irq) $fatal(1,"ACK read failed to clear IRQ");
        expect_read(16'he0d2,8'h80);
        wr(16'he0d2,8'h3f,19);
        expect_read(16'he0d0,8'hfe);
        if(irq) $fatal(1,"UART ACK repeated after a held write");
    endtask
    task automatic send_checked(input [7:0] value);
        reg [7:0] status;
        rd(16'he0d2,status);
        while(status[6]) begin
            repeat(TICKS) @(negedge clk);
            rd(16'he0d2,status);
        end
        expected[expected_count]=value;expected_count=expected_count+1;
        wr(16'he0d0,value,23);
    endtask
    task automatic serial_in(input [7:0] value,input bit valid_stop=1);
        @(negedge clk);external_rx=0;
        #(32000);
        for(integer i=0;i<8;i=i+1) begin external_rx=value[i];#(32000);end
        external_rx=valid_stop;#(32000);
        external_rx=1;#(32000);
    endtask
    initial begin : run
        reg [7:0] status;
        repeat(5) @(negedge clk);reset=0;
        expect_read(16'he0d2,8'h80);
        // No odd-lane or IBM-PC alias, even on an otherwise matching address.
        io_select=2;wr(16'he0d2,8'h3f);io_select=1;
        wr(16'h0331,8'h3f);wr(16'he0d3,8'h3f);
        if(irq) $fatal(1,"Wrong port or byte lane changed MPU state");
        expect_read(16'he0d0,8'hff);
        uart_init();

        // Slow serial plus a fast CPU forces TX busy; no skipped, duplicated,
        // or reordered status/data/SysEx bytes despite extended I/O strobes.
        for(integer i=0;i<80;i=i+1) send_checked((i*73+16'h91)&255);
        wait(sent_count==expected_count);
        #(40000);
        if(tx_overrun) $fatal(1,"Obeying busy overflowed TX");
        // A command in UART mode is ignored, except FF reset.
        wr(16'he0d2,8'h3f);if(irq) $fatal(1,"UART command falsely acknowledged");

        // RX FIFO + IRQ, including a read that holds RD after consuming data.
        for(integer i=0;i<16;i=i+1) serial_in(8'h80+i);
        if(!irq) $fatal(1,"Received MIDI failed to raise IRQ");
        serial_in(8'hff);
        if(!rx_overrun) $fatal(1,"RX overflow was not recorded");
        for(integer i=0;i<16;i=i+1) expect_read(16'he0d0,8'h80+i);
        if(irq) $fatal(1,"RX FIFO did not drain/clear IRQ");
        expect_read(16'he0d0,8'hff);
        // Bad stop bit must not fabricate a byte; break recovers at idle high.
        serial_in(8'h42,0);
        if(!rx_framing_error || irq) $fatal(1,"Invalid framing accepted as data");
        serial_in(8'h5a);expect_read(16'he0d0,8'h5a);
        uart_init();
        if(rx_overrun || rx_framing_error || tx_overrun) $fatal(1,"Reset kept error flags");

        // Concurrent TX/RX traffic and FIFO pointer wrap.
        loopback=1;
        for(integer i=0;i<40;i=i+1) begin
            send_checked(8'hf0^i);
            wait(irq);expect_read(16'he0d0,8'hf0^i);
        end
        wait(sent_count==expected_count);#(40000);loopback=0;

        // Full TX must reject, not corrupt, a caller violating busy.
        for(integer i=0;i<17;i=i+1) begin
            expected[expected_count]=i;expected_count=expected_count+1;
            wr(16'he0d0,i);
        end
        rd(16'he0d2,status);
        if(!status[6]) $fatal(1,"Full TX did not advertise busy");
        wr(16'he0d0,8'ha5);
        if(!tx_overrun) $fatal(1,"TX overflow not recorded");
        wait(sent_count==expected_count);#(40000);
        uart_init();

        // Pending receive/ACK and transmit state cannot leak across disable.
        serial_in(8'h33);if(!irq) $fatal(1,"Missing test IRQ");
        @(negedge clk);enable=0;
        repeat(10) @(negedge clk);
        io_read=1;io_address=16'he0d0;
        repeat(3) @(negedge clk);
        if(io_oe || irq || !midi_tx) $fatal(1,"Disabled MPU drives bus/IRQ/TX");
        io_read=0;enable=1;
        repeat(3) @(negedge clk);
        expect_read(16'he0d2,8'h80);
        uart_init();
        $display("PASS MPU UART %0dMHz: %0d independently decoded MIDI bytes, %0d held reads, ports/lanes/ACK/IRQ/FIFO/backpressure/reset/framing",CLOCK_MHZ,sent_count,checks);
        $finish;
    end
    initial begin #(64'd200000000);$fatal(1,"MPU test timeout");end
endmodule
