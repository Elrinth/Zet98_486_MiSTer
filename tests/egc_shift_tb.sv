`timescale 1ns/1ps
module egc_shift_tb;
    parameter USE_REGISTERS=0;
    reg clk=0, reset=1, reload=0, advance=0, byte_mode=0, byte_lane=0;
    always #5 clk=~clk;
    reg [15:0] shift_control=0, bit_length=15;
    reg [63:0] source_words=0;
    wire [63:0] shifted_words;
    wire [15:0] clip_mask;
    wire result_valid;
    reg [15:1] io_address=0;
    reg [15:0] io_writedata=0;
    reg io_strobe=0;
    wire [15:0] programmed_shift, programmed_length;
    wire shift_reload;
    pc98_egc_registers registers (
        .clk(clk),.reset(reset),.egc_enable(1'b1),.io_address(io_address),
        .io_select(2'b11),.io_writedata(io_writedata),.io_strobe(io_strobe),.io_write(1'b1),
        .shift_control(programmed_shift),.bit_length(programmed_length),.shift_reload(shift_reload)
    );
    pc98_egc_shift dut (
        .clk(clk),.reset(reset),.reload(USE_REGISTERS ? shift_reload : reload),.advance(advance),
        .byte_mode(byte_mode),.byte_lane(byte_lane),
        .shift_control(USE_REGISTERS ? programmed_shift : shift_control),
        .bit_length(USE_REGISTERS ? programmed_length : bit_length),.source_words(source_words),
        .shifted_words(shifted_words),.clip_mask(clip_mask),.result_valid(result_valid)
    );
    task write_register(input [15:0] port, input [15:0] value);
        begin
            io_address=port[15:1]; io_writedata=value; io_strobe=1;
            @(negedge clk);
            // The registered event reaches the shifter on the following edge.
            @(negedge clk);
            io_strobe=0;
            @(negedge clk);
        end
    endtask
    string vectors;
    integer file, fields, reload_value, shifts, lengths, records=0, gaps=0;
    reg [63:0] input_data, expected_data, held_data;
    reg [15:0] expected_mask, held_mask;
    reg held_valid;
    initial begin
        if (!$value$plusargs("vectors=%s", vectors)) $fatal(1, "Missing vectors");
        file=$fopen(vectors,"r");
        if (!file) $fatal(1, "Cannot open vectors");
        repeat(3) @(negedge clk);
        reset=0;
        while (!$feof(file)) begin
            fields=$fscanf(file,"%h %h %h %h %h %h\n", reload_value, shifts, lengths,
                           input_data, expected_mask, expected_data);
            if (fields!=6) $fatal(1,"Malformed vector");
            reload=reload_value==1;
            byte_mode=reload_value>=2; byte_lane=reload_value==3;
            // Reload must win even if a stale source completion is asserted.
            advance=1;
            shift_control=shifts;
            bit_length=lengths;
            source_words=input_data;
            if (USE_REGISTERS && reload_value==1) begin
                advance=0;
                write_register(16'h04ac, shifts);
                write_register(16'h04ae, lengths);
            end
            @(negedge clk);
            if (clip_mask!==expected_mask ||
                (shifted_words & {4{expected_mask}})!==expected_data ||
                result_valid!==(expected_mask!=0))
                $fatal(1,"EGC shift mismatch record=%0d shift=%h length=%0d mask=%h/%h data=%h/%h",
                       records,shift_control,bit_length+1,clip_mask,expected_mask,
                       shifted_words & {4{expected_mask}},expected_data);
            records=records+1;
            if ((records % 97)==0) begin
                // A held result must not advance with time or changing inputs.
                held_data=shifted_words; held_mask=clip_mask; held_valid=result_valid;
                reload=0; advance=0;
                repeat(3) begin
                    source_words=~source_words;
                    @(negedge clk);
                    if (shifted_words!==held_data || clip_mask!==held_mask || result_valid!==held_valid)
                        $fatal(1,"EGC shift hold mismatch");
                    gaps=gaps+1;
                end
            end
        end
        $fclose(file);
        // Reset also wins over a simultaneous input completion.
        reset=1; reload=0; advance=1;
        @(negedge clk);
        if (shifted_words!==0 || clip_mask!==0 || result_valid!==0)
            $fatal(1,"EGC shift reset mismatch");
        $display("PASS: EGC RTL shift registers=%0d: %0d records, %0d idle/poison cycles",USE_REGISTERS,records,gaps);
        $finish;
    end
endmodule
