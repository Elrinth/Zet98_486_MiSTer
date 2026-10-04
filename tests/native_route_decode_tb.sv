// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Compare the compact router against full-width byte-interval arithmetic at
// every 512 KB boundary in the 4 GB address space, for all legal burst sizes.
module native_route_decode_tb;
    parameter RAM_MB=64;
    parameter RAM_ENABLE=1;
    reg [29:0] avm_address=0;
    reg [3:0] avm_burstcount=1;
    reg avm_write=0, wide_linear_enable=0;
    ao486_memory_bridge #(.WIDE_RAM_MB(RAM_MB),.WIDE_RAM_ENABLE(RAM_ENABLE)) dut (
        .clk(1'b0),.reset(1'b1),.avm_address(avm_address),
        .avm_burstcount(avm_burstcount),.avm_write(avm_write),
        .wide_linear_enable(wide_linear_enable));
    reg [32:0] first_byte,end_byte;
    reg expected;
    integer checks=0;
    task verify(input [31:0] byte_address);
        begin
            avm_address=byte_address[31:2];
            first_byte={1'b0,byte_address};
            end_byte=first_byte+(avm_write ? 33'd4 : 4*avm_burstcount);
            expected=RAM_MB!=0 &&
                ((RAM_ENABLE && first_byte>=33'h100000 && end_byte<=RAM_MB*33'h100000 &&
                  (end_byte<=33'hf00000 || first_byte>=33'h1000000)) ||
                 (wide_linear_enable &&
                  ((first_byte>=33'hf00000 && end_byte<=33'hf80000) ||
                   (first_byte>=33'hfff00000 && end_byte<=33'hfff80000))));
            #1;
            if(dut.use_wide !== expected)
                $fatal(1,"route mismatch RAM=%0d address=%h count=%0d write=%b linear=%b got=%b expected=%b",
                    RAM_MB,byte_address,avm_burstcount,avm_write,wide_linear_enable,dut.use_wide,expected);
            checks++;
        end
    endtask
    initial begin
        for(integer linear=0;linear<2;linear++) begin
            wide_linear_enable=linear;
            for(integer wr=0;wr<2;wr++) begin
                avm_write=wr;
                for(integer count=1;count<=8;count++) begin
                    avm_burstcount=count;
                    for(integer block=0;block<8192;block++) begin
                        verify(block*32'h80000);
                        verify(block*32'h80000+32'h40000);
                        for(integer tail=1;tail<=8;tail++)
                            verify((block+1)*32'h80000-tail*4);
                    end
                end
            end
        end
        $display("PASS compact native decode RAM_MB=%0d RAM_ENABLE=%0d: %0d interval comparisons",RAM_MB,RAM_ENABLE,checks);
        $finish;
    end
endmodule
