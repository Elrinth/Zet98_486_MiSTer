`timescale 1ns/1ps
module egc_write_tb;
    reg [15:0] operation,color_select,cpu_writedata,pixel_mask,clip_mask;
    reg [63:0] shifted_source,pattern_words,foreground_words,background_words;
    reg [3:0] plane_enable;
    reg [1:0] byte_enable;
    reg byte_access=0;          // word writes (byte mode: engine test)
    wire [63:0] base_words,xor_mask_words;
    wire load_pattern_on_write,configuration_valid;
    pc98_egc_write dut(.*);
    reg [63:0] destination,expected,captured_base,captured_mask;
    reg [1023:0] filename;
    integer file_handle,fields,count=0,k,mode;

    function automatic [63:0] reference(input [63:0] d);
        reg [63:0] s,p,r,enabled;
        reg [7:0] op;
        integer bit_no;
        begin
            s=shifted_source; p=pattern_words; op=operation[7:0];
            if(color_select[14:13]==1) p=background_words;
            else if(color_select[14:13]==2) p=foreground_words;
            else if(operation[9:8]==2) p=d;
            else if(operation[12:11]==1 && operation[9:8]==1) p=shifted_source;
            r=0;
            if(op[7]) r=r | ( s &  p &  d);
            if(op[6]) r=r | ( s & ~p &  d);
            if(op[5]) r=r | ( s &  p & ~d);
            if(op[4]) r=r | ( s & ~p & ~d);
            if(op[3]) r=r | (~s &  p &  d);
            if(op[2]) r=r | (~s & ~p &  d);
            if(op[1]) r=r | (~s &  p & ~d);
            if(op[0]) r=r | (~s & ~p & ~d);
            if(operation[12:11]==0) r={4{cpu_writedata}};
            if(operation[12:11]==2) r=p;
            for(bit_no=0;bit_no<64;bit_no=bit_no+1)
                enabled[bit_no]=plane_enable[bit_no/16] && byte_enable[(bit_no%16)/8] &&
                    pixel_mask[bit_no%16] && clip_mask[bit_no%16];
            reference=(r & enabled) | (d & ~enabled);
        end
    endfunction

    initial begin
        if(!$value$plusargs("vectors=%s",filename)) $fatal(1,"Missing write vectors");
        file_handle=$fopen(filename,"r");
        if(!file_handle) $fatal(1,"Cannot open write vectors");
        while(!$feof(file_handle)) begin
            fields=$fscanf(file_handle,"%h %h %h %h %h %h %h %h %h %h %h %h %h\n",
                operation,color_select,cpu_writedata,shifted_source,pattern_words,
                foreground_words,background_words,pixel_mask,clip_mask,
                plane_enable,byte_enable,destination,expected);
            if(fields!=13) $fatal(1,"Malformed EGC write vectors: %0d",fields);
            #1;
            if(!configuration_valid || load_pattern_on_write !== (operation[9:8]==2))
                $fatal(1,"EGC write control mismatch record=%0d",count);
            if((base_words ^ (destination & xor_mask_words)) !== expected || reference(destination)!==expected)
                $fatal(1,"EGC write mismatch record=%0d op=%h color=%h expected=%h got=%h model=%h",
                    count,operation,color_select,expected,base_words ^ (destination & xor_mask_words),reference(destination));
            // The coefficients must work for a destination not known when the
            // request is constructed. Change all fresh read bits after capture.
            captured_base=base_words; captured_mask=xor_mask_words;
            destination=~destination;
            if((captured_base ^ (destination & captured_mask)) !== reference(destination))
                $fatal(1,"EGC write fresh-destination mismatch record=%0d",count);
            count=count+1;
        end
        $fclose(file_handle);
        // Invalid encodings must be visible and preserve all destination bits.
        for(k=0;k<3;k=k+1) begin
            operation=16'h08f0; color_select=0;
            if(k==0) operation[12:11]=3;
            if(k==1) operation[9:8]=3;
            if(k==2) color_select[14:13]=3;
            #1;
            if(configuration_valid || load_pattern_on_write || base_words!==0 || xor_mask_words!==64'hffffffffffffffff)
                $fatal(1,"EGC write reserved encoding mismatch kind=%0d",k);
        end
        if(count!=17280) $fatal(1,"Incomplete NP2 EGC write corpus: %0d",count);
        $display("PASS: EGC write %0d NP2 cases, fresh destination variants and reserved controls",count);
        $finish;
    end
endmodule
