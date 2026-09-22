`timescale 1ps/1ps
module video_config_snapshot_tb;
    parameter SYS_HALF=8333, VIDEO_HALF=3367, PHASE=1;
    reg source_clk=0, video_clk=0, source_run=1, video_run=1;
    always #(SYS_HALF) if(source_run) source_clk=~source_clk;
    initial begin #(PHASE); forever #(VIDEO_HALF) if(video_run) video_clk=~video_clk; end
    reg [149:0] source_data=0;
    wire [149:0] video_data;
    video_config_snapshot #(150) dut(.*);
    reg [149:0] in_flight=0, expected=0, previous_held=0;
    reg previous_request=0, busy;
    integer launches=0, captures=0, changes=0;
    time launch_time=0;
    always @(posedge source_clk) begin
        busy=dut.request != dut.acknowledge_sync[1];
        #1;
        if(busy && dut.held_data !== previous_held)
            $fatal(1,"snapshot payload changed before acknowledgement");
        if(dut.request != previous_request) begin
            if(busy) $fatal(1,"snapshot request overwritten while busy");
            if(dut.held_data !== source_data) $fatal(1,"snapshot captured wrong source");
            in_flight=source_data;
            launch_time=$time;
            launches=launches+1;
        end
        previous_held=dut.held_data;
        previous_request=dut.request;
    end
    always @(posedge video_clk) begin
        if(dut.request_sync[1] != dut.acknowledge) begin
            if($time-launch_time < 2*VIDEO_HALF*2-2)
                $fatal(1,"snapshot capture before two video periods");
            expected=in_flight;
            captures=captures+1;
        end
        #2;
        if(video_data !== expected) $fatal(1,"snapshot data/order mismatch");
    end
    task change;
        begin
            @(negedge source_clk);
            source_data={$random,$random,$random,$random,$random};
            changes=changes+1;
        end
    endtask
    task settle;
        begin
            repeat(32) @(negedge source_clk);
            repeat(32) @(negedge video_clk);
            if(video_data !== source_data) $fatal(1,"snapshot lost latest update");
        end
    endtask
    initial begin
        repeat(10) @(negedge source_clk);
        repeat(200) change(); // Repeated updates must not corrupt a held word.
        settle();
        @(negedge video_clk); video_run=0;
        repeat(40) change();
        video_run=1;
        settle();
        change();
        @(negedge source_clk); source_run=0;
        repeat(40) @(negedge video_clk);
        source_run=1;
        settle();
        repeat(50) begin change(); repeat(17) @(negedge source_clk); end
        settle();
        if(launches!=captures || captures<50) $fatal(1,"snapshot count/liveness");
        $display("PASS snapshot sys=%0d video=%0d phase=%0d changes=%0d captures=%0d",
                 SYS_HALF,VIDEO_HALF,PHASE,changes,captures);
        $finish;
    end
    initial begin #1000000000; $fatal(1,"snapshot watchdog"); end
endmodule
