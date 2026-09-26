`timescale 1ns/1ps
module pc98_cpu_speed_tb;
reg clk=0, reset_n=0;
always #5 clk=~clk;
reg [1:0] speed_sel=0;
wire hold, release_cycle, full_speed;
reg active_cycle=0;
cpu_throttle #(.CLOCK_RATE_MHZ(90),.PC98_MODE(1)) dut(.*);
integer count, target;
initial begin
repeat(4) @(negedge clk); reset_n=1;
for(integer s=0;s<4;s=s+1) begin
speed_sel=s; active_cycle=0; repeat(3) @(negedge clk);
count=0; target=s==0 ? 90000 : s==1 ? 60000 : s==2 ? 30000 : 15000;
for(integer i=0;i<90000;i=i+1) begin
active_cycle=!hold;
if(active_cycle) count=count+1;
@(negedge clk);
end
if(count < target-2 || count > target+2) $fatal(1,"speed %d count %d wanted %d",s,count,target);
end
speed_sel=0; active_cycle=0; repeat(3) @(negedge clk);
if(hold || !full_speed) $fatal(1,"full speed does not clear throttle");
$display("PASS: CPU speed debt rate 90/60/30/15, runtime transitions, full speed"); $finish;
end
endmodule
