// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module z486_icache_snoop_fill_tb;
    parameter SET_BITS=8;
    reg clk=0; always #5 clk=~clk;
    reg reset=1, cpu_valid=0;
    reg [31:0] cpu_addr=0;
    wire [127:0] cpu_line;
    wire cpu_ready,cpu_resp_valid,mem_valid;
    wire [31:0] mem_addr;
    reg [127:0] mem_line_dout=0;
    reg mem_line_resp_valid=0;
    reg patch_valid=0;
    reg [31:0] patch_addr=0,patch_data=0;
    reg automatic_response=1,changed=0;
    integer pending=0,requests=0,before_reads=0;
    integer dma=0,other_way=0;
    reg [31:0] pending_addr=0;
    localparam [31:0] A=32'h01000000+(1<<(SET_BITS+3));
    wire [31:0] B=other_way ? A+(1<<(SET_BITS+4)) : A+16;
    localparam [127:0] OLD_A={4{32'h11111111}};
    localparam [127:0] NEW_A={96'h111111111111111111111111,32'h22222222};
    localparam [127:0] DATA_B={4{32'h33333333}};

    l1_icache #(.SET_BITS(SET_BITS)) dut(
        .clk(clk),.reset(reset),.invalidate_all(1'b0),
        .cpu_addr(cpu_addr),.cpu_line(cpu_line),.cpu_valid(cpu_valid),
        .cpu_no_alloc(1'b0),.cpu_ready(cpu_ready),.cpu_resp_valid(cpu_resp_valid),
        .mem_addr(mem_addr),.mem_dout(32'b0),.mem_line_dout(mem_line_dout),
        .mem_be(),.mem_burstcount(),.mem_busy(1'b0),.mem_valid(mem_valid),
        .mem_ready(1'b1),.mem_resp_valid(1'b0),.mem_line_resp_valid(mem_line_resp_valid),
        .patch_addr(patch_addr),.patch_data(patch_data),.patch_be(4'hf),
        .patch_valid(patch_valid && !dma),.invalidate_addr(patch_addr),
        .invalidate_valid(patch_valid && dma),
        .cache_enable(1'b1)
    );
    always @(posedge clk) if(mem_valid) requests<=requests+1;
    always @(posedge clk) if(automatic_response) begin
        mem_line_resp_valid<=0;
        if(mem_valid) begin pending<=2;pending_addr<=mem_addr;end
        else if(pending!=0) begin
            pending<=pending-1;
            if(pending==1) begin
                mem_line_resp_valid<=1;
                mem_line_dout<=(pending_addr==A) ? (changed ? NEW_A : OLD_A) : DATA_B;
            end
        end
    end
    task automatic request(input [31:0] address);
        @(negedge clk);
        while(!cpu_ready) @(negedge clk);
        cpu_addr=address;cpu_valid=1;
        @(negedge clk);cpu_valid=0;
    endtask
    task automatic expect_line(input [127:0] expected);
        while(!cpu_resp_valid) @(negedge clk);
        if(cpu_line!==expected) $fatal(1,"stale instruction line: got %h expected %h",cpu_line,expected);
        @(negedge clk);
    endtask
    initial begin
        void'($value$plusargs("dma=%d",dma));
        void'($value$plusargs("other_way=%d",other_way));
        repeat(3) @(negedge clk);reset=0;
        request(A);expect_line(OLD_A);
        // Default: distinct sets, both choosing way zero. The other-way
        // control fills the same set's second way and may install both writes.
        repeat(3) @(negedge clk);
        automatic_response=0;
        request(B);
        wait(mem_valid);@(posedge clk);@(negedge clk);
        patch_valid=1;patch_addr=A;patch_data=32'h22222222;changed=1;
        @(negedge clk);
        // A's registered invalidation and B's fill need the same way RAM
        // write port. A following snoop replaces the registered A address.
        patch_addr=A+32'h100;patch_data=32'h44444444;
        mem_line_dout=DATA_B;mem_line_resp_valid=1;
        @(negedge clk);
        if(!cpu_resp_valid || cpu_line!==DATA_B) $fatal(1,"fill response lost");
        mem_line_resp_valid=0;
        automatic_response=1;
        for(integer n=0;n<4;n=n+1) begin
            patch_addr=A+32'h200+n*16;patch_data=32'h55555555;
            @(negedge clk);
        end
        patch_valid=0;
        repeat(3) @(negedge clk);
        request(A);expect_line(NEW_A);
        before_reads=requests;
        request(A);expect_line(NEW_A);
        if(requests!=before_reads) $fatal(1,"old snoop state invalidated the refreshed line");
        before_reads=requests;
        request(B);expect_line(DATA_B);
        if(other_way && requests!=before_reads) $fatal(1,"independent-way fill was unnecessarily discarded");
        before_reads=requests;
        request(B);expect_line(DATA_B);
        if(requests!=before_reads) $fatal(1,"refetched fill did not cache");
        $display("PASS: fill/snoop instruction coherence, SET_BITS=%0d DMA=%0d OTHER_WAY=%0d",SET_BITS,dma,other_way);
        $finish;
    end
    initial begin #100000; $fatal(1,"snoop/fill watchdog");end
endmodule
