// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module ao486_cpu_tb;
    parameter LOWMEM_CACHE=0;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg [1:0] cpu_speed_sel = 0;
    integer speed_option = 0;
    integer speed_cycles = 0;
    reg switch_speed = 0;
    always @(posedge clk) if (!reset && switch_speed) begin
        speed_cycles <= speed_cycles + 1;
        if (speed_cycles % 997 == 996) cpu_speed_sel <= cpu_speed_sel + 1'b1;
    end
    reg cache_invalidate = 0;
    reg interrupt_do = 0;
    wire cache_upper_ram_native = 0;
    wire interrupt_done;
    wire [7:0] interrupt_vector = interrupt_done ? 8'h80 : 8'h07;
    wire [19:1] bus_address;
    wire [1:0] bus_select;
    wire [15:0] bus_writedata;
    wire bus_write, bus_strobe, bus_io, unmapped_access;
    reg [15:0] bus_readdata = 0;
    reg bus_ack = 0;
    wire [127:0] debug_snapshot;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable, ddr_burstcount;
    wire ddr_read, ddr_write;
    wire ddr_busy=0, ddr_readdatavalid=0;
    wire [63:0] ddr_readdata=0;
    pc98_ao486 #(.LOWMEM_CACHE(LOWMEM_CACHE)) dut (
        .pegc_analog16(1'b0),.pegc_display_enable(1'b0),.pegc_gdc_5mhz(1'b0),
        .pegc_mode256(),.pegc_single_page(),.pegc_pixel_clk(clk),
        .pegc_palette_index(8'b0),.pegc_palette_rgb(),.pegc_video_address(16'b0),
        .pegc_video_burstcount(5'b0),.pegc_video_read(1'b0),.pegc_video_busy(),
        .pegc_video_readdatavalid(),.pegc_video_readdata(),
        .*);

    reg [7:0] memory [0:1048575];
    reg [7:0] ports [0:65535];
    integer phase = 0, wait_count = 0, transactions = 0, irq_count = 0, boot_count = 0;
    integer reset_alias_reads = 0;
    integer pio_mode = 0, pio_read_count = 0, pio_write_count = 0;
    reg [31:0] bus_delay_state = 0;
    reg random_bus_delays = 0;
    integer bus_wait_mask = 15;
    reg [31:0] recent_eip [0:31];
    reg [31:0] previous_eip = 32'hffffffff;
    integer recent_index = 0;
    always @(posedge clk) if (!reset && dut.cpu.eip != previous_eip) begin
        recent_eip[recent_index] <= dut.cpu.eip;
        recent_index <= (recent_index+1)%32;
        previous_eip <= dut.cpu.eip;
    end
    reg [19:0] held_addr;
    reg [15:0] held_data;
    reg [1:0] held_select;
    reg held_write, held_io;
    always @(posedge clk) if (interrupt_done) begin
        interrupt_do <= 0;
        irq_count <= irq_count + 1;
    end
    always @(negedge clk) begin
        if (reset) begin phase = 0; bus_ack = 0; end
        else case (phase)
            0: if (bus_strobe) begin
                held_addr = {bus_address, 1'b0};
                held_data = bus_writedata; held_select = bus_select;
                held_write = bus_write; held_io = bus_io;
                if (random_bus_delays) begin
                    bus_delay_state = bus_delay_state ^ (bus_delay_state << 13);
                    bus_delay_state = bus_delay_state ^ (bus_delay_state >> 17);
                    bus_delay_state = bus_delay_state ^ (bus_delay_state << 5);
                    wait_count = bus_delay_state & bus_wait_mask;
                end else wait_count = transactions % 4;
                phase = 1;
            end
            1: if (!bus_strobe || {bus_address, 1'b0} !== held_addr ||
                   bus_select !== held_select || bus_io !== held_io ||
                   bus_write !== held_write || bus_writedata !== held_data)
                   $fatal(1, "CPU bus changed before acknowledgement");
               else if (wait_count != 0) wait_count = wait_count - 1;
               else begin
                   if (held_io) begin
                       if (held_write) begin
                           if (held_addr == 20'h07ff2) begin
                               if (held_data == 1) begin
                                   pio_mode = 1; pio_read_count = 0; pio_write_count = 0;
                               end else if (held_data == 2) begin
                                   if (pio_read_count != 256) $fatal(1, "short REP INSW: %0d", pio_read_count);
                                   pio_mode = 2;
                               end else if (held_data == 3) begin
                                   if (pio_write_count != 256) $fatal(1, "short REP OUTSW: %0d", pio_write_count);
                                   pio_mode = 0;
                               end else $fatal(1, "invalid PIO test command");
                           end
                           if (held_addr == 20'h00640 && pio_mode == 2) begin
                               if (held_select != 2'b11 || pio_write_count >= 256 ||
                                   held_data != (16'ha500 ^ 16'(pio_write_count)))
                                   $fatal(1, "REP OUTSW word %0d: %h", pio_write_count, held_data);
                               pio_write_count = pio_write_count + 1;
                           end
                           if (held_select[0]) ports[held_addr[15:0]] = held_data[7:0];
                           if (held_select[1]) ports[held_addr[15:0]+16'd1] = held_data[15:8];
                           if (held_addr == 20'h07ff0) begin
                               if (held_data == 16'h0011) interrupt_do <= 1;
                               else if (held_data == 16'hdead) begin
                                   for (integer n=0;n<32;n=n+1)
                                       $display("RECENT EIP %08h",recent_eip[(recent_index+n)%32]);
                                   $fatal(1, "486 program reported failure: EIP=%h shift_stage=%0d integer_stage=%0d string_stage=%0d", dut.cpu.eip, {memory[20'h27f1],memory[20'h27f0]}, {memory[20'h27d1],memory[20'h27d0]}, {memory[20'h27c1],memory[20'h27c0]});
                               end
                               else if (held_data == 16'h600d) begin
`ifdef ZET98_Z486
                                   if (pio_read_count != 256 || pio_write_count != 256 || pio_mode != 0)
                                       $fatal(1, "PIO regression did not complete");
                                   $display("PASS: disk-style REP INSW/OUTSW, 256 exact ordered words, upper RAM and 16-bit index/count wrap");
                                   if ({memory[20'h27e1],memory[20'h27e0]} != 16'd1 ||
                                       memory[20'h27e2] != 8'd0)
                                       $fatal(1, "FLAGS single-step regression did not complete");
                                   $display("PASS: FLAGS/POPFD/SAHF restoration and exact single-step return/IRET");
                                   if ({memory[20'h27d1],memory[20'h27d0]} != 16'd6)
                                       $fatal(1, "Integer and elapsed-time regression did not complete");
                                   $display("PASS: MUL/IMUL/DIV/IDIV, exact clock conversion and elapsed-time carry/borrow/hour wrap");
                                   if ({memory[20'h27c1],memory[20'h27c0]} != 16'd25)
                                       $fatal(1, "REP fill/compare diagnostic did not finish");
                                   $display("PASS: cached/uncached REP STOSW/SCASW, flags across indirect JMP, 16-bit wrap and mismatch termination");
`endif
                                   if (irq_count != 1 || boot_count < 2 || reset_alias_reads == 0)
                                       $fatal(1, "missing IRQ or software reset: %0d/%0d", irq_count, boot_count);
                                   $display("PASS: full ao486 CPU: BSWAP, DWORD memory/I/O, REP MOVSD, A20, interrupt/IRET, CPU reset; %0d bus transfers", transactions);
                                   $finish;
                               end
                           end
                       end
                       bus_readdata = {ports[held_addr[15:0]+16'd1], ports[held_addr[15:0]]};
                       if (!held_write && held_addr == 20'h00640 && pio_mode == 1) begin
                           if (held_select != 2'b11 || pio_read_count >= 256)
                               $fatal(1, "invalid REP INSW transfer");
                           bus_readdata = 16'ha500 ^ 16'(pio_read_count);
                           pio_read_count = pio_read_count + 1;
                       end
                   end else begin
                       if (held_write) begin
                           if (held_select[0]) memory[held_addr] = held_data[7:0];
                           if (held_select[1]) memory[held_addr+20'd1] = held_data[15:8];
                       end else if (held_addr == 20'hffff0) boot_count = boot_count + 1;
                       if (!held_write && dut.physical_address[31:20] != 0)
                           reset_alias_reads = reset_alias_reads + 1;
                       bus_readdata = {memory[held_addr+20'd1], memory[held_addr]};
                   end
                   bus_ack = 1; phase = 2; transactions = transactions + 1;
               end
            2: if (!bus_strobe) begin phase = 3; wait_count = 2; end
            3: if (wait_count != 0) wait_count = wait_count - 1;
               else begin phase = 0; bus_ack = 0; end
        endcase
    end
    string program_path;
    integer i, fd, loaded;
    initial begin
        if ($value$plusargs("speed=%d", speed_option)) cpu_speed_sel = speed_option[1:0];
        switch_speed = $test$plusargs("switch_speed");
        if ($value$plusargs("bus_wait_mask=%d", bus_wait_mask)) begin
            if (bus_wait_mask < 1 || bus_wait_mask > 65535) $fatal(1, "Invalid bus wait mask");
        end
        $display("CPU speed option=%0d switching=%0d", cpu_speed_sel, switch_speed);
        if ($value$plusargs("bus_seed=%d", bus_delay_state)) begin
            if (bus_delay_state == 0) $fatal(1, "Random bus seed must be nonzero");
            random_bus_delays = 1;
            $display("Random bus stalls enabled, seed=%0d, wait mask=%0d cycles", bus_delay_state, bus_wait_mask);
        end
        for (i = 0; i < 1048576; i = i + 1) memory[i] = 0;
`ifdef ZET98_Z486
        // Private-firmware-free checksum fixture in the uncached ROM aperture.
        // Each byte lane sums to zero modulo 256 over the 512 words.
        for (i = 0; i < 512; i = i + 1) begin
            memory[20'hf8000 + 2*i] = 8'(i * 17);
            memory[20'hf8001 + 2*i] = 8'(i * 29 + 7);
        end
`endif
        for (i = 0; i < 65536; i = i + 1) ports[i] = 8'hff;
        if (!$value$plusargs("program=%s", program_path)) $fatal(1, "missing test program");
        fd = $fopen(program_path, "rb");
        if (!fd) $fatal(1, "cannot open test program");
        loaded = $fread(memory, fd, 4096);
        $fclose(fd);
        if (loaded == 0) $fatal(1, "empty test program");
        if (loaded > 4096) $fatal(1, "test program overlaps scratch memory");
        // Near branch retains the 486 reset CS base and forces a high-address
        // ROM-alias fetch. The subsequent far branch enters normal real mode.
        memory[20'hffff0] = 8'he9; memory[20'hffff1] = 5; memory[20'hffff2] = 0;
        memory[20'hffff8] = 8'hea; memory[20'hffff9] = 0;
        memory[20'hffffa] = 8'h10; memory[20'hffffb] = 0; memory[20'hffffc] = 0;
        repeat (5) @(posedge clk);
        @(negedge clk); reset = 0;
    end
    integer watchdog_ms = 100;
    initial begin
        if ($value$plusargs("watchdog_ms=%d", watchdog_ms)) begin
            if (watchdog_ms < 1 || watchdog_ms > 2000) $fatal(1, "Invalid watchdog limit");
        end
        #(64'(watchdog_ms) * 1000000);
        $fatal(1, "CPU watchdog: transfers=%0d boots=%0d IRQs=%0d PC=%h", transactions, boot_count,
               irq_count, dut.cpu.eip);
    end
endmodule
