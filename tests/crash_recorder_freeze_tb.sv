`timescale 1ns/1ps
// z486_crash_recorder DE_FREEZE_CS: with DE_TRIGGER, the first far transfer
// into DE_FREEZE_CS freezes the ring; the newest entry is that CS change
// (type 12) carrying the CS:IP it came from. Later events are ignored.
module crash_recorder_freeze_tb;
    parameter [15:0] FREEZE_CS = 16'h0de3;
    parameter [16:0] FREEZE_IP = 17'h00000;   // bit 16: freeze at CS:IP instead
    parameter [8:0] FREEZE_VECTOR = 9'h000;   // bit 8: freeze on that vector (INT 6 here)
    reg clk = 0; always #5 clk = ~clk;
    reg gate_read = 0;
    reg [31:0] gate_addr = 0, eip = 32'h0000fff0;
    reg [15:0] cs = 16'hf000;
    wire tx;
    z486_crash_recorder #(.CLOCK_HZ(1152000), .DE_TRIGGER(1), .DE_FREEZE_CS(FREEZE_CS), .DE_FREEZE_IP(FREEZE_IP), .DE_FREEZE_VECTOR(FREEZE_VECTOR)) dut(.clk(clk), .gate_read(gate_read),
        .gate_addr(gate_addr), .cs(cs), .eip(eip), .eflags(32'h2), .pe(1'b0), .vm(1'b0), .pf_code(3'd0),
        .pf_addr(32'h0), .triple_fault(1'b0), .port_f0_write(1'b0), .port_f0_data(8'h00),
        .page_fault(1'b0), .walk_pde(32'h0), .walk_pte(32'h0), .cr3(32'h0), .a20(1'b1), .sp(16'h0),
        .mem_write(1'b0), .mem_addr(32'h0), .mem_data(32'h0), .mem_be(4'h0),
        .io_wr(1'b0), .io_rd(1'b0), .io_addr(16'h0), .io_wdata(32'h0), .io_rdata(32'h0), .tx(tx));
    reg [7:0] line[0:63]; integer n = 0, e_lines = 0; reg seen_b = 0, done = 0;
    reg [127:0] last_e, far_e; integer far_n = 0;
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
                if ((v >> 124) == 12) begin far_n++; far_e = v; end
            end
            n = 0;
        end else begin line[n] = b; n++; end
    end
    initial begin
        repeat (20) @(posedge clk);             // power-on at F000:FFF0: must not freeze
        @(negedge clk); cs = 16'h1234;
        for (integer k = 1; k <= 20; k++) begin    // real-mode interrupts (vector*4)
            @(negedge clk); gate_read = 1; gate_addr = 4 * (8 + k % 8); eip = k;
            @(negedge clk); gate_read = 0;
        end
        @(negedge clk); cs = 16'h0e4b; eip = 32'h00002130;   // an ordinary far transfer
        if (FREEZE_VECTOR[8]) begin                       // #UD at 0E4B:2130
            @(negedge clk); gate_read = 1; gate_addr = 4 * 6;
            @(negedge clk); gate_read = 0;
        end
        if (FREEZE_IP[16]) begin                          // enter elsewhere, no freeze yet
            @(negedge clk); cs = 16'h0de3; eip = 32'h00005ffd;
            @(negedge clk); eip = 32'h00000100;
            @(negedge clk); gate_read = 1; gate_addr = 4 * 8;
            @(negedge clk); gate_read = 0;
            @(negedge clk); eip = 32'h0000049d;             // reaches the watched IP
        end else begin
            @(negedge clk); cs = 16'h0de3; eip = 32'h0000049d;   // the wild jump
        end
        @(negedge clk); cs = 16'h1111; eip = 32'h1;          // after freeze: ignored
        @(negedge clk); gate_read = 1; gate_addr = 4 * 9;
        @(negedge clk); gate_read = 0;
        wait (done);
        if (FREEZE_VECTOR[8]) begin
            if (last_e[127:124] !== 4'd1 || last_e[123:108] !== 16'h0e4b || last_e[107:76] !== 32'h2130 ||
                last_e[75:44] !== 32'h18)
                $fatal(1, "newest entry is not the INT 6 vector read at 0E4B:2130: %h", last_e);
            $display("PASS: crash recorder DE_FREEZE_VECTOR: freezes on the first read of vector 6, at the faulting CS:IP");
            $finish;
        end
        if (last_e[127:124] !== 4'd12 || last_e[123:108] !== 16'h0de3 || last_e[107:92] !== 16'h049d ||
            (!FREEZE_IP[16] && (far_e[75:60] !== 16'h0e4b || far_e[59:44] !== 16'h2130)))
            $fatal(1, "newest entry is not the jump into 0DE3 from 0E4B:2130: %h", last_e);
        $display("PASS: crash recorder DE_FREEZE_CS: freezes on the far transfer into the watched CS, with the CS:IP it came from");
        $finish;
    end
    initial begin #200000000; $fatal(1, "timeout"); end
endmodule
