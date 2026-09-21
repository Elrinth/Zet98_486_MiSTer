// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module ao486_cache_tb;
    parameter ICACHE_ENABLE = 1;
    parameter LOWMEM_CACHE = 0;
    parameter INVALIDATION_CONNECTED = 1;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg invalidate = 0;
    wire cache_invalidate = invalidate && INVALIDATION_CONNECTED;
    wire interrupt_do = 0;
    wire [7:0] interrupt_vector = 0;
    wire interrupt_done;
    wire [19:1] bus_address;
    wire [1:0] bus_select;
    wire [15:0] bus_writedata;
    wire bus_write, bus_strobe, bus_io, unmapped_access;
    reg [15:0] bus_readdata = 0;
    reg bus_ack = 0;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable, ddr_burstcount;
    wire ddr_read, ddr_write;
    wire ddr_busy=0, ddr_readdatavalid=0;
    wire [63:0] ddr_readdata=0;
    pc98_ao486 #(.ICACHE_ENABLE(ICACHE_ENABLE),.LOWMEM_CACHE(LOWMEM_CACHE)) dut (.*);
    reg [7:0] memory [0:1048575];
    integer cycles = 0, transactions = 0, phase = 0, delay_left = 0;
    integer memory_wait = 8, dma_left = 0, dma_tests = 0;
    integer start_cycles, start_transfers, measurements = 0;
    reg [19:0] held_addr;
    reg [15:0] held_data;
    reg [1:0] held_select;
    reg held_write, held_io;
    integer j;
    always @(negedge clk) begin
        cycles = cycles + 1;
        if (dma_left != 0) begin
            dma_left = dma_left - 1;
            // A later byte in the same ownership interval replaces a warmed
            // instruction. No per-byte invalidation queue may overflow.
            memory[20'h2001] = dma_left == 0 ? 8'h22 : 8'hee;
            memory[20'h2002] = dma_left == 0 ? 8'h22 : 8'hee;
            if (dma_left == 0) invalidate = 0;
        end else if (reset) begin phase = 0; bus_ack = 0; end
        else case (phase)
            0: if (bus_strobe) begin
                held_addr = {bus_address, 1'b0};
                held_data = bus_writedata; held_select = bus_select;
                held_write = bus_write; held_io = bus_io;
                delay_left = bus_io ? 1 : memory_wait;
                phase = 1;
            end
            1: if (!bus_strobe || {bus_address, 1'b0} !== held_addr ||
                   bus_select !== held_select || bus_io !== held_io ||
                   bus_write !== held_write || bus_writedata !== held_data)
                   $fatal(1, "Cache CPU bus changed before acknowledgement");
               else if (delay_left != 0) delay_left = delay_left - 1;
               else begin
                   if (held_io && held_write) begin
                       case (held_addr)
                           20'h07ff2: begin
                               dma_left = 300; invalidate = 1; dma_tests = dma_tests + 1;
                           end
                           20'h07ff4: begin memory[20'h80001] = 8'h55; memory[20'h80002] = 8'h55; end
                           20'h07ff0: begin
                               if (held_data[15:8] == 1) begin
                                   start_cycles = cycles; start_transfers = transactions;
                               end else if (held_data[15:8] == 2) begin
                                   measurements = measurements + 1;
                                   $display("BENCH icache=%0d lowmem_cache=%0d wait=%0d kernel=%0d cycles=%0d transfers=%0d", ICACHE_ENABLE, LOWMEM_CACHE,
                                       memory_wait, held_data[7:0], cycles-start_cycles, transactions-start_transfers);
                               end else if (held_data == 16'hdead) $fatal(1, "Cache coherence/checksum failure");
                               else if (held_data == 16'h600d) begin
                                   if (dma_tests != 1 || measurements != 2) $fatal(1, "Missing cache checks");
                                   for (j=0; j<256; j=j+2)
                                       if ({memory[20'ha8000+j+1],memory[20'ha8000+j]} !== 16'ha55a)
                                           $fatal(1, "VRAM copy corrupted at %h", j);
                                   $display("PASS: full CPU cache=%0d: DMA modification, CPU self-modification, upper-window bypass, ALU and VRAM checksums", ICACHE_ENABLE);
                                   $finish;
                               end
                           end
                           default: $fatal(1, "Unexpected port %h", held_addr);
                       endcase
                   end else if (!held_io) begin
                       if (held_write) begin
                           if (held_select[0]) memory[held_addr] = held_data[7:0];
                           if (held_select[1]) memory[held_addr+20'd1] = held_data[15:8];
                       end
                       bus_readdata = {memory[held_addr+20'd1], memory[held_addr]};
                   end
                   bus_ack = 1; phase = 2; transactions = transactions + 1;
               end
            2: if (!bus_strobe) begin phase = 3; delay_left = 1; end
            3: if (delay_left != 0) delay_left = delay_left - 1;
               else begin phase = 0; bus_ack = 0; end
        endcase
    end
    string program_path;
    integer i, fd, loaded;
    initial begin
        if ($value$plusargs("wait=%d", memory_wait)) begin end
        for (i = 0; i < 1048576; i = i + 1) memory[i] = 0;
        if (!$value$plusargs("program=%s", program_path)) $fatal(1, "missing test program");
        fd = $fopen(program_path, "rb");
        if (!fd) $fatal(1, "cannot open test program");
        loaded = $fread(memory, fd, 4096); $fclose(fd);
        if (loaded == 0) $fatal(1, "empty test program");
        memory[20'hffff0]=8'hea; memory[20'hffff1]=0; memory[20'hffff2]=8'h10;
        memory[20'hffff3]=0; memory[20'hffff4]=0;
        memory[20'h2000]=8'hb8; memory[20'h2001]=8'h11; memory[20'h2002]=8'h11; memory[20'h2003]=8'hc3;
        memory[20'h80000]=8'hb8; memory[20'h80001]=8'h33; memory[20'h80002]=8'h33; memory[20'h80003]=8'hcb;
        memory[20'h3000]=8'h5a; memory[20'h3001]=8'ha5;
        repeat (5) @(posedge clk);
        @(negedge clk); reset = 0;
    end
    initial begin
        #30000000;
        $fatal(1, "Cache watchdog: transfers=%0d PC=%h", transactions, dut.cpu.eip);
    end
endmodule
