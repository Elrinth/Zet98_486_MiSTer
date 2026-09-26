// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module z486_pc98_cache_tb;
    reg clk=0; always #5 clk=~clk;
    reg reset_n=0, cache_invalidate=0, cache_upper_ram=0;
    reg dreq=0, ireq=0;
    reg [31:0] daddr=0, iaddr=0;
    wire daccept, dcomplete, iaccept, icomplete;
    wire [31:0] ddata;
    wire [127:0] idata;
    wire [31:2] addr;
    wire [3:0] be;
    wire [7:0] burstcount;
    wire valid, write, io, inta;
    wire [31:0] dout;
    reg [31:0] din=0;
    reg resp_valid=0;
    integer remaining=0, gap=0, reads=0, cycles=0;
    reg [31:0] pending_address, pending_generation;
    reg [31:0] generation=32'h10000000;
    wire ready = remaining==0 && gap==0;

    memory #(.PC98_MODE(1),.PC98_EXT_RAM_MB(64)) dut (
        .clk(clk), .reset_n(reset_n), .cache_invalidate(cache_invalidate), .cache_upper_ram(cache_upper_ram), .a20_enable(1'b1),
        .device_mmio_enable(1'b0), .device_mmio_base(32'b0),
        .dcache_req_valid(dreq), .dcache_req_phys_addr_raw(daddr),
        .dcache_req_preread_offset(daddr[11:0]), .dcache_req_preread_priority(dreq),
        .dcache_req_write(1'b0), .dcache_req_be(4'hf), .dcache_req_wdata(32'b0),
        .dcache_direct_wdata(32'b0), .dcache_req_is_io(1'b0), .dcache_req_is_inta(1'b0),
        .dcache_req_is_x87(1'b0), .dcache_req_is_vga_mem(1'b0),
        .dcache_req_accepted(daccept), .dcache_req_complete(), .dcache_read_complete(dcomplete),
        .dcache_rdata(ddata), .fast_store_valid(1'b0), .fast_store_phys_addr_raw(32'b0),
        .fast_store_be(4'b0), .fast_store_wdata(32'b0), .fast_store_accepted(),
        .dcache_vipt_probe_valid(1'b0), .dcache_vipt_probe_offset(12'b0),
        .dcache_vipt_probe_ready(), .dcache_vipt_probe_accepted(),
        .dcache_vipt_probe_direct_accepted(), .dcache_vipt_resolve_valid(1'b0),
        .dcache_vipt_resolve_phys_addr_raw(32'b0), .dcache_vipt_resolve_hit(),
        .dcache_vipt_resolve_data(), .x87_req_selected(), .x87_req_accepted(1'b0),
        .x87_req_complete(1'b0), .x87_read_complete(1'b0), .x87_rdata(32'b0),
        .icache_req_valid(ireq), .icache_req_phys_addr_raw(iaddr),
        .icache_req_accepted(iaccept), .icache_req_complete(icomplete), .icache_rdata(idata),
        .snoop_addr(32'b0), .snoop_valid(1'b0), .addr(addr), .be(be), .burstcount(burstcount),
        .line_read(), .din(din), .line_din(128'b0), .dout(dout), .valid(valid), .ready(ready),
        .write(write), .io(io), .resp_valid(resp_valid), .line_resp_valid(1'b0), .inta(inta)
    );
    // Capture the generation at request acceptance. A DMA event during a fill
    // can therefore leave an old response in flight, which must be drained.
    always @(posedge clk) begin
        cycles <= cycles+1;
        resp_valid <= 0;
        if(valid && ready) begin
            if(write || io || inta || be!=15) $fatal(1,"unexpected backend command");
            pending_address <= {addr,2'b0}; pending_generation <= generation;
            remaining <= burstcount; gap <= 3; reads <= reads+1;
        end else if(gap!=0) gap<=gap-1;
        else if(remaining!=0) begin
            din <= pending_address ^ pending_generation; resp_valid <= 1;
            pending_address <= pending_address+4; remaining<=remaining-1; gap<=2;
        end
        if(cycles>30000) $fatal(1,"cache watchdog");
    end
    task automatic data_read(input [31:0] a, input [31:0] expected_generation);
        @(negedge clk); daddr=a; dreq=1;
        do @(posedge clk); while(!daccept);
        @(negedge clk); dreq=0;
        while(!dcomplete) @(negedge clk);
        if(ddata !== (a^expected_generation)) $fatal(1,"data %h got %h expected %h",a,ddata,a^expected_generation);
        @(negedge clk);
    endtask
    task automatic code_read(input [31:0] a, input [31:0] expected_generation);
        @(negedge clk); iaddr=a; ireq=1;
        do @(posedge clk); while(!iaccept);
        @(negedge clk); ireq=0;
        while(!icomplete) @(negedge clk);
        for(integer n=0;n<4;n=n+1)
            if(idata[n*32+:32] !== ((a+n*4)^expected_generation))
                $fatal(1,"code line %h word %0d got %h",a,n,idata[n*32+:32]);
        @(negedge clk);
    endtask
    task automatic invalidate(input [31:0] new_generation);
        @(negedge clk); generation=new_generation; cache_invalidate=1;
        repeat(9) @(negedge clk);
        cache_invalidate=0;
    endtask
    integer before_reads;
    initial begin
        repeat(5) @(negedge clk); reset_n=1;
        code_read(32'hfffffff0,generation);
        code_read(32'hfffffff0,generation); // uncached BIOS: all four distinct words
        data_read(32'h2000,generation);
        repeat(30) @(negedge clk);
        before_reads=reads; data_read(32'h2000,generation);
        if(reads!=before_reads) $fatal(1,"fixed RAM data did not hit cache");
        code_read(32'h3000,generation); before_reads=reads;
        code_read(32'h3000,generation);
        if(reads!=before_reads) $fatal(1,"fixed RAM code did not hit cache");
        invalidate(32'h20000000);
        data_read(32'h2000,generation); code_read(32'h3000,generation);
        // Bank/VRAM reads must see new data without a cache flush.
        data_read(32'h80000,generation); data_read(32'he0000,generation);
        @(negedge clk); generation=32'h30000000;
        data_read(32'h80000,generation); data_read(32'he0000,generation);
        code_read(32'h80000,generation);
        @(negedge clk); generation=32'h40000000;
        code_read(32'h80000,generation);
        // Only native upper RAM instructions gain caching. Data and VRAM
        // still observe each physical transaction, even with upper code on.
        @(negedge clk); cache_upper_ram=1;
        code_read(32'h8c600,generation); before_reads=reads;
        code_read(32'h8c600,generation);
        if(reads!=before_reads) $fatal(1,"upper native instructions did not hit");
        data_read(32'h8c600,generation); before_reads=reads;
        data_read(32'h8c600,generation);
        if(reads!=before_reads+1) $fatal(1,"upper data acquired a cache tag");
        code_read(32'ha0000,generation); before_reads=reads;
        code_read(32'ha0000,generation);
        if(reads!=before_reads+1) $fatal(1,"VRAM instructions acquired a cache tag");
        // A bank switch invalidates a pending upper-RAM fill as well as tags.
        fork
            code_read(32'h8c700,32'h40000000);
            begin wait(valid && ready); @(negedge clk);
                cache_upper_ram=0; invalidate(32'h41000000); end
        join
        code_read(32'h8c700,generation);
        @(negedge clk); cache_upper_ram=1;
        invalidate(32'h42000000);
        code_read(32'h8c700,generation); before_reads=reads;
        code_read(32'h8c700,generation);
        if(reads!=before_reads) $fatal(1,"restored upper RAM did not cache");
        invalidate(32'h40000000);
        // Invalidate during an outstanding instruction line and early-return data fill.
        fork
            code_read(32'h5000,32'h40000000);
            begin wait(valid && ready); @(negedge clk); invalidate(32'h50000000); end
        join
        code_read(32'h5000,generation);
        data_read(32'h6000,generation);
        invalidate(32'h60000000);
        data_read(32'h6000,generation);
        data_read(32'h01200000,generation);
        $display("PASS: z486 PC-98 RAM hits, uncached BIOS/banks/VRAM, extended RAM and DMA invalidation across pending fills");
        $finish;
    end
endmodule
