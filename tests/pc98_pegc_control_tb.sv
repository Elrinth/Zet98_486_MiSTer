// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module pc98_pegc_control_tb;
    reg clk=0, reset=1;
    always #5 clk=~clk;
    reg [15:1] ia=0;
    reg [1:0] isel=0, msel=3;
    reg iw=0, ir=0, mw=0;
    reg [15:0] id=0, md=0;
    reg [31:1] ma=0;
    reg analog16=0, display_enable=0, gdc_5mhz=0;
    wire irs, ps, pw, mm, vs, unhandled, mode256, single_page, packed_mode, linear_enable;
    wire [7:0] ird, pi, pd;
    wire [1:0] pc;
    wire [15:0] mr;
    wire [18:1] va;
    integer checks=0, palette_beats=0;
    pc98_pegc_control dut(.clk(clk),.reset(reset),.io_address(ia),.io_select(isel),
        .io_write(iw),.io_read(ir),.io_writedata(id),.analog16(analog16),
        .display_enable(display_enable),.gdc_5mhz(gdc_5mhz),.io_read_selected(irs),
        .io_readdata(ird),.palette_selected(ps),.palette_write(pw),.palette_index(pi),
        .palette_component(pc),.palette_data(pd),.mem_address(ma),.mem_select(msel),
        .mem_write(mw),.mem_writedata(md),.mmio_selected(mm),.mmio_readdata(mr),
        .vram_selected(vs),.vram_word_address(va),.vram_unhandled(unhandled),
        .mode256(mode256),.single_page(single_page),.packed_mode(packed_mode),.linear_enable(linear_enable));
    task check(input bit good,input string msg);
        begin checks=checks+1; if(!good) $fatal(1,"PEGC: %s",msg); end
    endtask
    task outb(input [15:0] portno,input [7:0] data);
        begin
            @(negedge clk); ia=portno[15:1]; isel=portno[0]?2:1;
            id=portno[0]?{data,8'h00}:{8'h00,data}; iw=1;
            @(negedge clk); iw=0;
        end
    endtask
    task store(input [31:0] adr,input [15:0] data,input [1:0] lanes);
        begin @(negedge clk);ma=adr[31:1];msel=lanes;md=data;mw=1;
            @(negedge clk);mw=0;msel=3; end
    endtask
    task address(input [31:0] adr,input bit mapped,input [18:1] offset);
        begin ma=adr[31:1];#1;check(vs===mapped,"framebuffer address selection");
            if(mapped) check(va===offset,"framebuffer address translation");end
    endtask
    task status(input [7:0] idx,input [7:0] expected);
        begin outb('h9a0,idx);ir=1;#1;check(irs && ird===expected,"status readback");ir=0;end
    endtask
    reg [7:0] expected_index=0, expected_component=0, expected_data=0;
    always @(posedge clk) if(pw) begin
        check(pi===expected_index,"palette index aliases or truncated");
        check(pc===expected_component[1:0] && pd===expected_data,"palette component/data");
        palette_beats=palette_beats+1;
    end
    integer b,o,i,c;
    initial begin
        repeat(3) @(negedge clk);reset=0;
        check(!mode256 && packed_mode && !linear_enable,"reset mode");
        address('hf00000,0,0);address('hfff00000,0,0);
        outb('h6a,'h21);check(!mode256,"locked mode changed");
        outb('h6b,'h07);outb('h6a,'h21);check(!mode256,"odd port unlocked mode");
        outb('h6a,'h07);outb('h6a,'h21);check(mode256,"mode not enabled");
        outb('h6a,'h69);check(single_page,"single-page mode");
        gdc_5mhz=1;analog16=1;display_enable=1;
        status('h03,3);status('h04,3);status('h08,3);status('h0a,3);status('h0d,3);status('hff,2);
        // Entire 512 KB, all 16 banks, both banked windows, both aliases.
        store('he0102,1,1);
        for(b=0;b<16;b=b+1) begin
            store('he0004,b,3);store('he0006,15-b,3);
            for(o=0;o<32768;o=o+2) begin
                address('ha8000+o,1,(b*32768+o)/2);
                address('hb0000+o,1,((15-b)*32768+o)/2);
                address('hf00000+b*32768+o,1,(b*32768+o)/2);
                address('hfff00000+b*32768+o,1,(b*32768+o)/2);
            end
        end
        address('heffffe,0,0);address('hf80000,0,0);address('hffeffffe,0,0);address('hfff80000,0,0);
        address('hb8000,0,0);check(unhandled,"unused window leaked to legacy");
        address('he8000,0,0);check(!mm,"MMIO leaked to BIOS");
        ma='he7ffe>>1;#1;check(mm,"MMIO last word");
        store('he0004,'hfff5,3);ma='he0004>>1;#1;check(mr===16'h0005,"bank mask");
        store('he0004,'h0000,2);#1;check(mr===16'h0005,"high lane altered bank");
        store('he0100,1,1);check(!packed_mode,"planar mode latch");
        address('ha8000,0,0);check(unhandled,"planar silently mapped as packed");
        address('hf00100,1,'h80); // Linear map does not depend on window format.
        store('he0100,0,1);
        for(i=0;i<256;i=i+1) begin
            outb('ha8,i);expected_index=i;
            for(c=1;c<4;c=c+1) begin
                expected_component=c;expected_data=(i*7+c*39)&255;
                outb('ha8+c*2,expected_data);
            end
        end
        check(palette_beats==768,"missing palette writes");
        outb('hab,'hff);outb('haf,'hff);check(palette_beats==768,"odd port palette writes");
        outb('h6a,'h20);check(!mode256,"return to legacy");
        outb('haa,'hff);check(palette_beats==768 && !ps,"legacy palette intercepted");
        ma='he0100>>1;#1;check(!mm,"legacy E plane intercepted");
        address('ha8000,0,0);check(!unhandled,"legacy window intercepted");
        address('hf00000,1,0); // Aperture enable is independent of display mode.
        outb('h6a,'h21);store('he0102,0,1);address('hf00000,0,0);
        outb('h6a,'h06);outb('h6a,'h20);check(mode256,"locked clear changed mode");
        @(negedge clk);reset=1;repeat(2)@(negedge clk);
        check(!mode256 && !linear_enable && packed_mode && !single_page,"soft reset");
        $display("PASS: PEGC control %0d checks, 768 full-width palette component writes",checks);$finish;
    end
    initial begin #20000000;$fatal(1,"PEGC control timeout");end
endmodule
