// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module pc98_native_ddr_tb;
    parameter LATENCY=7;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [29:0] address=0;
    reg [31:0] writedata=0;
    reg [3:0] byteenable=15,burstcount=1;
    reg read=0,write=0;
    wire waitrequest,busy,readdatavalid;
    wire [31:0] readdata;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable;
    wire ddr_read,ddr_write;
    wire ddr_busy=force_busy || cycles%7<2;
    reg delayed_valid=0;
    reg [63:0] delayed_data=0;
    wire ddr_readdatavalid=LATENCY==0 ? command && ddr_read : delayed_valid;
    wire [63:0] ddr_readdata=LATENCY==0 ? words[index] : delayed_data;
    reg force_busy=0;
    pc98_native_ddr_bridge dut(.*);
    reg [63:0] words[0:255],expected[0:255];
    integer cycles=0,commands=0,left=0,return_index=0,checks=0;
    wire command=(ddr_read || ddr_write) && !ddr_busy;
    wire [7:0] index=ddr_address[7:0];
    reg stalled=0;
    reg [102:0] stalled_payload;
    function automatic [63:0] pattern(input integer a);
        pattern={32'h36a17402^(a*32'd1741),32'hb0e93587^(a*32'd977)};
    endfunction
    task check(input bit good,input string message);
        begin checks++;if(!good)$fatal(1,"native DDR: %s",message);end
    endtask
    always @(posedge clk) begin
        cycles<=cycles+1;
        delayed_valid<=0;
        if(stalled && !reset)
            check({ddr_address,ddr_writedata,ddr_byteenable,ddr_read,ddr_write}===stalled_payload,
                  "command changed under DDR waitrequest");
        stalled<=(ddr_read || ddr_write) && ddr_busy && !reset;
        stalled_payload<={ddr_address,ddr_writedata,ddr_byteenable,ddr_read,ddr_write};
        if(left!=0) begin
            left<=left-1;
            if(left==1) begin
                delayed_valid<=1;
                delayed_data<=words[return_index];
            end
        end
        if(command) begin
            check(!reset && !(ddr_read && ddr_write),"command during reset or R/W overlap");
            check(left==0 && !delayed_valid,"read response overtaken");
            check(ddr_address[28:25]==4'h3,"DDR escaped core-owned region");
            check(ddr_address==((32'h30100000>>3)|index) ||
                  ddr_address==((32'h30f00000>>3)|index),"RAM/linear alias backing address");
            if(ddr_write) begin
                for(integer k=0;k<8;k++)
                    if(ddr_byteenable[k]) words[index][k*8+:8]<=ddr_writedata[k*8+:8];
            end else begin return_index<=index;left<=LATENCY;end
            commands<=commands+1;
        end
    end
    task put(input [31:0] a,input [3:0] mask,input [31:0] data);
        integer p;
        begin
            @(negedge clk);address=a[31:2];byteenable=mask;writedata=data;write=1;
            @(posedge clk);while(waitrequest) @(posedge clk);
            @(negedge clk);write=0;
            p=(a>>3)&255;
            for(integer k=0;k<4;k++) if(mask[k]) expected[p][((a&4)*8+k*8)+:8]=data[k*8+:8];
        end
    endtask
    task get(input [31:0] a,input integer count);
        integer n,p,lane;
        begin
            @(negedge clk);address=a[31:2];burstcount=count;read=1;
            @(posedge clk);while(waitrequest) @(posedge clk);
            @(negedge clk);read=0;n=0;
            while(n<count) begin
                if(readdatavalid) begin
                    p=((a+4*n)>>3)&255;lane=((a+4*n)&4)*8;
                    check(readdata===expected[p][lane+:32],"burst order, byte mask or stale data");
                    n++;
                end
                @(negedge clk);
            end
        end
    endtask
    integer before_commands;
    initial begin
        for(integer i=0;i<256;i++) begin words[i]=pattern(i);expected[i]=pattern(i);end
        repeat(4) @(negedge clk);reset=0;
        // Every byte mask, both DWORD halves and both linear framebuffer aliases.
        for(integer m=0;m<16;m++) begin
            put(32'h00100000+m*8,m,32'h92831b75^m);
            put(32'hfff00004+m*8,m,32'h196f02a8^m);
            get(32'h00100000+m*8,2);
            get(32'h00f00000+m*8,2);
        end
        for(integer n=1;n<=8;n++) begin
            before_commands=commands;get(32'h00100100,n);
            check(commands-before_commands==(n+1)/2,"aligned burst did not reuse both DDR halves");
            before_commands=commands;get(32'hfff00104,n);
            check(commands-before_commands==(n+2)/2,"odd-start burst DDR count");
        end
        // An unaccepted write disappears on reset; accepted reads drain without
        // presenting their data to a later CPU request, even after reset falls.
        force_busy=1;
        @(negedge clk);address=32'h00100000>>2;write=1;writedata=32'hdeadbeef;
        repeat(5) @(negedge clk);before_commands=commands;reset=1;write=0;
        repeat(3) @(negedge clk);force_busy=0;reset=0;
        check(commands==before_commands,"canceled write reached DDR");
        @(negedge clk);address=32'h00100000>>2;read=1;burstcount=8;
        @(posedge clk);while(waitrequest) @(posedge clk);
        @(negedge clk);read=0;reset=1;
        @(negedge clk);reset=0;
        while(busy) begin check(!readdatavalid,"canceled read delivered data");@(negedge clk);end
        get(32'h00100020,4);
        $display("PASS native DDR latency=%0d checks=%0d commands=%0d",LATENCY,checks,commands);
        $finish;
    end
    initial begin #1000000;$fatal(1,"native DDR watchdog");end
endmodule
