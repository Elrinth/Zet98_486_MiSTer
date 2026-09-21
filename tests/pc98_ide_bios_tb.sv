// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module pc98_ide_bios_tb;
    parameter LOWMEM_CACHE=0;
    parameter EXPECT_READS=7;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg cache_invalidate = 0;
    reg interrupt_do = 0;
    wire interrupt_done;
    wire [7:0] interrupt_vector = interrupt_done ? 8'h80 : 8'h07;
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
    pc98_ao486 #(.LOWMEM_CACHE(LOWMEM_CACHE)) dut (.*);

    reg [7:0] memory [0:1048575];
    reg [7:0] ports [0:65535];
    integer phase = 0, wait_count = 0, transactions = 0, irq_count = 0, boot_count = 0;
    integer reset_alias_reads = 0;
    reg [19:0] held_addr;
    reg [15:0] held_data;
    reg [1:0] held_select;
    reg held_write, held_io;
    integer ide_index=0, ide_delay=0, ide_fault=0, ide_reads=0;
    reg [27:0] ide_lba=0;
    reg [7:0] ide_status=8'h50;
    always @(negedge clk) begin
        if (reset) begin phase = 0; bus_ack = 0; end
        else case (phase)
            0: if (bus_strobe) begin
                held_addr = {bus_address, 1'b0};
                held_data = bus_writedata; held_select = bus_select;
                held_write = bus_write; held_io = bus_io;
                wait_count = transactions % 4;
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
                           if (held_select[0]) ports[held_addr[15:0]] = held_data[7:0];
                           if (held_select[1]) ports[held_addr[15:0]+16'd1] = held_data[15:8];
                           if (held_addr == 20'h07ff2) begin
                               ide_fault=held_data;
                               ide_status=ide_fault==1 ? 0 : ide_fault==2 ? 8'h80 : 8'h50;
                           end
                           if (held_addr == 20'h0064e) begin
                               if (held_data[7:0]!=8'h20) $fatal(1,"Read-only BIOS issued non-read command %h",held_data);
                               if (ports[16'h644]!=1) $fatal(1,"Expected single-sector PIO");
                               ide_lba={ports[16'h64c][3:0],ports[16'h64a],ports[16'h648],ports[16'h646]};
                               ide_index=0;ide_delay=3;ide_status=8'h80;ide_reads=ide_reads+1;
                               if(ide_reads==1 || ide_reads%32==0) $display("BIOS progress: sector %0d, LBA %0d",ide_reads,ide_lba);
                           end
                           if (held_addr == 20'h07ff0) begin
                               if (held_data == 16'hdead) $fatal(1,"BIOS test reported failure at EIP=%h",dut.cpu.eip);
                               if (held_data == 16'h600d) begin
                                   if(ide_reads!=EXPECT_READS) $fatal(1,"Unexpected sector read count: %0d",ide_reads);
                                   if(ports[16'h74c]!=0) $fatal(1,"PIO left IRQ disabled");
                                   $display("PASS actual ao486 PC-98 read BIOS: CHS/LBA, geometry, partial sector, segmented buffer, registers/DF, VERIFY, read-only/errors/chaining; %0d reads, %0d transfers",ide_reads,transactions);
                                   $finish;
                               end
                           end
                       end
                       bus_readdata = {ports[held_addr[15:0]+16'd1], ports[held_addr[15:0]]};
                       if(!held_write && (held_addr==20'h0074c || held_addr==20'h0064e)) begin
                           if(ide_delay>0) begin
                               ide_delay=ide_delay-1;
                               if(ide_delay==0) ide_status=ide_fault==3 ? 8'h51 : 8'h58;
                           end
                           bus_readdata={8'hff,ide_status};
                       end
                       if(!held_write && held_addr==20'h00640) begin
                           if(ide_status!=8'h58 || held_select!=3) $fatal(1,"Invalid ATA data read");
                           bus_readdata=16'ha55a ^ ide_lba[15:0] ^ ide_index;
                           ide_index=ide_index+1;
                           if(ide_index==256) ide_status=8'h50;
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
    integer cycles=0;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(cycles%50000==0) $display("BIOS CPU progress: cycles=%0d EIP=%h reads=%0d bus=%h",cycles,dut.cpu.eip,ide_reads,held_addr);
    end
    string program_path;
    integer i, fd, loaded;
    initial begin
        for (i = 0; i < 1048576; i = i + 1) memory[i] = 0;
        for (i = 0; i < 65536; i = i + 1) ports[i] = 8'hff;
        if (!$value$plusargs("program=%s", program_path)) $fatal(1, "missing test program");
        fd = $fopen(program_path, "rb");
        if (!fd) $fatal(1, "cannot open test program");
        loaded = $fread(memory, fd, 4096);
        $fclose(fd);
        if (loaded == 0) $fatal(1, "empty test program");
        // Near branch retains the 486 reset CS base and forces a high-address
        // ROM-alias fetch. The subsequent far branch enters normal real mode.
        memory[20'hffff0] = 8'he9; memory[20'hffff1] = 5; memory[20'hffff2] = 0;
        memory[20'hffff8] = 8'hea; memory[20'hffff9] = 0;
        memory[20'hffffa] = 8'h10; memory[20'hffffb] = 0; memory[20'hffffc] = 0;
        repeat (5) @(posedge clk);
        @(negedge clk); reset = 0;
    end
    initial begin
        #20000000;
        $fatal(1, "CPU watchdog: transfers=%0d boots=%0d IRQs=%0d PC=%h", transactions, boot_count,
               irq_count, dut.cpu.eip);
    end
endmodule
