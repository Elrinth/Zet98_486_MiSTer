// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module pc98_debug_uart_tb;
    reg clk=0; always #5 clk=~clk;
    reg reset=1;
    reg [127:0] snapshot=128'h0123456789abcdef_fedcba9876543210;
    wire tx;
    pc98_debug_uart #(.CLOCK_HZ(1152000),.INTERVAL_CYCLES(100)) dut(.*);
    string expected="Z0123456789ABCDEFFEDCBA9876543210\n";
    reg [7:0] got;
    initial begin
        repeat(5) @(negedge clk); reset=0;
        // Change the source during transmission: all bytes must retain one snapshot.
        repeat(40) @(negedge clk); snapshot=0;
    end
    initial begin
        for(integer c=0;c<34;c=c+1) begin
            @(negedge tx);
            repeat(15) @(negedge clk);
            for(integer bitno=0;bitno<8;bitno=bitno+1) begin
                got[bitno]=tx;
                repeat(10) @(negedge clk);
            end
            if(!tx) $fatal(1,"missing UART stop bit");
            if(got!==expected[c]) $fatal(1,"UART byte %0d: %h expected %h",c,got,expected[c]);
        end
        $display("PASS: startup UART framing, byte order and atomic snapshot");
        $finish;
    end
    initial begin #1000000; $fatal(1,"UART watchdog"); end
endmodule
