`timescale 1ns/1ps
// cpu_throttle unit test: PC-98 Full/33/8/3 MHz execution rates out of a
// 90 MHz clock, runtime selection changes (debt reset), debt_high for the
// REP restart exit, the 20-bit saturating debt, and a negative control
// (an unthrottled requester must not meet the slow targets).
module pc98_cpu_speed_tb;
reg clk=0, reset_n=0;
always #5 clk=~clk;
reg [1:0] speed_sel=0;
wire hold, release_cycle, full_speed, debt_high;
reg active_cycle=0;
cpu_throttle #(.CLOCK_RATE_MHZ(90),.PC98_MODE(1)) dut(.*);
integer count, target, highs, i, s;
initial begin
repeat(4) @(negedge clk); reset_n=1;
for(s=0;s<4;s=s+1) begin
  speed_sel=s; active_cycle=0; repeat(3) @(negedge clk);
  count=0; target=s==0 ? 90000 : s==1 ? 33000 : s==2 ? 8000 : 3000;
  for(i=0;i<90000;i=i+1) begin
    active_cycle=!hold;
    if(active_cycle) count=count+1;
    if(debt_high) $fatal(1,"debt_high while repaying every cycle at speed %0d",s);
    @(negedge clk);
  end
  if(count < target-2 || count > target+2) $fatal(1,"speed %0d count %0d wanted %0d",s,count,target);
  $display("speed %0d: %0d execution cycles per 90000 clocks", s, count);
end
// Negative control: a requester that ignores hold runs every cycle; the
// debt then grows and debt_high must assert (the REP restart condition).
speed_sel=3; active_cycle=0; repeat(3) @(negedge clk);
highs=0;
for(i=0;i<400;i=i+1) begin
  active_cycle=1; @(negedge clk);
  if(debt_high) highs=highs+1;
end
if(!hold || highs==0 || highs>400-16384/87+2) $fatal(1,"debt_high after %0d cycles (hold=%b)",400-highs,hold);
// Saturation: 20 bits at 87 per cycle saturate after ~12053 cycles.
for(i=0;i<13000;i=i+1) begin active_cycle=1; @(negedge clk); end
if(dut.debt!=20'hfffff) $fatal(1,"debt did not saturate: %h",dut.debt);
// Runtime change with debt outstanding resets the debt immediately.
active_cycle=0; speed_sel=2; @(negedge clk); @(negedge clk);
if(hold || debt_high || dut.debt!=0) $fatal(1,"speed change kept debt");
// Repayment: 100 cycles at 8 MHz then repaid at 8 per held cycle.
for(i=0;i<100;i=i+1) begin active_cycle=1; @(negedge clk); end
active_cycle=0; count=0;
while(hold) begin count=count+1; @(negedge clk); end
if(count < 100*82/8-2 || count > 100*82/8+2) $fatal(1,"repaid in %0d cycles",count);
speed_sel=0; active_cycle=1; repeat(3) @(negedge clk);
if(hold || !full_speed || debt_high) $fatal(1,"full speed does not clear throttle");
$display("PASS: CPU speed debt rate 90/33/8/3, debt_high, 20-bit saturation, runtime transitions, full speed"); $finish;
end
endmodule
