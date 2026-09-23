`timescale 1ns/1fs
module pcm86_rates_tb;
    reg clk20=0,clk40=0,clk50=0,clk60=0,clk75=0,clk90=0,clk100=0,reset=1;
    always #25 clk20=!clk20;
    always #12.5 clk40=!clk40;
    always #10 clk50=!clk50;
    always #8.333333333 clk60=!clk60;
    always #6.666666667 clk75=!clk75;
    always #5.555555556 clk90=!clk90;
    always #5 clk100=!clk100;
    reg [15:0] address=16'ha468;
    reg write=0;
    reg [7:0] writedata=0;
    pcm86 #(.CLOCK_HZ(20000000)) slow(.clk(clk20),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    pcm86 #(.CLOCK_HZ(40000000)) fast(.clk(clk40),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    pcm86 #(.CLOCK_HZ(50000000)) faster(.clk(clk50),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    pcm86 #(.CLOCK_HZ(60000000)) fastest(.clk(clk60),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    pcm86 #(.CLOCK_HZ(75000000)) turbo75(.clk(clk75),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    pcm86 #(.CLOCK_HZ(90000000)) turbo90(.clk(clk90),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    pcm86 #(.CLOCK_HZ(100000000)) turbo100(.clk(clk100),.reset(reset),.address(address),.read(1'b0),.write(write),.writedata(writedata));
    integer ticks20=0,ticks40=0,ticks50=0,ticks60=0,ticks75=0,ticks90=0,ticks100=0,n,want;
    reg measuring=0;
    always @(posedge clk20) if(measuring && slow.sample_tick) ticks20=ticks20+1;
    always @(posedge clk40) if(measuring && fast.sample_tick) ticks40=ticks40+1;
    always @(posedge clk50) if(measuring && faster.sample_tick) ticks50=ticks50+1;
    always @(posedge clk60) if(measuring && fastest.sample_tick) ticks60=ticks60+1;
    always @(posedge clk75) if(measuring && turbo75.sample_tick) ticks75=ticks75+1;
    always @(posedge clk90) if(measuring && turbo90.sample_tick) ticks90=ticks90+1;
    always @(posedge clk100) if(measuring && turbo100.sample_tick) ticks100=ticks100+1;
    initial begin
        #211; reset=0;
        for(n=0;n<8;n=n+1) begin
            // A 20 MHz falling edge coincides with a 50 MHz rising edge.
            // Drive between edges so every instance observes the same write.
            @(negedge clk20);#1;writedata=n;write=1;
            repeat(3) @(negedge clk20);#1;write=0;
            repeat(3) @(negedge clk20);
            ticks20=0;ticks40=0;ticks50=0;ticks60=0;ticks75=0;ticks90=0;ticks100=0;measuring=1;
            #10000000;measuring=0;
            case(n)
                0:want=441;1:want=330;2:want=220;3:want=165;
                4:want=110;5:want=82;6:want=55;7:want=41;
            endcase
            if(ticks20<want || ticks20>want+1 || ticks40<want || ticks40>want+1 || ticks50<want || ticks50>want+1 || ticks60<want || ticks60>want+1 || ticks75<want || ticks75>want+1 || ticks90<want || ticks90>want+1 || ticks100<want || ticks100>want+1)
                $fatal(1,"PCM rate %0d changed with CPU clock: %0d/%0d/%0d/%0d/%0d/%0d/%0d expected %0d",n,ticks20,ticks40,ticks50,ticks60,ticks75,ticks90,ticks100,want);
        end
        $display("PASS: PCM86 all eight fractional sample rates unchanged at 20/40/50/60/75/90/100 MHz");
        $finish;
    end
endmodule
