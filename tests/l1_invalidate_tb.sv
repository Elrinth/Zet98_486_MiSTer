// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module l1_invalidate_tb;
    reg CLK = 0;
    always #5 CLK = !CLK;
    reg RESET = 1, pr_reset = 0, DISABLE = 0, INVALIDATE = 0, CPU_REQ = 0;
    reg [31:0] CPU_ADDR = 32'h1000;
    wire CPU_VALID, CPU_DONE, MEM_REQ;
    wire [31:0] CPU_DATA, MEM_ADDR;
    reg MEM_DONE = 0;
    reg [31:0] MEM_DATA = 0;
    wire [27:2] snoop_addr = 0;
    wire [31:0] snoop_data = 0;
    wire [3:0] snoop_be = 0;
    wire snoop_we = 0;
    l1_icache dut (.*);
    reg [31:0] ram [0:4095];
    integer phase = 0, beat = 0, address, bursts = 0;
    reg memory_paused = 0;
    always @(negedge CLK) begin
        MEM_DONE = 0;
        if (!memory_paused) case (phase)
            0: if (MEM_REQ) begin
                address = MEM_ADDR >> 2; beat = 0; phase = 1; bursts = bursts + 1;
            end
            1: begin
                MEM_DATA = ram[address+beat]; MEM_DONE = 1; beat = beat + 1;
                if (beat == 8) phase = 2;
            end
            2: if (!MEM_REQ) phase = 0;
        endcase
    end
    task request(input [31:0] addr);
        begin
            @(negedge CLK); CPU_ADDR = addr; CPU_REQ = 1;
            @(negedge CLK); CPU_REQ = 0;
        end
    endtask
    task collect(input [31:0] expected);
        integer count;
        begin
            count = 0;
            while (!CPU_DONE) begin
                @(negedge CLK);
                if (CPU_VALID) begin
                    if (CPU_DATA !== expected + count) $fatal(1, "Stale code %h, expected %h", CPU_DATA, expected+count);
                    count = count + 1;
                end
            end
            if (count != 4) $fatal(1, "Expected four returned code words, got %0d", count);
            @(negedge CLK);
        end
    endtask
    integer i, before_bursts;
    initial begin
        for (i=0; i<4096; i=i+1) ram[i]=32'h10000000+i;
        repeat (5) @(negedge CLK);
        RESET=0;
        wait (dut.state == 1);
        request(32'h1000); collect(32'h10000400);
        before_bursts=bursts;
        request(32'h1000); collect(32'h10000400);
        if (bursts != before_bursts) $fatal(1, "Warm code failed to hit");

        // Multiple writes while held, followed by another pulse during the
        // clear sweep. Every tag must be invalid before the queued request.
        @(negedge CLK); INVALIDATE=1; pr_reset=1;
        repeat (200) @(negedge CLK);
        for (i=0; i<8; i=i+1) ram[1024+i]=32'h20000400+i;
        INVALIDATE=0; pr_reset=0;
        wait (dut.state == 0);
        repeat (10) @(negedge CLK);
        INVALIDATE=1;
        @(negedge CLK); INVALIDATE=0;
        request(32'h1000); collect(32'h20000400);
        if (bursts != before_bursts+1) $fatal(1, "Invalidation failed to refill");

        // Invalidation during an outstanding burst must drain that burst,
        // acknowledge the aborted CPU request, and clear tags afterwards.
        request(32'h2000);
        wait (MEM_REQ);
        @(negedge CLK); memory_paused=1; INVALIDATE=1; pr_reset=1;
        repeat (80) @(negedge CLK);
        for (i=0; i<8; i=i+1) ram[2048+i]=32'h30000800+i;
        memory_paused=0;
        wait (CPU_DONE);
        @(negedge CLK); INVALIDATE=0; pr_reset=0;
        request(32'h2000); collect(32'h30000800);
        $display("PASS: L1 warm hit, held/repeated invalidation, queued request, outstanding-burst drain/refill");
        $finish;
    end
    initial begin #100000; $fatal(1, "L1 invalidation watchdog state=%0d", dut.state); end
endmodule
