`timescale 1ns/1ps
module pc98_extmem_bridge_tb;
    reg clk=0, reset=1;
    always #5 clk=!clk;
    reg [31:1] address=0;
    reg [1:0] select=0;
    reg [15:0] writedata=0;
    reg write=0, strobe=0;
    wire mapped, mapped16, ack;
    wire [15:0] readdata;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable, ddr_burstcount;
    wire ddr_read, ddr_write;
    reg ddr_busy=0, ddr_readdatavalid=0;
    reg [63:0] ddr_readdata=0;
    pc98_extmem_bridge #(.RAM_MB(64)) dut(.*);
    pc98_extmem_bridge #(.RAM_MB(16)) map16(
        .clk(clk),.reset(reset),.address(address),.select(select),.writedata(writedata),
        .write(write),.strobe(1'b0),.mapped(mapped16),.ddr_busy(1'b0),
        .ddr_readdatavalid(1'b0),.ddr_readdata(64'b0));

    reg [28:0] keys[0:255];
    reg [63:0] words[0:255];
    integer used=0, commands=0, ticks=0, left=0, read_index=0, latency=5;
    reg [31:0] expected_address=0;
    reg [63:0] expected_data;
    reg [7:0] expected_be;
    reg expected_write;
    integer n,k,found;
    function automatic [63:0] initial_word(input reg [28:0] key);
        initial_word={key,3'b101,key^29'h1965a73,3'b010};
    endfunction
    always @(posedge clk) begin
        ticks<=ticks+1;
        ddr_busy<=(ticks%5)<2;
        ddr_readdatavalid<=0;
        if(left!=0) begin
            left<=left-1;
            if(left==1) begin
                ddr_readdata<=words[read_index];
                ddr_readdatavalid<=1;
            end
        end
        if ((ddr_read || ddr_write) && !ddr_busy) begin
            if(ddr_read && ddr_write) $fatal(1,"simultaneous DDR read/write");
            if(left!=0) $fatal(1,"new command overtook a pending DDR read");
            if(ddr_address !== ((32'h30000000+expected_address)>>3) ||
               ddr_burstcount!==1 || ddr_byteenable!==expected_be ||
               ddr_write!==expected_write)
                $fatal(1,"DDR command mapping/mask mismatch at %h",expected_address);
            if(ddr_write && ddr_writedata!==expected_data) $fatal(1,"DDR data mismatch");
            found=-1;
            for(n=0;n<used;n=n+1) if(keys[n]==ddr_address) found=n;
            if(found<0) begin
                found=used; used=used+1;
                keys[found]=ddr_address; words[found]=initial_word(ddr_address);
            end
            if(ddr_write) begin
                for(k=0;k<8;k=k+1)
                    if(ddr_byteenable[k]) words[found][k*8+:8]=ddr_writedata[k*8+:8];
            end else begin
                read_index<=found; left<=latency;
            end
            commands<=commands+1;
        end
    end
    task start(input bit wr, input reg [31:0] a, input reg [1:0] be, input reg [15:0] d);
        begin
            @(negedge clk);
            address=a[31:1]; write=wr; select=be; writedata=d; strobe=1;
            expected_address=a; expected_be=be << a[2:0];
            expected_data={4{d}}; expected_write=wr;
        end
    endtask
    task finish_request;
        begin
            @(negedge clk);
            while(!ack) @(negedge clk);
            repeat(3) begin
                @(negedge clk);
                if(!ack) $fatal(1,"ACK was not held until request release");
            end
            strobe=0;
            @(negedge clk);
            if(ack) $fatal(1,"ACK did not release");
        end
    endtask
    task check_map(input reg [31:0] a, input bit yes16, yes64);
        begin
            @(negedge clk); address=a[31:1];
            #1;
            if(mapped16!==yes16 || mapped!==yes64) $fatal(1,"bad extended RAM map at %h",a);
        end
    endtask
    integer a,be,lane,before_commands;
    reg [31:0] test_address;
    reg [63:0] reference_word;
    reg [15:0] word_value;
    initial begin
        repeat(3) @(negedge clk); reset=0;
        check_map(32'h000ffffe,0,0); check_map(32'h00100000,1,1);
        check_map(32'h00effffe,1,1); check_map(32'h00f00000,0,0);
        check_map(32'h00fffffe,0,0); check_map(32'h01000000,0,1);
        check_map(32'h03fffffe,0,1); check_map(32'h04000000,0,0);
        check_map(32'hfffffff0,0,0);
        for(a=0;a<12;a=a+1) begin
            test_address=a<6 ? 32'h00100000+a*32'h240000 : 32'h01000000+(a-6)*32'h940000;
            reference_word=initial_word((32'h30000000+test_address)>>3);
            for(lane=0;lane<4;lane=lane+1) begin
                for(be=0;be<4;be=be+1) begin
                    word_value=16'ha95c^(a*713+lane*137+be*47);
                    start(1,test_address+lane*2,be,word_value); finish_request;
                    if(be&1) reference_word[lane*16+:8]=word_value[7:0];
                    if(be&2) reference_word[lane*16+8+:8]=word_value[15:8];
                    start(0,test_address+lane*2,3,0); finish_request;
                    if(readdata!==reference_word[lane*16+:16]) $fatal(1,"extended RAM byte-write/read mismatch");
                end
            end
        end
        // A late pre-reset read must not become the next request's response.
        latency=30;
        start(0,32'h00100000,3,0);
        @(negedge clk); while(left==0) @(negedge clk);
        reset=1; strobe=0;
        repeat(3) @(negedge clk); reset=0;
        start(0,32'h02000006,3,0);
        finish_request;
        reference_word=initial_word((32'h30000000+32'h02000006)>>3);
        if(readdata!==reference_word[63:48]) $fatal(1,"stale DDR response survived reset");
        before_commands=commands;
        start(1,32'h00f00000,3,16'hdead);
        repeat(12) @(negedge clk);
        if(ack || commands!=before_commands) $fatal(1,"system aperture was written as RAM");
        strobe=0;
        $display("PASS: extended DDR RAM bridge: %0d commands, 16/64 MB boundaries, PC-98 hole, byte lanes, stalls, late reset response",commands);
        $finish;
    end
    initial begin #1000000; $fatal(1,"extended RAM watchdog"); end
endmodule
