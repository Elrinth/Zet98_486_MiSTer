`timescale 1ps/1ps
module video_status_tb;
    parameter HALF_PERIOD=8333;
    reg clk_sys=0, HDMI_TX_VS=0, cfg_ready=1, cfg_set=0, arm_wait=0;
    wire vs_wait,cfg_done,sampled_vs;
    actual_video_status dut(.*);
    always #(HALF_PERIOD) clk_sys=~clk_sys;
    reg previous_input=0, expected_sample=0;
    always @(posedge clk_sys) begin
        expected_sample<=previous_input;
        previous_input<=HDMI_TX_VS;
    end
    always @(negedge clk_sys) begin
        if (sampled_vs!==expected_sample)
            $fatal(1,"video status bypassed synchronization");
    end
    integer phase;
    reg old_config;
    initial begin
        repeat(8) @(negedge clk_sys);
        for(phase=0;phase<24;phase=phase+1) begin
            HDMI_TX_VS=0; cfg_set=0;
            repeat(8) @(negedge clk_sys);
            old_config=cfg_done;
            cfg_set=1; arm_wait=1;
            @(negedge clk_sys);arm_wait=0;
            repeat(3) @(negedge clk_sys);
            if(!vs_wait || cfg_done!==old_config) $fatal(1,"video status completed without rising sync");
            #(1+phase*(HALF_PERIOD/12)); HDMI_TX_VS=1;
            repeat(8) @(negedge clk_sys);
            if(vs_wait || cfg_done!==cfg_set) $fatal(1,"video status did not complete at rising sync");
            // A constant-high sync must not invent another rising edge.
            arm_wait=1;
            @(negedge clk_sys);arm_wait=0;
            repeat(6) @(negedge clk_sys);
            if(!vs_wait) $fatal(1,"video status repeated rising edge");
            HDMI_TX_VS=0;
            repeat(8) @(negedge clk_sys);
            if(!vs_wait) $fatal(1,"video status treated falling sync as rising");
        end
        // Existing configuration cancellation does not wait for video.
        cfg_ready=0;cfg_set=~cfg_set;
        repeat(2) @(negedge clk_sys);
        if(cfg_done!==cfg_set) $fatal(1,"video status configuration cancellation changed");
        cfg_set=1;
        repeat(2) @(negedge clk_sys);
        if(cfg_done!==cfg_set) $fatal(1,"video status not-ready configuration behavior changed");
        $display("PASS: actual HDMI status consumers period=%0dps, 24 edge phases",2*HALF_PERIOD);
        $finish;
    end
    initial begin #100000000; $fatal(1,"video status watchdog"); end
endmodule
