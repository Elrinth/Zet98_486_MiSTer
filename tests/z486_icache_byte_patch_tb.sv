// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module z486_icache_byte_patch_tb;
    parameter SET_BITS=8;
    reg clk=0; always #5 clk=~clk;
    reg reset=1, cpu_valid=0;
    wire cpu_ready,cpu_resp_valid,mem_valid;
    wire [127:0] cpu_line;
    reg [31:0] mem_dout=0;
    reg mem_resp_valid=0,mem_line_resp_valid=0;
    reg patch_valid=0;
    reg [31:0] patch_addr=0;
    reg [3:0] patch_be=0;
    localparam [31:0] ADDRESS=32'h01005800;
    localparam [127:0] OLD_LINE=128'habcd0000_c8779911_445566bb_aa112233;
    localparam [31:0] NEW_DATA=32'h94837261;
    reg [31:0] mask32;
    reg [127:0] mask128,expected;
    integer cases=0;
    l1_icache #(.SET_BITS(SET_BITS)) dut(
        .clk(clk),.reset(reset),.invalidate_all(1'b0),
        .cpu_addr(ADDRESS),.cpu_line(cpu_line),.cpu_valid(cpu_valid),
        .cpu_no_alloc(1'b0),.cpu_ready(cpu_ready),.cpu_resp_valid(cpu_resp_valid),
        .mem_addr(),.mem_dout(mem_dout),.mem_line_dout(OLD_LINE),
        .mem_be(),.mem_burstcount(),.mem_busy(1'b0),.mem_valid(mem_valid),
        .mem_ready(1'b1),.mem_resp_valid(mem_resp_valid),
        .mem_line_resp_valid(mem_line_resp_valid),
        .patch_addr(patch_addr),.patch_data(NEW_DATA),.patch_be(patch_be),
        .patch_valid(patch_valid),.invalidate_addr(32'b0),.invalidate_valid(1'b0),
        .cache_enable(1'b1)
    );
    initial begin
        for(integer narrow=0;narrow<2;narrow++)
          for(integer phase=0;phase<3;phase++)
            for(integer word=0;word<4;word++)
              for(integer be=0;be<16;be++) begin
                @(negedge clk);
                reset=1;cpu_valid=0;patch_valid=0;
                mem_resp_valid=0;mem_line_resp_valid=0;
                repeat(3) @(negedge clk);
                reset=0;
                while(!cpu_ready) @(negedge clk);
                patch_addr=ADDRESS+word*4;patch_be=4'(be);
                // Independent shifted-mask reference, with distinct bytes
                // in every DWORD to detect a wrong source/destination lane.
                mask32={{8{patch_be[3]}},{8{patch_be[2]}},
                        {8{patch_be[1]}},{8{patch_be[0]}}};
                mask128={96'b0,mask32} << (word*32);
                expected=(OLD_LINE & ~mask128) |
                         ({96'b0,NEW_DATA & mask32} << (word*32));
                cpu_valid=1;
                @(negedge clk);cpu_valid=0;
                wait(mem_valid);@(posedge clk);@(negedge clk);
                if(phase==0) begin
                    // A queued patch, with its live/registered pulse gone
                    // before any stale external memory response arrives.
                    patch_valid=1;@(negedge clk);patch_valid=0;
                    repeat(3) @(negedge clk);
                end
                if(narrow) begin
                    for(integer beat=0;beat<3;beat++) begin
                        mem_dout=OLD_LINE[beat*32 +:32];mem_resp_valid=1;
                        @(negedge clk);
                    end
                    mem_resp_valid=0;
                end
                if(phase==1) begin
                    // Patch a previously accumulated DWORD, or register a
                    // patch just before a whole-line reply.
                    patch_valid=1;@(negedge clk);patch_valid=0;
                end
                if(phase==2) patch_valid=1; // Live patch on the final reply.
                if(narrow) begin mem_dout=OLD_LINE[127:96];mem_resp_valid=1;end
                else mem_line_resp_valid=1;
                @(negedge clk);
                if(!cpu_resp_valid || cpu_line!==expected)
                    $fatal(1,"patch mismatch sets=%0d narrow=%0d phase=%0d word=%0d be=%h got=%h expected=%h",
                           SET_BITS,narrow,phase,word,patch_be,cpu_line,expected);
                mem_resp_valid=0;mem_line_resp_valid=0;patch_valid=0;
                cases++;
              end
        $display("PASS: %0d partial-byte instruction refill cases, SET_BITS=%0d",cases,SET_BITS);
        $finish;
    end
    initial begin #20000000; $fatal(1,"byte-patch watchdog");end
endmodule
