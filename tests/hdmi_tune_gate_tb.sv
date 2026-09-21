`timescale 1ps/1ps
module hdmi_tune_gate_tb;
    reg vidclk=0, outclk=0, enable=0;
    reg [15:0] data=16'h853b;
    wire [15:0] raw=(data & 16'hff3f) | (vidclk ? 16'h0040:0) | (outclk ? 16'h0080:0);
    wire [15:0] gated;
    always #6667 vidclk=~vidclk;
    always #3367 outclk=~outclk;
    hdmi_tune_gate dut(enable,raw,gated);
    integer in_edges=0,out_edges=0,gated_in_edges=0,gated_out_edges=0;
    always @(posedge vidclk) in_edges=in_edges+1;
    always @(posedge outclk) out_edges=out_edges+1;
    always @(posedge gated[6]) gated_in_edges=gated_in_edges+1;
    always @(posedge gated[7]) gated_out_edges=gated_out_edges+1;
    integer phase;
    initial begin
        #50000;
        if((gated & 16'hff3f)!=0) $fatal(1,"disabled tune data not zero");
        for(phase=0;phase<40;phase=phase+1) begin
            @(posedge vidclk); #(1+phase*307);enable=1;
            repeat(3) @(posedge vidclk);#1;
            if(gated!==raw) $fatal(1,"enabled scaler suggestions not preserved");
            @(negedge vidclk);data=~data;
            #1;if(gated!==raw) $fatal(1,"enabled data changes not passed through");
            #(1+phase*131);enable=0;
            repeat(3) @(posedge vidclk);#1;
            if((gated & 16'hff3f)!=0) $fatal(1,"disabled tune data not zero");
            if(in_edges!=gated_in_edges || out_edges!=gated_out_edges)
                $fatal(1,"configuration generated or suppressed a measurement clock edge");
        end
        $display("PASS: HDMI tune data gating, 40 enable phases, both clocks preserved exactly");$finish;
    end
    initial begin #100000000;$fatal(1,"tune gate watchdog");end
endmodule
