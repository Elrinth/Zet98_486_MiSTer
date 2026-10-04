// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Drive the CPU bus of the real router directly. The CPU is a black box here;
// run-z486-native-ddr.sh separately checks actual instructions and cache fills.
module pc98_native_router_tb;
    parameter RAM_ENABLE=1;
    reg clk=0,reset=1;
    always #5 clk=~clk;
    reg [29:0] request_address=0;
    reg [31:0] request_data=0;
    reg [3:0] request_mask=15,request_count=1;
    reg request_read=0,request_write=0,io_request=0;
    reg [15:0] io_address=0;
    reg [31:0] io_data=0;
    wire [19:1] bus_address;
    wire [1:0] bus_select;
    wire [15:0] bus_writedata;
    wire bus_write,bus_strobe,bus_io;
    wire bus_ack=bus_strobe && bus_io;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable,ddr_burstcount;
    wire ddr_read,ddr_write;
    wire ddr_busy=cycles%7<2;
    reg ddr_readdatavalid=0;
    reg [63:0] ddr_readdata=0;
    pc98_ao486 #(.EXT_RAM_MB(64),.NATIVE_DDR(1),.NATIVE_DDR_RAM(RAM_ENABLE),.PEGC_ENABLE(1)) dut (
        .clk(clk),.reset(reset),.cpu_speed_sel(2'b0),.cache_invalidate(1'b0),
        .cache_upper_ram_native(1'b0),.interrupt_do(1'b0),.interrupt_vector(8'b0),
        .bus_address(bus_address),.bus_select(bus_select),.bus_writedata(bus_writedata),
        .bus_write(bus_write),.bus_strobe(bus_strobe),.bus_io(bus_io),
        .bus_readdata(16'hffff),.bus_ack(bus_ack),
        .ddr_address(ddr_address),.ddr_writedata(ddr_writedata),
        .ddr_byteenable(ddr_byteenable),.ddr_burstcount(ddr_burstcount),
        .ddr_read(ddr_read),.ddr_write(ddr_write),.ddr_busy(ddr_busy),
        .ddr_readdatavalid(ddr_readdatavalid),.ddr_readdata(ddr_readdata),
        .pegc_analog16(1'b1),.pegc_display_enable(1'b1),.pegc_gdc_5mhz(1'b1),
        .pegc_pixel_clk(clk),.pegc_palette_index(8'b0),.pegc_video_address(16'b0),
        .pegc_video_burstcount(5'b0),.pegc_video_read(1'b0));
    reg [28:0] keys[0:255];
    reg [63:0] words[0:255];
    integer used=0,cycles=0,left=0,read_index=0,commands=0,checks=0;
    reg write_pending=0;
    reg [31:0] pending_address,pending_data;
    integer write_requests=0,write_completions=0;
    task check(input bit good,input string reason);
        begin checks++;if(!good)$fatal(1,"native router: %s",reason);end
    endtask
    always @(posedge clk) begin
        cycles<=cycles+1;ddr_readdatavalid<=0;
        if(dut.avm_write && !dut.avm_waitrequest) begin
            check(!write_pending,"new store before prior completion");
            write_pending=1;write_requests++;
            pending_address={request_address,2'b0};pending_data=request_data;
        end
        if(dut.memory_write_complete) begin : completion_check
            reg [28:0] backing_word;
            integer found;
            check(write_pending,"unowned or repeated write completion");
            if(pending_address>=32'h00100000) begin
                backing_word=(pending_address[31:19]==(32'hfff00000>>19) ?
                    (32'h30f00000 | {13'b0,pending_address[18:0]}) :
                    (32'h30000000 | pending_address))>>3;
                found=-1;
                for(integer i=0;i<used;i++) if(keys[i]==backing_word) found=i;
                check(found>=0,"store completed before a DDR write");
                check(words[found][pending_address[2]*32+:32]===pending_data,
                    "store completed before all bytes reached DDR");
            end
            write_pending=0;write_completions++;
        end
        if(left!=0) begin
            left<=left-1;
            if(left==1) begin ddr_readdata<=words[read_index];ddr_readdatavalid<=1;end
        end
        if((ddr_read || ddr_write) && !ddr_busy) begin
            check(left==0 && !ddr_readdatavalid,"DDR response overtaken");
            check(ddr_burstcount==1 && ddr_address[28:25]==4'h3,"DDR region/burst");
            begin : lookup
                integer found;
                found=-1;
                for(integer i=0;i<used;i++) if(keys[i]==ddr_address) found=i;
                if(found==-1) begin found=used;keys[used]=ddr_address;words[used]=0;used++;end
                if(ddr_write) begin
                    for(integer k=0;k<8;k++) if(ddr_byteenable[k]) words[found][k*8+:8]=ddr_writedata[k*8+:8];
                end else begin read_index<=found;left<=25;end
            end
            commands<=commands+1;
        end
    end
    task begin_memory(input bit wr,input [31:0] a,input [31:0] data,input integer count);
        begin
            @(negedge clk);request_address=a[31:2];request_data=data;request_count=count;
            request_write=wr;request_read=!wr;
            @(posedge clk);while(dut.avm_waitrequest) @(posedge clk);
            @(negedge clk);request_write=0;request_read=0;
        end
    endtask
    task put(input [31:0] a,input [31:0] data);
        begin begin_memory(1,a,data,1);while(dut.fabric_busy) @(negedge clk);end
    endtask
    task get2(input [31:0] a,input [31:0] first,input [31:0] second,input integer count);
        integer n;
        begin
            begin_memory(0,a,0,count);n=0;
            while(n<count) begin
                if(dut.avm_readdatavalid) begin
                    check(dut.avm_readdata===(n==0 ? first : second),"crossing/alias/stale response");n++;
                end
                @(negedge clk);
            end
            while(dut.fabric_busy) @(negedge clk);
        end
    endtask
    task port_write(input [15:0] a,input [7:0] data);
        begin
            @(negedge clk);io_address=a;io_data=data;io_request=1;
            while(!dut.io_write_done) @(negedge clk);
            io_request=0;while(dut.fabric_busy) @(negedge clk);
        end
    endtask
    task cancel_read(input [31:0] a,input integer count);
        begin
            begin_memory(0,a,0,count);
            while(left==0) @(negedge clk);
            force dut.cpu_reset=1'b1;
            repeat(3) @(negedge clk);
            release dut.cpu_reset;
            get2(32'h00100000,32'h12345678,0,1);
        end
    endtask
    initial begin
        force dut.avm_address=request_address;force dut.avm_writedata=request_data;
        force dut.avm_byteenable=request_mask;force dut.avm_burstcount=request_count;
        force dut.avm_read=request_read;force dut.avm_write=request_write;
        force dut.io_read_do=1'b0;force dut.io_write_do=io_request;
        force dut.io_write_address=io_address;force dut.io_write_data=io_data;
        force dut.io_write_length=3'd1;
        repeat(4) @(negedge clk);reset=0;
        port_write(16'h6a,7);port_write(16'h6a,33);
        put(32'he0100,32'h00010000); // E0102 low lane enables linear memory.
        put(32'h00100000,32'h12345678);
        put(32'h00effffc,32'h10203040);
        put(32'h00f00000,32'h50607080);
        // This burst falls back to halfwords across the RAM/framebuffer edge.
        get2(32'h00effffc,32'h10203040,32'h50607080,2);
        put(32'h00effffc,32'haabbccdd);
        get2(32'h00effffc,32'haabbccdd,32'h50607080,2);
        get2(32'hfff00000,32'h50607080,0,1);
        put(32'hfff00000,32'h11223344);
        get2(32'h000a8000,32'h11223344,0,1);
        cancel_read(32'h00100000,4); // native RAM read
        cancel_read(32'hfff00000,4); // native framebuffer read in both modes
        cancel_read(32'h000a8000,1); // banked framebuffer read
        cancel_read(32'h00effffc,2); // fallback RAM read
        check(write_requests==write_completions && !write_pending,"missing write completion");
        $display("PASS native router RAM_ENABLE=%0d checks=%0d commands=%0d: boundary coherence, aliases, CPU-only reset tags",RAM_ENABLE,checks,commands);
        $finish;
    end
    initial begin #1000000;$fatal(1,"native router watchdog");end
endmodule
