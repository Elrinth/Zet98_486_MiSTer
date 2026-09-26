// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module ao486_upper_cache_tb;
    parameter UPPER_RAM_ICACHE = 1;
    parameter SKIP_INVALIDATION = 0;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1, dma_active = 0;
    reg [7:0] bank89 = 8'h08, bankab = 8'h0a;
    wire policy_invalidate, cache_upper_ram_native;
    wire [19:1] bus_address;
    wire [1:0] bus_select;
    wire [15:0] bus_writedata;
    wire bus_write, bus_strobe, bus_io, unmapped_access;
    wire io_write = bus_write && bus_strobe && bus_io;
    wire alias_write = bus_write && bus_strobe && !bus_io && bus_address[19:17] == 3'b101;
    wire cache_invalidate = policy_invalidate &&
        !(SKIP_INVALIDATION == 1 && alias_write) &&
        !(SKIP_INVALIDATION == 2 && dma_active) &&
        !(SKIP_INVALIDATION == 3 && io_write);
    pc98_cache_policy policy (
        .dma_active(dma_active), .load_active(1'b0), .cpu_address(bus_address),
        .cpu_write(bus_write), .cpu_strobe(bus_strobe), .cpu_io(bus_io),
        .odd_io_address({bus_address[15:1], bus_select[1]}), .io_write(io_write),
        .bank89(bank89), .bankab(bankab), .invalidate(policy_invalidate),
        .upper_ram_native(cache_upper_ram_native));
    wire interrupt_do = 0;
    wire [7:0] interrupt_vector = 0;
    wire interrupt_done;
    reg [15:0] bus_readdata = 0;
    reg bus_ack = 0;
    wire [127:0] debug_snapshot;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable, ddr_burstcount;
    wire ddr_read, ddr_write;
    wire ddr_busy=0, ddr_readdatavalid=0;
    wire [63:0] ddr_readdata=0;
`ifdef ZET98_Z486
    localparam LOWMEM_CACHE = 0;
`else
    localparam LOWMEM_CACHE = 1;
`endif
    pc98_ao486 #(.LOWMEM_CACHE(LOWMEM_CACHE), .UPPER_RAM_ICACHE(UPPER_RAM_ICACHE)) dut (
        .pegc_analog16(1'b0),.pegc_display_enable(1'b0),.pegc_gdc_5mhz(1'b0),
        .pegc_mode256(),.pegc_single_page(),.pegc_pixel_clk(clk),
        .pegc_palette_index(8'b0),.pegc_palette_rgb(),.pegc_video_address(16'b0),
        .pegc_video_burstcount(5'b0),.pegc_video_read(1'b0),.pegc_video_busy(),
        .pegc_video_readdatavalid(),.pegc_video_readdata(),
        .cpu_speed_sel(2'b0),.*);
    reg [7:0] memory [0:1048575];
    integer cycles = 0, transactions = 0, phase = 0, delay_left = 0;
    integer dma_left = 0, dma_tests = 0, bank_writes = 0;
    integer start_cycles, start_fetches, measurements = 0, upper_fetches = 0;
    reg [19:0] held_addr, mapped_addr;
    reg [15:0] held_data;
    reg [1:0] held_select;
    reg held_write, held_io;
    // Independent test RAM model: 128 KB windows selected by the bank number.
    // Exhaustive peripheral mapping/eligibility is tested against memorymap.vhd
    // by run-cache-map.sh; this model tests temporal CPU/cache coherence.
    function [19:0] physical_address(input [19:0] addr);
        if (addr[19:17] == 3'b100) physical_address = {bank89[3:1], addr[16:0]};
        else if (addr[19:17] == 3'b101) physical_address = {bankab[3:1], addr[16:0]};
        else physical_address = addr;
    endfunction
    always @(negedge clk) begin
        cycles = cycles + 1;
        if (dma_left != 0) begin
            dma_left = dma_left - 1;
            memory[20'h90001] = dma_left == 0 ? 8'h44 : 8'hee;
            memory[20'h90002] = dma_left == 0 ? 8'h44 : 8'hee;
            if (dma_left == 0) dma_active = 0;
        end else if (reset) begin phase = 0; bus_ack = 0; end
        else case (phase)
            0: if (bus_strobe) begin
                held_addr = {bus_address, 1'b0};
                held_data = bus_writedata; held_select = bus_select;
                held_write = bus_write; held_io = bus_io;
                delay_left = bus_io ? 1 : 8;
                phase = 1;
            end
            1: if (!bus_strobe || {bus_address, 1'b0} !== held_addr ||
                   bus_select !== held_select || bus_io !== held_io ||
                   bus_write !== held_write || bus_writedata !== held_data)
                   $fatal(1, "CPU bus changed before acknowledgement");
               else if (delay_left != 0) delay_left = delay_left - 1;
               else begin
                   if (held_io && held_write) begin
                       case (held_addr)
                           20'h00460, 20'h00462: begin
                               if (held_select != 2'b10) $fatal(1, "Wrong PC-98 odd I/O byte lane");
                               if (held_addr == 20'h00460) bank89 = held_data[15:8];
                               else bankab = held_data[15:8];
                               bank_writes = bank_writes + 1;
                           end
                           20'h07ff2: begin
                               dma_left = 300; dma_active = 1; dma_tests = dma_tests + 1;
                           end
                           20'h07ff4: begin memory[20'he0001] = 8'h66; memory[20'he0002] = 8'h66; end
                           20'h07ff0: begin
                               if (held_data == 16'h0101) begin
                                   start_cycles = cycles; start_fetches = upper_fetches;
                               end else if (held_data == 16'h0201) begin
                                   measurements = measurements + 1;
                                   $display("BENCH upper=%0d cycles=%0d upper_fetches=%0d", UPPER_RAM_ICACHE,
                                       cycles-start_cycles, upper_fetches-start_fetches);
                               end else if (held_data == 16'hdead)
                                   $fatal(1, "Upper RAM cache coherence failure PC=%h bank89=%h bankab=%h", dut.cpu.eip, bank89, bankab);
                               else if (held_data == 16'h600d) begin
                                   if (dma_tests != 1 || measurements != 1 || bank_writes != 3)
                                       $fatal(1, "Missing upper-cache checks");
                                   $display("PASS: full CPU upper=%0d: warm fetch, native store snoop, alias store, DMA, remap/restore, ROM bypass and loop checksum", UPPER_RAM_ICACHE);
                                   $finish;
                               end else $fatal(1, "Unexpected diagnostic word %h", held_data);
                           end
                           default: $fatal(1, "Unexpected port %h", held_addr);
                       endcase
                   end else if (!held_io) begin
                       mapped_addr = physical_address(held_addr);
                       if (held_write) begin
                           if (held_select[0]) memory[mapped_addr] = held_data[7:0];
                           if (held_select[1]) memory[mapped_addr+20'd1] = held_data[15:8];
                       end else if (held_addr >= 20'h90000 && held_addr < 20'ha0000) upper_fetches = upper_fetches + 1;
                       bus_readdata = {memory[mapped_addr+20'd1], memory[mapped_addr]};
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
        for (i = 0; i < 1048576; i = i + 1) memory[i] = 0;
        if (!$value$plusargs("program=%s", program_path)) $fatal(1, "missing test program");
        fd = $fopen(program_path, "rb");
        if (!fd) $fatal(1, "cannot open test program");
        loaded = $fread(memory, fd, 4096); $fclose(fd);
        if (loaded == 0) $fatal(1, "empty test program");
        memory[20'hffff0]=8'hea; memory[20'hffff1]=0; memory[20'hffff2]=8'h10;
        memory[20'hffff3]=0; memory[20'hffff4]=0;
        memory[20'h10000]=8'hb8; memory[20'h10001]=8'haa; memory[20'h10002]=8'haa; memory[20'h10003]=8'hcb;
        memory[20'he0000]=8'hb8; memory[20'he0001]=8'h55; memory[20'he0002]=8'h55; memory[20'he0003]=8'hcb;
        repeat (5) @(posedge clk);
        @(negedge clk); reset = 0;
    end
    initial begin
        #15000000;
        $fatal(1, "Upper cache watchdog: transfers=%0d PC=%h", transactions, dut.cpu.eip);
    end
endmodule
