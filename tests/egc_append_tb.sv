`timescale 1ns/1ps
// Check every alignment selector, including unreachable state encodings.
// Zero and every source basis bit cover the bitwise append operation.
module egc_append_tb;
    reg byte_mode=0, byte_lane=0;
    reg [15:0] shift_control=0;
    reg [63:0] source_words=0;
    pc98_egc_shift dut (
        .clk(1'b0), .reset(1'b0), .reload(1'b0), .advance(1'b0),
        .byte_mode(byte_mode), .byte_lane(byte_lane),
        .shift_control(shift_control), .bit_length(16'd15),
        .source_words(source_words), .shifted_words(), .clip_mask(), .result_valid()
    );
    integer mode, lane, rev, count, skip, basis, carry, plane, bitno, index;
    integer cases=0;
    reg [15:0] input_word, traversal;
    reg [31:0] expected;
    integer remaining_count;
    reg [15:0] expected_mask;
    initial begin
        for (mode=0; mode<2; mode=mode+1)
        for (lane=0; lane<2; lane=lane+1)
        for (rev=0; rev<2; rev=rev+1)
        for (count=0; count<32; count=count+1)
        for (skip=0; skip<16; skip=skip+1)
        for (basis=0; basis<17; basis=basis+1)
        for (carry=0; carry<2; carry=carry+1) begin
            byte_mode=mode; byte_lane=lane; shift_control=rev<<12;
            dut.pending_count=count; dut.source_skip=skip;
            dut.destination_skip=(count+skip+basis)%16;
            for (plane=0; plane<4; plane=plane+1) begin
                source_words[16*plane +:16]=basis==16 ? 16'b0 : (16'b1<<((basis+plane)%16));
                dut.pending[plane]=carry ? (16'h9a53 ^ (plane*16'h1357)) : 16'b0;
            end
            #1;
            for (plane=0; plane<4; plane=plane+1) begin
                input_word=source_words[16*plane +:16];
                traversal=0;
                for (bitno=0; bitno<(mode ? 8 : 16); bitno=bitno+1) begin
                    if (mode) index=8*lane+(rev ? bitno : 7-bitno);
                    else if (rev) index=(bitno+8)%16;
                    else index=(bitno<8 ? 7-bitno : 23-bitno);
                    traversal[bitno]=input_word[index];
                end
                expected=({16'b0,traversal}>>skip)<<count;
                expected=expected | {16'b0,dut.pending[plane]};
                if (dut.joined[plane] !== expected ||
                    dut.positioned[plane] !== ((expected[15:0] << dut.destination_skip) & 16'hffff) ||
                    dut.pending_next[plane] !== ((expected >> dut.needed) & 32'hffff))
                    $fatal(1,"EGC append mismatch mode=%0d lane=%0d rev=%0d count=%0d skip=%0d basis=%0d carry=%0d plane=%0d got=%h want=%h",
                        mode,lane,rev,count,skip,basis,carry,plane,dut.joined[plane],expected);
            end
            cases=cases+1;
        end
        $display("PASS: EGC append/position/carry selectors and basis bits: %0d cases x 4 planes",cases);
        for(remaining_count=0;remaining_count<8192;remaining_count=remaining_count+1)
        for(skip=0;skip<16;skip=skip+1) begin
            dut.remaining=remaining_count; dut.destination_skip=skip;
            for(bitno=0;bitno<16;bitno=bitno+1)
                expected_mask[bitno]=(bitno>=skip) && (bitno-skip<remaining_count);
            #1;
            if(dut.traversal_mask!==expected_mask) $fatal(1,"EGC shared clip endpoint mismatch");
        end
        $display("PASS: all 131072 EGC remaining-length/destination clip masks");
        $finish;
    end
endmodule
