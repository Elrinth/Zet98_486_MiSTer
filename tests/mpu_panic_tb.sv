`timescale 1ns/1ps
module mpu_panic_tb;
parameter CLOCK_MHZ=90;
localparam TICKS=CLOCK_MHZ*1000000/31250;
reg clk=0; always #(500.0/CLOCK_MHZ) clk=~clk;
reg reset=1,enable=1;
reg [15:0] io_address=0,io_writedata=0;
reg [1:0] io_select=1;
reg io_read=0,io_write=0,midi_rx=1;
wire [7:0] io_readdata;
wire io_oe,irq,midi_tx,rx_overrun,rx_framing_error,tx_overrun;
pc98_mpu_uart #(.CLOCK_HZ(CLOCK_MHZ*1000000),.RESET_PANIC(1)) dut(.*);
reg [7:0] expected[0:4095]; integer queued=0,received=0;
task add(input [7:0] b); expected[queued]=b;queued++;endtask
task panic;
 add(8'hf7);
 for(integer c=0;c<16;c++) begin
  add(8'hb0+c);add(64);add(0);
  add(8'hb0+c);add(120);add(0);
  add(8'hb0+c);add(123);add(0);
  add(8'hb0+c);add(121);add(0);
 end
endtask
always begin : decoder
 reg [7:0] b;
 @(negedge midi_tx);#16000;
 if(midi_tx!==0)$fatal(1,"panic start framing");
 for(integer n=0;n<8;n++)begin #32000;b[n]=midi_tx;end
 #32000;if(midi_tx!==1)$fatal(1,"panic stop framing");
 if(received>=queued || b!==expected[received])$fatal(1,"panic wire byte %0d got %02x wanted %02x",received,b,expected[received]);
 received++;
end
task wr(input [15:0] port,input [7:0] b);
 @(negedge clk);io_address=port;io_writedata=b;io_write=1;
 repeat(20)@(negedge clk);io_write=0;repeat(3)@(negedge clk);
endtask
task init_uart;
 wr(16'he0d2,8'h3f);
 @(negedge clk);io_address=16'he0d0;io_read=1;
 repeat(4)@(negedge clk);
 if(io_readdata!==8'hfe)$fatal(1,"missing UART ACK");
 io_read=0;repeat(3)@(negedge clk);
endtask
task drain;
 wait(received==queued);#64000;
 if(tx_overrun)$fatal(1,"panic test overflow");
endtask
initial begin
 panic();repeat(5)@(negedge clk);reset=0;drain();
 init_uart();add(8'hf0);wr(16'he0d0,8'hf0);drain();
 // Reset during a byte; drop a queued byte and terminate the old SysEx.
 add(8'h55);wr(16'he0d0,8'h55);wait(!midi_tx);
 repeat(TICKS*2)@(negedge clk);wr(16'he0d0,8'h66);
 panic();wr(16'he0d2,8'hff);
 if(irq)$fatal(1,"UART reset falsely acknowledged");
 drain();init_uart();
 // Game traffic immediately following reset must follow the complete panic.
 panic();wr(16'he0d2,8'hff);init_uart();
 add(8'h90);add(60);add(100);
 wr(16'he0d0,8'h90);wr(16'he0d0,60);wr(16'he0d0,100);drain();
 // Held reset sends once and preserves an in-flight byte.
 add(8'h80);wr(16'he0d0,8'h80);wait(!midi_tx);
 repeat(TICKS*2)@(negedge clk);panic();reset=1;
 #5000000;reset=0;drain();init_uart();
 // Disabling still emits panic, but never bus or IRQ responses.
 panic();@(negedge clk);enable=0;drain();
 if(irq||io_oe)$fatal(1,"disabled MPU bus/IRQ");
 panic();enable=1;drain();
 if(!midi_tx)$fatal(1,"not idle");
 $display("PASS MIDI panic %0dMHz: %0d wire bytes, all16 channels, midbyte reset, SysEx, discard, held reset, disable, ordering",CLOCK_MHZ,received);$finish;
end
initial begin #600000000;$fatal(1,"panic watchdog %0d/%0d",received,queued);end
endmodule
