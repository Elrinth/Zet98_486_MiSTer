`timescale 1ns/1ps
// Exhaust the complete combinational support of read/mask generation in the
// actual vendor RTL, including unreachable states and conflicting requesters.
module avalon_read_mask_tb;
    reg clk=0, rst_n=1;
    reg writeburst_do=0, readburst_do=0, readcode_do=0;
    reg [31:0] writeburst_address=0, readburst_address=0, readcode_address=0;
    reg [2:0] writeburst_length=1;
    reg [3:0] readburst_length=0;
    reg [31:0] writeburst_data_in=0;
    wire writeburst_done,readburst_done,readcode_done;
    wire [95:0] readburst_data_out;
    wire [31:0] readcode_partial,snoop_data,avm_writedata;
    wire [27:2] snoop_addr;
    wire [3:0] snoop_be,avm_byteenable,avm_burstcount;
    wire snoop_we,avm_read,avm_write;
    wire [31:2] avm_address;
    reg avm_waitrequest=1,avm_readdatavalid=0;
    reg [31:0] avm_readdata=0;
    reg [23:0] dma_address=0;
    reg dma_16bit=0,dma_write=0,dma_read=0;
    reg [15:0] dma_writedata=0;
    wire [15:0] dma_readdata;
    wire dma_readdatavalid,dma_waitrequest;
    avalon_mem dut(.*);
    integer state_value,controls,length,offset,dma_offset,width,reset_value;
    integer cases=0,reads=0;
    initial begin
        for(reset_value=0;reset_value<2;reset_value=reset_value+1)
        for(state_value=0;state_value<8;state_value=state_value+1) begin
            force dut.state=state_value;
            rst_n=reset_value;
            for(controls=0;controls<32;controls=controls+1)
            for(length=0;length<16;length=length+1)
            for(offset=0;offset<4;offset=offset+1)
            for(dma_offset=0;dma_offset<4;dma_offset=dma_offset+1)
            for(width=0;width<2;width=width+1) begin
                {writeburst_do,readburst_do,readcode_do,dma_read,dma_write}=controls;
                readburst_length=length; readburst_address=offset;
                dma_address=dma_offset; dma_16bit=width;
                #1;
                if(avm_read) begin
                    reads=reads+1;
                    if(avm_byteenable===0 || ^avm_byteenable===1'bx)
                        $fatal(1,"empty ao486 read mask: state=%0d controls=%h length=%0d offset=%0d",state_value,controls,length,offset);
                end
                cases=cases+1;
            end
        end
        release dut.state;
        if(reads!=7168 || cases!=262144) $fatal(1,"incomplete mask contract coverage: %0d %0d",reads,cases);
        $display("PASS: actual ao486 nonzero read masks, %0d inputs, %0d asserted reads",cases,reads);
        $finish;
    end
endmodule
