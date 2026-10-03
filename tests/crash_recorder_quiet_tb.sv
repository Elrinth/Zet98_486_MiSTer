`timescale 1ns/1ps
// z486_crash_recorder DE_QUIET: with DE_TRIGGER, DE_QUIET type 14 samples in a
// row with no other event freeze the ring, so it ends with the samples of the
// stalled CPU and keeps the events before them. An event resets the count.
module crash_recorder_quiet_tb;
    parameter integer QUIET = 4;
    reg clk = 0; always #5 clk = ~clk;
    reg [31:0] eip = 32'h0000fff0;
    reg [15:0] cs = 16'hf000;
    wire tx;
    z486_crash_recorder #(.CLOCK_HZ(1152000), .DE_TRIGGER(1), .DE_QUIET(QUIET)) dut(.clk(clk), .gate_read(1'b0),
        .gate_addr(32'h0), .cs(cs), .eip(eip), .eflags(32'h46), .pe(1'b1), .vm(1'b0), .pf_code(3'd0),
        .pf_addr(32'h0), .triple_fault(1'b0), .port_f0_write(1'b0), .port_f0_data(8'h00),
        .page_fault(1'b0), .walk_pde(32'h0), .walk_pte(32'h0), .cr3(32'h0), .a20(1'b1), .sp(16'h0),
        .mem_write(1'b0), .mem_addr(32'h0), .mem_data(32'h0), .mem_be(4'h0),
        .io_wr(1'b0), .io_rd(1'b0), .io_addr(16'h0), .io_wdata(32'h0), .io_rdata(32'h0), .tx(tx));
    reg [7:0] line[0:63]; integer n = 0, e_lines = 0, samples = 0, fars = 0; reg seen_b = 0, done = 0;
    task automatic rx_byte(output [7:0] b);
        begin
            @(negedge tx); repeat (15) @(posedge clk);
            for (integer i = 0; i < 8; i++) begin b[i] = tx; repeat (10) @(posedge clk); end
        end
    endtask
    function automatic [3:0] hv(input [7:0] c); hv = c <= "9" ? c - "0" : c - "A" + 10; endfunction
    initial forever begin : rx
        reg [7:0] b; reg [127:0] v;
        rx_byte(b);
        if (b == 8'h0a) begin
            if (n > 0 && line[0] == "B") seen_b = 1;
            if (n > 0 && line[0] == "Z" && seen_b) done = 1;
            if (n == 33 && line[0] == "E" && seen_b) begin
                v = 0; for (integer i = 1; i < 33; i++) v = {v[123:0], hv(line[i])};
                if (v >> 124) begin
                    e_lines++;
                    if ((v >> 124) == 14) samples++; else samples = 0;   // trailing run
                    if ((v >> 124) == 12) fars++;
                end
            end
            n = 0;
        end else begin line[n] = b; n++; end
    end
    initial begin
        // A far transfer every 2.5 samples: the run of samples never reaches QUIET.
        for (integer k = 0; k < 6; k++) begin
            repeat (2621440) @(posedge clk);
            @(negedge clk); cs = cs + 1'b1; eip = k;
            if (seen_b) begin $display("FAIL: froze while events kept arriving"); $fatal(1); end
        end
        @(negedge clk); cs = 16'h0028; eip = 32'hc0008fe0;   // then the CPU stops
        fork
            begin wait (done); end
            begin repeat (40000000) @(posedge clk); $display("timeout"); $fatal(1); end
        join_any
        repeat (100) @(posedge clk);
        if (samples != QUIET || fars < 7) begin
            $display("FAIL: dump has %0d samples (want %0d), %0d far transfers", samples, QUIET, fars); $fatal(1);
        end
        $display("PASS: quiet freeze after %0d samples, %0d events kept", samples, e_lines);
        $finish;
    end
endmodule
