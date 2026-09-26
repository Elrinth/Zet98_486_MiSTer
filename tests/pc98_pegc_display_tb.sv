// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Actual bus target -> shared DDR -> line RAM -> palette. Only DDR service and
// the CPU bus master are modeled. Pixel expectations use the original writes.
module pc98_pegc_display_tb;
    parameter CPU_HALF_PS=5556, VIDEO_PHASE_PS=1300;
    reg clk=0,video_clk=0,reset=1;
    always #(CPU_HALF_PS/1000.0) clk=~clk;
    initial begin #(VIDEO_PHASE_PS/1000.0);forever #19.861 video_clk=~video_clk;end
    reg [31:1] address=0;reg [1:0] select=0;reg [15:0] writedata=0;
    reg write=0,io=0,strobe=0,legacy_ack=0;
    wire claimed,ack,mode256,single_page;wire [15:0] readdata;
    wire [28:0] fb_address,ddr_address;
    wire [63:0] fb_data,ddr_data,client_data;
    wire [7:0] fb_mask,ddr_mask,ddr_count;
    wire fb_read,fb_write,fb_busy,fb_valid,ddr_read,ddr_write;
    reg ddr_busy=1,ddr_valid=0;reg [63:0] return_data=0;
    reg line_start=0,active=0,page_wrap=0,enable=0;
    reg [18:3] line_address=0;reg [9:0] pixel_x=0;
    wire [18:3] fetch_address;wire [4:0] fetch_count;
    wire fetch_read,fetch_busy,fetch_valid,pixel_valid;
    wire [7:0] pixel_index;wire [23:0] pixel_rgb;
    pc98_pegc_bus bus_target(.clk(clk),.video_clk(video_clk),.reset(reset),.bus_reset(1'b0),
        .address(address),.select(select),.writedata(writedata),.write(write),.io(io),.strobe(strobe),
        .legacy_ack(legacy_ack),.analog16(1'b1),.display_enable(1'b1),.gdc_5mhz(1'b1),
        .claimed(claimed),.ack(ack),.mode256(mode256),.single_page(single_page),.readdata(readdata),
        .ddr_address(fb_address),.ddr_writedata(fb_data),.ddr_byteenable(fb_mask),
        .ddr_read(fb_read),.ddr_write(fb_write),.ddr_busy(fb_busy),.ddr_readdatavalid(fb_valid),
        .ddr_readdata(client_data),.video_index(pixel_index),.video_rgb(pixel_rgb));
    pc98_pegc_line_fetch fetch(.cpu_clk(clk),.video_clk(video_clk),.reset(reset),
        .line_start(line_start),.line_enable(enable),.line_address(line_address),.page_wrap(page_wrap),
        .active(active),.pixel_x(pixel_x),.pixel_data(pixel_index),.pixel_valid(pixel_valid),
        .underrun(),.line_busy(),.memory_address(fetch_address),.memory_burstcount(fetch_count),
        .memory_read(fetch_read),.memory_busy(fetch_busy),.memory_readdatavalid(fetch_valid),.memory_readdata(client_data));
    pc98_pegc_ddr_arbiter arbiter(.clk(clk),.reset(reset),
        .ram_address(29'h06020000),.ram_writedata(64'b0),.ram_byteenable(8'hff),
        .ram_read(1'b1),.ram_write(1'b0),.ram_busy(),.ram_readdatavalid(),
        .fb_address(fb_address),.fb_writedata(fb_data),.fb_byteenable(fb_mask),.fb_read(fb_read),.fb_write(fb_write),
        .fb_busy(fb_busy),.fb_readdatavalid(fb_valid),.video_address(fetch_address),.video_burstcount(fetch_count),
        .video_read(fetch_read),.video_busy(fetch_busy),.video_readdatavalid(fetch_valid),.client_readdata(client_data),
        .ddr_address(ddr_address),.ddr_writedata(ddr_data),.ddr_byteenable(ddr_mask),.ddr_burstcount(ddr_count),
        .ddr_read(ddr_read),.ddr_write(ddr_write),.ddr_busy(ddr_busy),.ddr_readdatavalid(ddr_valid),.ddr_readdata(return_data));
    reg [7:0] memory[0:524287];
    integer ticks=0,remaining=0,delay_left=0,pos=0,checks=0,pixels=0;
    reg pending_fb=0;
    task check(input bit yes,input string why);
        begin checks++;if(!yes)$fatal(1,"PEGC display: %s",why);end
    endtask
    always @(posedge clk) begin
        ticks<=ticks+1;ddr_busy<=ticks%7<2;ddr_valid<=0;
        if(remaining!=0)begin
            if(delay_left!=0)delay_left<=delay_left-1;
            else begin
                for(integer b=0;b<8;b++)return_data[b*8+:8]<=pending_fb ? memory[pos+b] : 8'hcd;
                ddr_valid<=1;pos<=pos+8;remaining<=remaining-1;delay_left<=ticks%3;
            end
        end
        if((ddr_read||ddr_write)&&!ddr_busy)begin
            check(remaining==0&&!ddr_valid,"DDR command overtook response");
            check(ddr_address[28:16]==13'h61e || ddr_address==29'h06020000,"DDR backing address");
            if(ddr_write)begin
                check(ddr_count==1,"CPU write burst");
                for(integer b=0;b<8;b++)if(ddr_mask[b])memory[{ddr_address[15:0],3'b0}+b]<=ddr_data[b*8+:8];
            end else begin
                remaining<=ddr_count;delay_left<=ticks%7+3;pos<={ddr_address[15:0],3'b0};
                pending_fb<=ddr_address[28:16]==13'h61e;
            end
        end
    end
    task put(input bit isio,input [31:0] addr,input [1:0] lanes,input [15:0] data);
        integer n;
        begin
            @(negedge clk);io=isio;address=addr[31:1];select=lanes;writedata=data;write=1;strobe=1;
            #0.001;n=0;
            if(claimed)begin
                while(!ack)begin @(negedge clk);n++;check(n<150,"CPU write timeout");end
            end else begin check(isio && addr==32'h6a,"unexpected unclaimed write");legacy_ack=1;end
            repeat(3)@(negedge clk);strobe=0;legacy_ack=0;
            repeat(2)@(negedge clk);
        end
    endtask
    function automatic [7:0] index_of(input integer x,input integer pattern);
        index_of=(x*7)^(x>>8)^(pattern*53);
    endfunction
    function automatic [23:0] rgb_of(input [7:0] index);
        rgb_of={index^8'h57,index^8'hb3,index^8'hc6};
    endfunction
    integer pattern_now=0;
    reg [1:0] expected_valid=0;
    reg [23:0] expected_rgb[0:1];
    always @(posedge video_clk)begin
        #0.001;
        if(reset)expected_valid=0;
        if(expected_valid[1])begin
            check(pixel_rgb===expected_rgb[1],"CPU-written framebuffer/palette RGB mismatch");pixels++;
        end
        expected_valid={expected_valid[0],active&&enable&&!reset};
        expected_rgb[1]=expected_rgb[0];expected_rgb[0]=rgb_of(index_of(pixel_x,pattern_now));
    end
    task paint(input integer base,input bit wrap,input integer pattern);
        integer offset;
        begin
            for(integer x=0;x<640;x++)begin
                offset=wrap ? ((base&19'h40000)|((base+x)&19'h3ffff)) : ((base+x)&19'h7ffff);
                // Alternate the two CPU aliases and byte lanes. Upper bytes must
                // survive adjacent low-byte writes before the row is displayed.
                put(0,(x%2 ? 32'hfff00000 : 32'h00f00000)+offset,
                    offset%2 ? 2 : 1,offset%2 ? {index_of(x,pattern),8'b0} : {8'b0,index_of(x,pattern)});
            end
        end
    endtask
    task show(input integer base,input bit wrap,input integer pattern);
        begin
            @(negedge video_clk);line_address=base>>3;page_wrap=wrap;pattern_now=pattern;line_start=1;enable=1;
            @(negedge video_clk);line_start=0;
            repeat(159)@(negedge video_clk);
            for(integer x=0;x<640;x++)begin active=1;pixel_x=x;@(negedge video_clk);end
            active=0;repeat(5)@(negedge video_clk);
        end
    endtask
    integer i;
    initial begin
        for(i=0;i<524288;i++)memory[i]=8'hde;
        repeat(5)@(negedge clk);reset=0;
        put(1,32'h6a,1,7);put(1,32'h6a,1,16'h21);put(0,32'he0102,1,1);
        for(i=0;i<256;i++)begin
            put(1,32'ha8,1,i);put(1,32'hac,1,i^8'h57);put(1,32'haa,1,i^8'hb3);put(1,32'hae,1,i^8'hc6);
        end
        paint(0,0,1);paint(19'h7ffb8,0,2);paint(19'h3ffb8,1,3);
        // Repaint row0 last: the single-page wrap intentionally aliases its beginning.
        paint(0,0,1);show(0,0,1);
        paint(19'h7ffb8,0,2);show(19'h7ffb8,0,2);
        paint(19'h3ffb8,1,3);show(19'h3ffb8,1,3);
        paint(19'h7ffb8,1,4);show(19'h7ffb8,1,4);
        // CPU writes to a different row while a displayed row uses the same DDR.
        fork show(19'h7ffb8,1,4);paint(19'h20000,0,5);join
        show(19'h20000,0,5);
        check(pixels==3840,"pixel coverage");
        $display("PASS integrated PEGC CPU bus writes/DDR/line/palette: %0d pixels/%0d checks half=%0d phase=%0d",pixels,checks,CPU_HALF_PS,VIDEO_PHASE_PS);
        $finish;
    end
    initial begin #10000000;$fatal(1,"PEGC integrated watchdog");end
endmodule
