`timescale 1ns/1ps
module decode_regs_tb;
    reg clk=0, rst_n=0, dec_reset=0, consume_enabled=0;
    reg [3:0] fetch_valid=0,prefix_count=0,consume_count=0;
    reg [63:0] fetch=0;
    wire [3:0] accepted,reference_accepted,count,reference_count;
    wire [95:0] data,reference_data;
    always #5 clk=~clk;
    decode_regs dut(clk,rst_n,dec_reset,fetch_valid,fetch,prefix_count,consume_count,consume_enabled,accepted,data,count);
    decode_regs_legacy reference(clk,rst_n,dec_reset,fetch_valid,fetch,prefix_count,
        consume_enabled ? consume_count : 4'd0,reference_accepted,reference_data,reference_count);
    integer dc,cc,pc,fv,en,reset_case,n;
    reg [3:0] injected_count;
    reg [95:0] injected_data;
    task compare;
        begin
            if(accepted!==reference_accepted || count!==reference_count || data!==reference_data)
                $fatal(1,"decode buffer differs dc=%d cc=%d pc=%d fv=%d enable=%b reset=%b",injected_count,consume_count,prefix_count,fetch_valid,consume_enabled,dec_reset);
        end
    endtask
    initial begin
        repeat(2) @(negedge clk);rst_n=1;
        // Include all 4-bit count encodings, even unreachable/underflow cases.
        for(dc=0;dc<16;dc=dc+1)
        for(cc=0;cc<16;cc=cc+1)
        for(pc=0;pc<16;pc=pc+1)
        for(fv=0;fv<16;fv=fv+1)
        for(en=0;en<2;en=en+1)
        for(reset_case=0;reset_case<2;reset_case=reset_case+1) begin
            @(negedge clk);
            injected_count=dc;injected_data={$random,$random,$random};
            force dut.decoder_count=injected_count;force reference.decoder_count=injected_count;
            force dut.decoder=injected_data;force reference.decoder=injected_data;
            consume_count=cc;prefix_count=pc;fetch_valid=fv;consume_enabled=en;
            fetch={$random,$random};dec_reset=reset_case;
            #1;compare();
            release dut.decoder_count;release reference.decoder_count;
            release dut.decoder;release reference.decoder;
            @(posedge clk);#1;compare();
        end
        // Exercise continuous reset/stall/consume/refill history as well.
        for(n=0;n<10000;n=n+1) begin
            @(negedge clk);
            rst_n=(n%197!=0);dec_reset=(n%71==0);
            consume_count=$random;prefix_count=$random;fetch_valid=$random;
            consume_enabled=$random;fetch={$random,$random};
            #1;compare();@(posedge clk);#1;compare();
        end
        $display("PASS: decode buffer bit-exact against legacy, 262144 count/consume/prefix/fetch/stall/reset combinations plus 10000 sequential cycles");$finish;
    end
endmodule
