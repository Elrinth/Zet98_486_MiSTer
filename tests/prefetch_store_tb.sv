`timescale 1ns/1ps
`include "defines.v"

module prefetch_store_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg rst_n = 0, pr_reset = 0;
    reg incoming = 0, accept = 0, gp = 0, pf = 0;
    reg [35:0] data = 0;
    wire [4:0] used, reference_used;
    wire [67:0] result;
    wire empty;
    prefetch_fifo dut(
        .clk(clk), .rst_n(rst_n), .pr_reset(pr_reset),
        .prefetchfifo_signal_limit_do(gp), .prefetchfifo_signal_pf_do(pf),
        .prefetchfifo_write_do(incoming), .prefetchfifo_write_data(data),
        .prefetchfifo_used(used), .prefetchfifo_accept_do(accept),
        .prefetchfifo_accept_data(result), .prefetchfifo_accept_empty(empty)
    );

    // Original queue implementation, including its direct empty-queue bypass.
    wire reference_empty;
    wire [35:0] reference_q;
    wire bypass = incoming && reference_empty;
    wire visible_empty = reference_empty && !bypass;
    wire [67:0] visible_data = bypass ?
        {data[35:32], 32'b0, data[31:0]} :
        {reference_q[35:32], 32'b0, reference_q[31:0]};
    simple_fifo_mlab #(.width(36), .widthu(4)) reference_fifo(
        .clk(clk), .rst_n(rst_n), .sclr(pr_reset), .rdreq(accept),
        .wrreq((incoming && (!reference_empty || !accept)) || gp || pf),
        .store(1'b0),
        .data(gp ? {`PREFETCH_GP_FAULT, 32'b0} :
              pf ? {`PREFETCH_PF_FAULT, 32'b0} : data),
        .empty(reference_empty), .full(reference_used[4]),
        .usedw(reference_used[3:0]), .q(reference_q)
    );

    integer cycles = 0, bypasses = 0, full_stores = 0, wraps = 0;
    reg [4:0] previous_write_index = 0;
    task check;
        begin
            if (used !== reference_used || empty !== visible_empty ||
                (!empty && result !== visible_data))
                $fatal(1, "Queue mismatch cycle %0d used %0d/%0d data %h/%h",
                       cycles, used, reference_used, result, visible_data);
        end
    endtask
    task cycle(input bit w, input bit r, input bit g, input bit p,
               input bit flush, input [35:0] value);
        begin
            @(negedge clk);
            incoming = w; accept = r; gp = g; pf = p;
            pr_reset = flush; data = value;
            #2; check();
            if (bypass && accept) bypasses = bypasses + 1;
            if (used == 16 && w && !r) full_stores = full_stores + 1;
            @(posedge clk); #2;
            check(); cycles = cycles + 1;
            if (dut.prefetch_fifo_inst.wr_index < previous_write_index && !flush)
                wraps = wraps + 1;
            previous_write_index = dut.prefetch_fifo_inst.wr_index;
        end
    endtask

    integer i, kind;
    reg [31:0] rng = 32'h18219648;
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        // Bypassed data must not enter the queue or add a CPU cycle.
        for (i = 0; i < 32; i = i + 1) cycle(1, 1, 0, 0, 0, i);
        // A store rejected at full must not overwrite the live head; then
        // simultaneous enqueue/dequeue at full must retain FIFO ordering.
        for (i = 0; i < 16; i = i + 1) cycle(1, 0, 0, 0, 0, i + 100);
        repeat (8) cycle(1, 0, 0, 0, 0, 36'h4deadbeef);
        for (i = 0; i < 100; i = i + 1) cycle(1, 1, 0, 0, 0, i + 200);
        repeat (16) cycle(0, 1, 0, 0, 0, 0);
        // Fault markers, resets with pending stores, pointer wrap and stalls.
        for (i = 0; i < 10000; i = i + 1) begin
            rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5);
            kind = rng[3:0];
            cycle(kind < 10, rng[8], kind == 10, kind == 11,
                  rng[17:9] == 0, {4'd4, rng});
        end
        repeat (16) cycle(0, 1, 0, 0, 0, 0);
        if (bypasses < 32 || full_stores < 8 || wraps < 20)
            $fatal(1, "Coverage missing: bypass=%0d full=%0d wraps=%0d", bypasses, full_stores, wraps);
        $display("PASS: %0d equivalent prefetch cycles, %0d bypasses, %0d rejected full stores, %0d physical wraps",
                 cycles, bypasses, full_stores, wraps);
        $finish;
    end
endmodule
