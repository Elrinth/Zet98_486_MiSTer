// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module z486_boot_probe_tb;
    parameter LOWMEM_CACHE=0;
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
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
        .cpu_speed_sel(2'b0),.*);

    reg [7:0] memory [0:1048575];
    reg [7:0] ports [0:65535];
    reg [7:0] rom [0:550911];
    reg itfen=1;
    integer phase = 0, wait_count = 0, transactions = 0, irq_count = 0, boot_count = 0;
    integer reset_alias_reads = 0;
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
                           if (transactions < 1000) $display("BOOT IO W %h %h lanes=%b EIP=%h",held_addr,held_data,held_select,dut.cpu.eip);
                           if (held_addr==20'h0043c && held_select[1]) begin
                               if(held_data[15:8]==8'h12) itfen=0;
                               if(held_data[15:8]==8'h10) itfen=1;
                           end
                       end
                       bus_readdata = {ports[held_addr[15:0]+16'd1], ports[held_addr[15:0]]};
                   end else begin
                       if (held_write) begin
                           if (held_select[0]) memory[held_addr] = held_data[7:0];
                           if (held_select[1]) memory[held_addr+20'd1] = held_data[15:8];
                       end else if (held_addr == 20'hffff0) boot_count = boot_count + 1;
                       if (!held_write && dut.physical_address[31:20] != 0)
                           reset_alias_reads = reset_alias_reads + 1;
                       if(itfen && held_addr>=20'hf8000)
                           bus_readdata={rom[held_addr-20'hf8000+20'h18001],rom[held_addr-20'hf8000+20'h18000]};
                       else if(held_addr>=20'he8000)
                           bus_readdata={rom[held_addr-20'he8000+1],rom[held_addr-20'he8000]};
                       else bus_readdata = {memory[held_addr+20'd1], memory[held_addr]};
                       if(transactions<80) $display("BOOT MEM %b %h %h EIP=%h",held_write,held_addr,bus_readdata,dut.cpu.eip);
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
        for (i = 0; i < 1048576; i = i + 1) memory[i] = 0;
        for (i = 0; i < 65536; i = i + 1) ports[i] = 8'hff;
        if (!$value$plusargs("bootrom=%s", program_path)) $fatal(1,"missing owner boot ROM");
        fd=$fopen(program_path,"rb");
        if(!fd) $fatal(1,"cannot open owner boot ROM");
        loaded=$fread(rom,fd); $fclose(fd);
        if(loaded!=550912) $fatal(1,"expected 550912 byte boot ROM");
        repeat (5) @(posedge clk);
        @(negedge clk); reset = 0;
    end
    always @(posedge clk) if(dut.cpu.triple_fault) $display("BOOT TRIPLE FAULT EIP=%h",dut.cpu.eip);
    initial begin
        #100000000;
        $display("BOOT PROBE END: transfers=%0d boots=%0d IRQs=%0d PC=%h", transactions, boot_count,
               irq_count, dut.cpu.eip);
        $finish;
    end
endmodule
