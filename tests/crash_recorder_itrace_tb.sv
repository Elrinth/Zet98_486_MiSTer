`timescale 1ns/1ps
// z486_crash_recorder ITRACE: every issued instruction is logged as type 15
// (CS, EIP) and the ring freezes on the first issue inside the freeze window,
// so the dump ends with that instruction and the ones that led to it.
module crash_recorder_itrace_tb;
    parameter integer WPOST = 0;
    parameter WATCH = 0;   // 1: freeze on a watched store instead of the EIP window
    reg clk = 0; always #5 clk = ~clk;
    reg [31:0] insn_eip = 0; reg insn_issue = 0; reg mem_write = 0;
    reg [15:0] cs = 16'h0028;
    wire tx;
    z486_crash_recorder #(.CLOCK_HZ(1152000), .DE_TRIGGER(1), .ITRACE(1), .DE_FREEZE_CS(16'h0028),
                          .DE_FREEZE_IP(17'h14010), .DE_FREEZE_EIP_HI(16'hc0ff), .DE_STACK(24'h01b73d), .DE_MATCH(16'hc0ff), .DE_POST(WPOST)) dut(.clk(clk), .gate_read(1'b0),
        .gate_addr(32'h0), .cs(cs), .eip(32'h0), .eflags(32'h46), .pe(1'b1), .vm(1'b0), .pf_code(3'd0),
        .pf_addr(32'h0), .triple_fault(1'b0), .port_f0_write(1'b0), .port_f0_data(8'h00),
        .page_fault(1'b0), .walk_pde(32'h0), .walk_pte(32'h0), .cr3(32'h0), .a20(1'b1), .sp(16'h0),
        .mem_write(mem_write), .mem_addr(32'h01b73d44), .mem_data(32'hc0ff401c), .mem_be(4'hf),
        .io_wr(1'b0), .io_rd(1'b0), .io_addr(16'h0), .io_wdata(32'h0), .io_rdata(32'h0),
        .insn_issue(insn_issue), .insn_eip(insn_eip), .tx(tx));
    reg [7:0] line[0:63]; integer n = 0, e_lines = 0; reg seen_b = 0, done = 0; reg [127:0] last_e;
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
                if (v >> 124) begin e_lines++; last_e = v; end
            end
            n = 0;
        end else begin line[n] = b; n++; end
    end
    initial begin
        repeat (20) @(posedge clk);
        for (integer k = 0; k < 300; k++) begin
            @(negedge clk); insn_issue = 1; insn_eip = 32'hc0001000 + k;
            if (k == 299 && !WATCH) insn_eip = 32'hc0ff401e;      // the wild target
            @(negedge clk); insn_issue = 0;
            if (k == 299 && WATCH) begin mem_write = 1; @(negedge clk); mem_write = 0; end
        end
        repeat (5) begin @(negedge clk); insn_issue = 1; insn_eip = 32'hc0002000; @(negedge clk); insn_issue = 0; end
        fork
            begin wait (done); end
            begin repeat (20000000) @(posedge clk); $display("timeout"); $fatal(1); end
        join_any
        repeat (100) @(posedge clk);
        if (WATCH ? ((last_e >> 124) != (WPOST ? 15 : 13) || e_lines != 256)
                  : ((last_e >> 124) != 15 || ((last_e >> 76) & 32'hffffffff) != 32'hc0ff401e || e_lines != 256)) begin
            $display("FAIL: last entry %h, %0d entries", last_e, e_lines); $fatal(1);
        end
        $display("PASS: ITRACE freezes on the window with the last %0d issues", e_lines);
        $finish;
    end
endmodule
