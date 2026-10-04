// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Exercise the unmodified ao486 Avalon generator, not a hand-coded approximation.
module ao486_memory_integration_tb;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    wire rst_n = !reset;
    reg writeburst_do = 0, readburst_do = 0, readcode_do = 0;
    wire writeburst_done, readburst_done, readcode_done;
    reg [31:0] writeburst_address = 0, readburst_address = 0, readcode_address = 0;
    reg [2:0] writeburst_length = 0;
    reg [3:0] readburst_length = 0;
    reg [31:0] writeburst_data_in = 0;
    wire [95:0] readburst_data_out;
    wire [31:0] readcode_partial;
    wire [27:2] snoop_addr;
    wire [31:0] snoop_data;
    wire [3:0] snoop_be;
    wire snoop_we;
    wire [29:0] avm_address;
    wire [31:0] avm_writedata, avm_readdata;
    wire [3:0] avm_byteenable, avm_burstcount;
    wire avm_write, avm_read, avm_waitrequest, avm_readdatavalid, avm_write_done, busy;
    reg [23:0] dma_address = 0;
    reg dma_16bit = 0, dma_write = 0, dma_read = 0;
    reg [15:0] dma_writedata = 0;
    wire [15:0] dma_readdata;
    wire dma_readdatavalid, dma_waitrequest;
    avalon_mem cpu_memory (.*);

    reg io_read_do = 0, io_write_do = 0;
    reg [15:0] io_read_address = 0, io_write_address = 0;
    reg [2:0] io_read_length = 1, io_write_length = 1;
    reg [31:0] io_write_data = 0;
    wire [31:0] io_read_data;
    wire io_read_done, io_write_done, bus_io;

    wire [31:1] bus_address;
    wire [1:0] bus_select;
    wire [15:0] bus_writedata;
    wire bus_write, bus_strobe;
    reg [15:0] bus_readdata = 0;
    reg bus_ack = 0;
    ao486_bus_bridge #(.READ_MASK_ALWAYS_NONZERO(1'b1)) bridge (
        .wide_linear_enable(1'b0),.wide_backend_busy(1'b0),.wide_waitrequest(1'b1),
        .wide_readdatavalid(1'b0),.wide_readdata(32'b0),
        .wide_address(),.wide_writedata(),.wide_byteenable(),.wide_burstcount(),
        .wide_read(),.wide_write(),.*);

    reg [7:0] memory [0:65535];
    reg [7:0] expected [0:65535];
    reg [7:0] ports [0:65535];
    integer phase = 0, wait_count = 0, transfers = 0, commands = 0;
    reg [15:0] held_addr;
    reg [15:0] held_data;
    reg [1:0] held_select;
    reg held_write, held_io;
    always @(negedge clk) begin
        if (reset) begin phase = 0; bus_ack = 0; end
        else case (phase)
            0: if (bus_strobe) begin
                held_addr = {bus_address[15:1], 1'b0};
                held_data = bus_writedata;
                held_select = bus_select;
                held_write = bus_write;
                held_io = bus_io;
                wait_count = (transfers % 5);
                phase = 1;
            end
            1: if (!bus_strobe || bus_io !== held_io ||
                   {bus_address[15:1], 1'b0} !== held_addr || bus_select !== held_select ||
                   bus_write !== held_write || bus_writedata !== held_data)
                   $fatal(1, "shared bus changed while stalled");
               else if (wait_count != 0) wait_count = wait_count - 1;
               else begin
                   if (held_io) begin
                       if (held_write) begin
                           if (held_select[0]) ports[held_addr] = held_data[7:0];
                           if (held_select[1]) ports[held_addr + 16'd1] = held_data[15:8];
                       end
                       bus_readdata = {ports[held_addr + 16'd1], ports[held_addr]};
                   end else begin
                     if (held_write) begin
                       if (held_select[0]) memory[held_addr] = held_data[7:0];
                       if (held_select[1]) memory[held_addr + 16'd1] = held_data[15:8];
                     end
                     bus_readdata = {memory[held_addr + 16'd1], memory[held_addr]};
                   end
                   bus_ack = 1;
                   phase = 2;
                   transfers = transfers + 1;
               end
            2: if (!bus_strobe) begin wait_count = 2; phase = 3; end
            3: if (wait_count != 0) wait_count = wait_count - 1;
               else begin bus_ack = 0; phase = 0; end
        endcase
    end

    task automatic write_bytes(input reg [31:0] a, input integer len, input reg [31:0] d);
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) expected[(a + k) & 65535] = d >> (k * 8);
            @(negedge clk);
            writeburst_address = a; writeburst_length = len; writeburst_data_in = d;
            writeburst_do = 1;
            @(posedge clk);
            while (!writeburst_done) @(posedge clk);
            @(negedge clk); writeburst_do = 0;
            commands = commands + 1;
        end
    endtask

    task automatic read_bytes(input reg [31:0] a, input integer len);
        integer k;
        begin
            @(negedge clk);
            readburst_address = a; readburst_length = len; readburst_do = 1;
            @(posedge clk);
            while (!readburst_done) @(posedge clk);
            for (k = 0; k < len; k = k + 1)
                if (readburst_data_out[k*8 +: 8] !== expected[(a+k) & 65535])
                    $fatal(1, "CPU read mismatch address %h length %0d byte %0d", a, len, k);
            @(negedge clk); readburst_do = 0;
            commands = commands + 1;
        end
    endtask

    task automatic fetch_line(input reg [31:0] a);
        integer beat, k;
        begin
            @(negedge clk);
            // Deliberately retain an unrelated unaligned data-read mask.
            // ao486 forwards this mask on code fetches; the bridge must read all bytes.
            readburst_address = 3; readburst_length = 1;
            readcode_address = a; readcode_do = 1;
            for (beat = 0; beat < 8; beat = beat + 1) begin
                @(posedge clk);
                while (!readcode_done) @(posedge clk);
                for (k = 0; k < 4; k = k + 1)
                    if (readcode_partial[k*8 +: 8] !== expected[(a+beat*4+k) & 65535])
                        $fatal(1, "CPU instruction fetch mismatch beat %0d byte %0d", beat, k);
            end
            @(negedge clk); readcode_do = 0;
            commands = commands + 1;
        end
    endtask

    task automatic dma_roundtrip(input reg [23:0] a, input bit word_mode);
        integer k;
        begin
            @(negedge clk);
            dma_address = a; dma_16bit = word_mode; dma_writedata = 16'h79b5; dma_write = 1;
            for (k = 0; k < (word_mode ? 2 : 1); k = k + 1)
                expected[(a+k) & 65535] = dma_writedata >> (k*8);
            @(posedge clk);
            while (dma_waitrequest) @(posedge clk);
            @(negedge clk); dma_write = 0; dma_read = 1;
            @(posedge clk);
            while (!dma_readdatavalid) @(posedge clk);
            if (dma_readdata !== (word_mode ? 16'h79b5 : 16'h00b5))
                $fatal(1, "ao486 DMA roundtrip mismatch");
            @(negedge clk); dma_read = 0;
            commands = commands + 2;
        end
    endtask

    task automatic concurrent_io;
        integer k;
        begin
            // ao486 reports write_done on accepting the FIRST DWORD of an
            // unaligned write. I/O must wait for its later memory command too.
            write_bytes(32'h00001003, 4, 32'h78563412);
            @(negedge clk);
            io_write_address = 16'h0189; io_write_length = 4;
            io_write_data = 32'hf1e2d3c4; io_write_do = 1;
            @(posedge clk);
            while (!(bus_strobe && bus_io)) @(posedge clk);
            for (k = 0; k < 4; k = k + 1)
                if (memory[16'h1003+k] !== expected[16'h1003+k])
                    $fatal(1, "I/O overtook a pending CPU write");
            fork
                fetch_line(32'hffffffe0);
                begin
                    @(posedge clk);
                    while (!io_write_done) @(posedge clk);
                    @(negedge clk); io_write_do = 0;
                end
            join
            if ({ports[16'h18c], ports[16'h18b], ports[16'h18a], ports[16'h189]} !== 32'hf1e2d3c4)
                $fatal(1, "I/O write corrupted by concurrent prefetch");
            @(negedge clk);
            io_read_address = 16'h0189; io_read_length = 4; io_read_do = 1;
            @(posedge clk);
            while (!(bus_strobe && bus_io)) @(posedge clk);
            fork
                read_bytes(32'h00001003, 4);
                begin
                    @(posedge clk);
                    while (!io_read_done) @(posedge clk);
                    if (io_read_data !== 32'hf1e2d3c4) $fatal(1, "I/O read corrupted by memory traffic");
                    @(negedge clk); io_read_do = 0;
                end
            join
            commands = commands + 2;
        end
    endtask

    integer i, offset, len, pass, before_transfers;
    initial begin
        for (i = 0; i < 65536; i = i + 1) begin
            memory[i] = (i * 43) ^ (i >> 8);
            expected[i] = memory[i];
            ports[i] = i ^ (i >> 8) ^ 8'h59;
        end
        repeat (3) @(posedge clk);
        @(negedge clk); reset = 0;
        // The real ao486 master must fetch a byte or aligned word in ONE
        // legacy transfer. Check counts separately from pending write traffic.
        for (offset = 0; offset < 4; offset = offset + 1) begin
            before_transfers = transfers;
            read_bytes(32'h00002000 + offset, 1);
            @(posedge clk); while (busy) @(posedge clk);
            if (transfers - before_transfers != 1)
                $fatal(1, "byte read did not omit its unused halfword");
            if (!(offset & 1)) begin
                before_transfers = transfers;
                read_bytes(32'h00002000 + offset, 2);
                @(posedge clk); while (busy) @(posedge clk);
                if (transfers - before_transfers != 1)
                    $fatal(1, "aligned word read did not omit its unused halfword");
            end
        end
        before_transfers = transfers;
        fetch_line(32'h00002000);
        @(posedge clk); while (busy) @(posedge clk);
        if (transfers - before_transfers != 16)
            $fatal(1, "instruction fetch did not retain all sixteen halfwords");
        for (pass = 0; pass < 2; pass = pass + 1) begin
            for (offset = 0; offset < 4; offset = offset + 1) begin
                for (len = 1; len <= 4; len = len + 1) begin
                    write_bytes(32'hfffefff0 + offset, len, 32'h39481726 ^ (len * 17 + pass));
                    // Request a read while an unaligned write may still be draining.
                    read_bytes(32'hfffefff0 + offset, len);
                end
                for (len = 1; len <= 8; len = len + 1)
                    read_bytes(32'hfffefff8 + offset, len);
            end
            // Code fetch may be pending while a split write is still in flight.
            write_bytes(32'hfffffff3, 4, 32'hf1e2d3c4);
            fetch_line(32'hffffffe0);
        end
        for (offset = 0; offset < 4; offset = offset + 1) begin
            dma_roundtrip(24'h10a020 + offset, 0);
            if (!(offset & 1)) dma_roundtrip(24'h10a020 + offset, 1);
        end
        concurrent_io();
        repeat (40) @(posedge clk);
        for (i = 0; i < 65536; i = i + 1)
            if (memory[i] !== expected[i]) $fatal(1, "CPU write side effect mismatch at %h", i);
        $display("PASS: ao486 avalon_mem integration: %0d commands, unaligned access, code fetch, DMA, concurrent I/O", commands);
        $finish;
    end
    initial begin #2000000; $fatal(1, "CPU memory integration watchdog timeout"); end
endmodule
