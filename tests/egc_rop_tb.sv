`timescale 1ns/1ps
module egc_rop_tb;
    reg [7:0] operation;
    reg [63:0] source_words, pattern_words, destination_words;
    reg [15:0] bit_mask;
    reg [1:0] byte_enable;
    reg [3:0] plane_enable;
    wire [63:0] base_words, xor_mask_words, result_words;
    pc98_egc_rop dut(.*);

    // Independent sum-of-products reference: no destination decomposition
    // and no dynamic bit lookup from the production kernel.
    function automatic [63:0] reference;
        input [7:0] op;
        input [63:0] s,p,d;
        input [15:0] mask;
        input [1:0] bytes;
        input [3:0] planes;
        reg [63:0] value, enabled;
        integer k;
        begin
            value=0; enabled=0;
            if(op[7]) value=value | ( s &  p &  d);
            if(op[6]) value=value | ( s & ~p &  d);
            if(op[5]) value=value | ( s &  p & ~d);
            if(op[4]) value=value | ( s & ~p & ~d);
            if(op[3]) value=value | (~s &  p &  d);
            if(op[2]) value=value | (~s & ~p &  d);
            if(op[1]) value=value | (~s &  p & ~d);
            if(op[0]) value=value | (~s & ~p & ~d);
            for(k=0;k<64;k=k+1)
                enabled[k]=planes[k/16] & bytes[(k%16)/8] & mask[k%16];
            reference=(value & enabled) | (d & ~enabled);
        end
    endfunction

    integer op,truth,planes,bytes,mask,k,checks=0;
    task compare;
        begin
            #1;
            if(result_words!==reference(operation,source_words,pattern_words,
                destination_words,bit_mask,byte_enable,plane_enable))
                $fatal(1,"EGC ROP mismatch op=%h mask=%h planes=%h bytes=%h",
                    operation,bit_mask,plane_enable,byte_enable);
            checks=checks+1;
        end
    endtask

    initial begin
        // All 256 operation tables, every truth-table input, every plane
        // subset and byte mask. Distinct bit/plane patterns expose swaps.
        for(op=0;op<256;op=op+1)
        for(truth=0;truth<8;truth=truth+1)
        for(planes=0;planes<16;planes=planes+1)
        for(bytes=0;bytes<4;bytes=bytes+1) begin
            operation=op; plane_enable=planes; byte_enable=bytes; bit_mask=16'hffff;
            for(k=0;k<64;k=k+1) begin
                source_words[k]=((truth+k/16+k)%8)/4;
                destination_words[k]=(((truth+k/16+k)%8)/2)%2;
                pattern_words[k]=(truth+k/16+k)%2;
            end
            compare();
        end
        // Every 16-bit clipping mask, with all operands changing together.
        for(mask=0;mask<65536;mask=mask+1) begin
            bit_mask=mask; operation=$random; byte_enable=$random; plane_enable=$random;
            source_words={$random,$random}; pattern_words={$random,$random};
            destination_words={$random,$random}; compare();
        end
        $display("PASS EGC ROP: %0d operation/truth/plane/byte/clip cases",checks);
        $finish;
    end
endmodule
