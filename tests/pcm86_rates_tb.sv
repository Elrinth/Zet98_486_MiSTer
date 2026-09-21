`timescale 1ns/1ps
module pcm86_rates_tb;
    reg clk20=0,clk40=0,clk50=0,clk60=0,reset=1;
    always #25 clk20=!clk20;
    always #12.5 clk40=!clk40;
    always #10 clk50=!clk50;
    always #8.333333 clk60=!clk60;
    reg [15:0] address=16'ha468;
    reg write=0;
    reg [7:0] writedata=0;
    pcm86 #(.CLOCK_HZ(20000000)) slow(.clk(clk20),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    pcm86 #(.CLOCK_HZ(40000000)) fast(.clk(clk40),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    pcm86 #(.CLOCK_HZ(50000000)) faster(.clk(clk50),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    pcm86 #(.CLOCK_HZ(60000000)) fastest(.clk(clk60),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    integer ticks20=0,ticks40=0,ticks50=0,ticks60=0,n,want;
    reg measuring=0;
    always @(posedge clk20) if(measuring && slow.sample_tick) ticks20=ticks20+1;
    always @(posedge clk40) if(measuring && fast.sample_tick) ticks40=ticks40+1;
    always @(posedge clk50) if(measuring && faster.sample_tick) ticks50=ticks50+1;
    always @(posedge clk60) if(measuring && fastest.sample_tick) ticks60=ticks60+1;
    initial begin
        #211; reset=0;
        for(n=0;n<8;n=n+1) begin
            // A 20 MHz falling edge coincides with a 50 MHz rising edge.
            // Drive between edges so every instance observes the same write.
            @(negedge clk20);#1;writedata=n;write=1;
            repeat(3) @(negedge clk20);#1;write=0;
            repeat(3) @(negedge clk20);
            ticks20=0;ticks40=0;ticks50=0;ticks60=0;measuring=1;
            #10000000;measuring=0;
            case(n)
                0:want=441;1:want=330;2:want=220;3:want=165;
                4:want=110;5:want=82;6:want=55;7:want=41;
            endcase
            if(ticks20<want || ticks20>want+1 || ticks40<want || ticks40>want+1 || ticks50<want || ticks50>want+1 || ticks60<want || ticks60>want+1)
                $fatal(1,"PCM rate %0d changed with CPU clock: %0d/%0d/%0d/%0d expected %0d",n,ticks20,ticks40,ticks50,ticks60,want);
        end
        $display("PASS: PCM86 all eight fractional sample rates unchanged at 20/40/50/60 MHz");
        $finish;
    end
endmodule
