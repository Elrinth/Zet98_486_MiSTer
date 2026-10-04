// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module pc98_pegc_bus_tb;
    reg clk=0,video_clk=0,reset=1,bus_reset=0;
    always #5.556 clk=~clk;
    always #19.861 video_clk=~video_clk;
    reg [31:1] address=0;
    reg [1:0] select=0;
    reg [15:0] writedata=0;
    reg write=0,io=0,strobe=0,legacy_ack=0;
    wire claimed,ack,mode256,single_page;
    wire [15:0] readdata;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable;
    wire ddr_read,ddr_write;
    reg ddr_busy=1,ddr_readdatavalid=0;
    reg [63:0] ddr_readdata=0;
    reg [7:0] video_index=0;
    wire [23:0] video_rgb;
    pc98_pegc_bus dut(.*,.linear_enable(),.analog16(1'b1),.display_enable(1'b1),.gdc_5mhz(1'b1));
    reg [7:0] memory[0:524287];
    integer checks=0,commands=0,palette_writes=0,ticks=0,pending=0,pending_address=0;
    reg hold_return=0;
    task check(input bit ok,input string reason);
        begin checks++;if(!ok)$fatal(1,"PEGC bus: %s",reason);end
    endtask
    always @(posedge clk) begin
        ticks<=ticks+1;ddr_busy<=ticks%5<2;ddr_readdatavalid<=0;
        if(dut.palette_write)palette_writes<=palette_writes+1;
        if(pending!=0 && !hold_return)begin
            pending<=pending-1;
            if(pending==1)begin
                for(integer b=0;b<8;b++)ddr_readdata[b*8+:8]<=memory[pending_address+b];
                ddr_readdatavalid<=1;
            end
        end
        if((ddr_read||ddr_write)&&!ddr_busy)begin
            check(ddr_address[28:16]==13'h61e,"DDR outside owned framebuffer");
            check(!reset&&!bus_reset,"DDR request during reset");
            check(pending==0&&!ddr_readdatavalid,"new DDR request before old return");
            commands<=commands+1;
            if(ddr_write)begin
                for(integer b=0;b<8;b++)if(ddr_byteenable[b])memory[{ddr_address[15:0],3'b0}+b]<=ddr_writedata[b*8+:8];
            end else begin pending<=8;pending_address<={ddr_address[15:0],3'b0};end
        end
    end
    task cycle(input bit isio,input bit wr,input [31:0] addr,input [1:0] lanes,
               input [15:0] data,input bit expect_claim,input [15:0] expected);
        integer timeout_cycles,old_commands;
        begin
            @(negedge clk);io=isio;write=wr;address=addr[31:1];select=lanes;writedata=data;strobe=1;
            #0.001;check(claimed===expect_claim,"address-space claim");
            timeout_cycles=0;
            if(expect_claim)begin
                while(!ack)begin @(negedge clk);timeout_cycles++;check(timeout_cycles<80,"ack timeout");end
                if(!wr)check(readdata===expected,"readback/byte-lane mismatch");
            end else begin
                repeat(3)@(negedge clk);legacy_ack=1;
            end
            // Hold completion for several clocks; target must not repeat work.
            old_commands=commands;
            repeat(4)@(negedge clk);
            check(commands==old_commands,"held ACK repeated framebuffer operation");
            strobe=0;legacy_ack=0;
            repeat(3)@(negedge clk);check(!ack,"ack did not release");
        end
    endtask
    task outb(input [15:0] port,input [7:0] data,input bit claim);
        cycle(1,1,{16'b0,port},1,{8'b0,data},claim,0);
    endtask
    task select_palette(input [7:0] index);
        outb(16'ha8,index,1);
    endtask
    integer i,bank,before_commands;
    reg [15:0] expected;
    initial begin
        for(i=0;i<524288;i++)memory[i]=(i*13)^(i>>8);
        repeat(4)@(negedge clk);reset=0;
        // Legacy accesses and high-byte-only I/O must pass through unchanged.
        cycle(0,0,32'ha8000,3,0,0,0);
        cycle(0,0,32'ha8,3,0,0,0);
        cycle(1,1,32'h6a,2,16'h0700,0,0);
        outb(16'h6a,8'h21,0);check(!mode256,"locked mode write accepted");
        outb(16'h6a,8'h07,0);outb(16'h6a,8'h21,0);check(mode256,"mode enable not snooped");
        outb(16'h6a,8'h69,0);check(single_page,"single page not snooped");
        outb(16'h9a0,8'h0a,1);cycle(1,0,32'h9a0,1,0,1,16'hff03);
        cycle(0,0,32'h9a0,3,0,0,0); // same address in memory is not I/O
        cycle(1,1,32'ha8,2,16'h4400,0,0); // odd I/O must not write index
        for(i=0;i<256;i++)begin
            select_palette(i);outb(16'hac,i^8'h57,1);outb(16'haa,i^8'hb3,1);outb(16'hae,i^8'hc6,1);
            cycle(1,0,32'ha8,1,0,1,{8'hff,i[7:0]});
            cycle(1,0,32'hac,1,0,1,{8'hff,i[7:0]^8'h57});
            cycle(1,0,32'haa,1,0,1,{8'hff,i[7:0]^8'hb3});
            cycle(1,0,32'hae,1,0,1,{8'hff,i[7:0]^8'hc6});
            @(negedge video_clk);video_index=i;
            @(negedge video_clk);check(video_rgb==={i[7:0]^8'h57,i[7:0]^8'hb3,i[7:0]^8'hc6},"palette pixel read");
        end
        check(palette_writes==768,"palette write repeated under held ACK");
        before_commands=commands;
        cycle(1,0,32'he0004,1,0,0,0); // memory MMIO cannot claim matching I/O
        cycle(0,0,32'h00f00000,3,0,0,0); // disabled linear aperture
        cycle(0,1,32'he0102,2,16'h0100,1,0); // high lane doesn't enable linear
        cycle(0,0,32'he0102,3,0,1,0);
        check(commands==before_commands,"register access reached framebuffer");
        cycle(0,1,32'he0102,1,1,1,0);
        for(bank=0;bank<16;bank++)begin
            cycle(0,1,32'he0004,1,bank,1,0);
            cycle(0,1,32'he0006,1,bank,1,0);
            for(i=0;i<8;i+=2)begin
                cycle(0,1,32'ha8000+i,3,16'ha000|(bank<<4)|i,1,0);
                cycle(0,0,32'h00f00000+(bank<<15)+i,3,0,1,16'ha000|(bank<<4)|i);
                cycle(0,1,32'hfff00000+(bank<<15)+i,1,16'h005c,1,0);
                cycle(0,1,32'hb0000+i,2,16'hc300,1,0);
                cycle(0,0,32'ha8000+i,3,0,1,16'hc35c);
            end
        end
        cycle(0,1,32'h00f7fffe,3,16'h9876,1,0);
        cycle(0,0,32'hfff7fffe,3,0,1,16'h9876);
        cycle(0,0,32'h00f80000,3,0,0,0);cycle(0,0,32'hfff80000,3,0,0,0);
        cycle(0,1,32'he0100,1,1,1,0); // planar windows are intentionally unimplemented
        before_commands=commands;
        cycle(0,0,32'ha8000,3,0,1,16'hffff);cycle(0,0,32'hb8000,3,0,1,16'hffff);
        check(commands==before_commands,"unimplemented window leaked to DDR");
        cycle(0,0,32'h00f7fffe,3,0,1,16'h9876); // linear still works
        outb(16'h6a,8'h20,0);check(!mode256,"mode disable");
        cycle(0,0,32'ha8000,3,0,0,0);cycle(1,0,32'ha8,1,0,0,0);
        cycle(0,0,32'hfff7fffe,3,0,1,16'h9876); // linear independent of display
        outb(16'h6a,8'h21,0);
        // CPU-only reset drains an accepted DDR read, retaining graphics state.
        @(negedge clk);address=32'h00f7fffe>>1;io=0;write=0;select=3;strobe=1;hold_return=1;
        while(pending==0)@(negedge clk);
        bus_reset=1;strobe=0;repeat(4)@(negedge clk);bus_reset=0;hold_return=0;
        cycle(0,0,32'hfff00000,3,0,1,16'hc35c);
        check(mode256&&single_page,"CPU reset erased display state");
        select_palette(255);cycle(1,0,32'hac,1,0,1,16'hffa8);
        reset=1;repeat(4)@(negedge clk);reset=0;
        check(!mode256,"core reset retained mode");
        cycle(0,0,32'h00f00000,3,0,0,0);
        outb(16'h6a,8'h07,0);outb(16'h6a,8'h21,0);
        select_palette(255);cycle(1,0,32'hac,1,0,1,16'hffa8); // soft reset preserves palette RAM
        $display("PASS: PEGC bus %0d checks/%0d DDR commands/%0d palette writes",checks,commands,palette_writes);
        $finish;
    end
    initial begin #5000000;$fatal(1,"PEGC bus watchdog");end
endmodule
