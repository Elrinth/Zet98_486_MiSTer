`timescale 1ns/1ps
// z486_crash_recorder: arms on PE, records gate reads, freezes on a triple
// fault and dumps B, 256 x E (oldest first), Z over its UART.
module crash_recorder_tb;
    reg clk = 0; always #5 clk = ~clk;
    reg gate_read = 0, pe = 0, vm = 0, triple = 0, f0 = 0;
    reg [31:0] gate_addr = 0, eip = 32'h1234, eflags = 2;
    reg [15:0] cs = 16'h0008;
    wire tx;
    // 115200 baud at 1.152 MHz: 10 clocks per bit keeps the dump short.
    z486_crash_recorder #(.CLOCK_HZ(1152000)) dut(.clk(clk), .gate_read(gate_read), .gate_addr(gate_addr),
        .cs(cs), .eip(eip), .eflags(eflags), .pe(pe), .vm(vm), .pf_code(3'd6), .pf_addr(32'h31000),
        .triple_fault(triple), .port_f0_write(f0), .port_f0_data(8'h00), .page_fault(1'b0),
        .walk_pde(32'h0), .walk_pte(32'h0), .cr3(32'h0), .a20(1'b1),
        .mem_write(1'b0), .mem_addr(32'h0), .mem_data(32'h0), .mem_be(4'h0),
        .io_wr(1'b0), .io_rd(1'b0), .io_addr(16'h0), .io_wdata(32'h0), .io_rdata(32'h0), .tx(tx));
    // UART receiver
    reg [7:0] line[0:63]; integer n = 0, lines = 0, e_lines = 0; reg seen_b = 0, done = 0;
    reg [127:0] first_e, last_e;
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
            if (line[0] == "B") seen_b = 1;
            if (line[0] == "E" && seen_b) begin
                if (n != 33) $fatal(1, "E line length %0d", n);
                v = 0; for (integer i = 1; i < 33; i++) v = {v[123:0], hv(line[i])};
                if (e_lines == 0) first_e = v; last_e = v; e_lines++;
            end
            if (line[0] == "Z" && seen_b) done = 1;
            n = 0; lines++;
        end else begin line[n] = b; n++; end
    end
    initial begin
        repeat (20) @(posedge clk);
        pe = 1; @(posedge clk);                  // arms; mode event 1
        for (integer k = 0; k < 300; k++) begin  // 300 gate reads (vector k%256), ring keeps 256 incl. the fault
            @(negedge clk); gate_read = 1; gate_addr = 32'h107e8 + 8 * (k % 256); eip = k;
            @(negedge clk); gate_read = 0;
        end
        @(negedge clk); triple = 1; @(negedge clk); triple = 0;
        @(negedge clk); gate_read = 1; gate_addr = 32'h99990; @(negedge clk); gate_read = 0;  // after freeze: ignored
        wait (done);
        if (e_lines != 256) $fatal(1, "E lines %0d", e_lines);
        if (last_e[127:124] !== 4'd3) $fatal(1, "newest entry not the triple fault: %h", last_e);
        if (last_e[107:76] !== 299) $fatal(1, "triple fault EIP %h", last_e[107:76]);
        if (first_e[127:124] !== 4'd1 || first_e[107:76] !== 45) $fatal(1, "oldest entry %h", first_e);
        if (last_e[40:9] !== 32'h31000 || last_e[43:41] !== 3'd6) $fatal(1, "CR2/code %h", last_e);
        $display("PASS: crash recorder: arms on PE, 256-entry ring, freezes on triple fault, dump oldest-first, CR2/#PF code");
        $finish;
    end
    initial begin #400000000; $fatal(1, "timeout"); end
endmodule
