`timescale 1ns/1ps
module z486_segmentation_tb;
    import z486_pkg::*;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset_n = 0;
    logic seg_cmd_valid = 0, stssaf_pulse = 0, ctssaf_pulse = 0;
    logic [3:0] seg_cmd = 0, seg_target = SEG_DS;
    logic [3:0] exec_seg_cmd = 0, exec_seg_target = SEG_DS;
    logic init_addr32 = 1, init_stack_op = 0, clear_descsw = 0;
    logic [31:0] seg_data = 0, desc_lo = 0, desc_hi = 0;
    logic [15:0] slctr = 0;
    prot_transition_t transition = '0;
    logic pe = 0, vm = 0;
    logic [1:0] cpl = 0, access_size = 0;
    logic [31:0] offset = 0;
    logic check_en = 1, is_mem_op = 1, is_write = 0;
    wire seg_fault, is_stack_fault;
    integer cases = 0;
    logic [31:0] random_state = 32'h98C48650;

    segmentation_unit dut (
        .clk, .reset_n, .seg_cmd_valid, .stssaf_pulse, .ctssaf_pulse,
        .seg_cmd, .seg_target, .exec_seg_cmd, .exec_seg_target,
        .init_addr32, .init_stack_op, .clear_descsw, .seg_data, .desc_lo,
        .desc_hi, .slctr, .transition, .pe, .vm, .cpl, .offset, .access_size,
        .check_en, .is_mem_op, .is_write, .seg_fault, .is_stack_fault
    );

    function automatic [31:0] random_word();
        random_state = random_state ^ (random_state << 13);
        random_state = random_state ^ (random_state >> 17);
        random_state = random_state ^ (random_state << 5);
        return random_state;
    endfunction

    task automatic command(input [3:0] cmd, input [3:0] target,
                           input [31:0] data);
        @(negedge clk);
        seg_cmd_valid = 1; seg_cmd = cmd; seg_target = target; seg_data = data;
        @(negedge clk);
        seg_cmd_valid = 0; seg_cmd = 0;
    endtask

    task automatic write_limit(input [3:0] target, input [19:0] raw_limit,
                               input bit granularity);
        command(SEG_CMD_SAR, target, 32'h00009240 | (32'(granularity) << 7));
        command(SEG_CMD_SLIM, target, {12'd0, raw_limit});
    endtask

    // Oracle follows the previous architectural behavior, including the
    // real-mode 16-bit SS waiver for a starting offset beyond the limit.
    task automatic check(input [31:0] expected_limit, input bit address32,
                          input bit stack_segment, input bit table_segment,
                          input bit io_segment, input [31:0] trial_offset);
        logic [31:0] effective, remaining;
        logic expected, crossing, beyond;
        for (integer width = 0; width < 4; width++) begin
            @(negedge clk);
            offset = trial_offset; access_size = 2'(width);
            effective = (address32 || table_segment) ? trial_offset :
                                                       {16'd0, trial_offset[15:0]};
            remaining = expected_limit - effective;
            crossing = remaining < width;
            beyond = effective > expected_limit;
            expected = check_en && is_mem_op && !io_segment &&
                (pe ? (!table_segment && (crossing || beyond)) :
                 (crossing || (beyond && !(stack_segment && !address32))));
            #1;
            if (seg_fault !== expected || is_stack_fault !== stack_segment) begin
                $display("LIMIT DETAIL actual=%h effective=%h start=%b size=%b",
                         dut.seg_limit_r, dut.eff_offset,
                         dut.start_out_of_bounds, dut.size_fault);
                $fatal(1, "SEG LIMIT fault=%b expected=%b limit=%h offset=%h width=%0d pe=%b a32=%b ss=%b table=%b io=%b",
                       seg_fault, expected, expected_limit, trial_offset,
                       width, pe, address32, stack_segment, table_segment, io_segment);
            end
            cases++;
            @(posedge clk); #1; // also run internal equivalence assertions
        end
    endtask

    task automatic boundaries(input [31:0] limit_value, input bit address32,
                               input bit stack_segment);
        for (integer delta = -5; delta <= 5; delta++)
            check(limit_value, address32, stack_segment, 0, 0, limit_value + delta);
        check(limit_value, address32, stack_segment, 0, 0, 32'd0);
        check(limit_value, address32, stack_segment, 0, 0, 32'hFFFFFFFF);
        check(limit_value, address32, stack_segment, 0, 0, 32'hFFFF);
        check(limit_value, address32, stack_segment, 0, 0, 32'h10000);
        for (integer n = 0; n < 32; n++)
            check(limit_value, address32, stack_segment, 0, 0, random_word());
    endtask

    initial begin
        logic [19:0] raw_limit;
        logic [31:0] expanded;
        repeat (3) @(negedge clk);
        reset_n = 1;
        check(32'hFFFF, 0, 0, 0, 0, 32'hFFFF);
        for (integer trial = 0; trial < 160; trial++) begin
            case (trial)
                0: raw_limit = 0;
                1: raw_limit = 1;
                2: raw_limit = 2;
                3: raw_limit = 3;
                4: raw_limit = 20'hFF;
                5: raw_limit = 20'h100;
                6: raw_limit = 20'hFFFF;
                7: raw_limit = 20'h10000;
                8: raw_limit = 20'hFFFFF;
                default: raw_limit = 20'(random_word());
            endcase
            for (integer gran = 0; gran < 2; gran++) begin
                expanded = gran ? {raw_limit, 12'hFFF} : {12'd0, raw_limit};
                write_limit(SEG_DS, raw_limit, 1'(gran));
                write_limit(SEG_SS, raw_limit, 1'(gran));
                for (integer protected_mode = 0; protected_mode < 2; protected_mode++) begin
                    pe = 1'(protected_mode);
                    for (integer a32 = 0; a32 < 2; a32++) begin
                        init_addr32 = 1'(a32);
                        command(SEG_CMD_INIT_SEG, SEG_DS, 0);
                        boundaries(expanded, 1'(a32), 0);
                        command(SEG_CMD_INIT_SEG, SEG_SS, 0);
                        boundaries(expanded, 1'(a32), 1);
                    end
                end
            end
        end

        // Exercise every segment-limit update source and simultaneous
        // STSSAF/command priority, independently of the ordinary INIT path.
        pe = 1; init_addr32 = 1;
        write_limit(SEG_SS, 20'h127, 0);
        write_limit(SEG_CS, 20'h234, 0);
        write_limit(SEG_DS, 20'h567, 0);
        command(SEG_CMD_INIT_SEG, SEG_SS, 0);
        command(SEG_CMD_DESCSW, SEG_CS, 0);
        boundaries(32'h234, 1, 1);
        command(SEG_CMD_UPDATE_SEG, SEG_SS, 0);
        boundaries(32'h234, 1, 1);
        clear_descsw = 1;
        command(SEG_CMD_UPDATE_SEG, SEG_SS, 0);
        clear_descsw = 0;
        boundaries(32'h127, 1, 1);
        command(SEG_CMD_DESCSW, SEG_CS, 0);
        stssaf_pulse = 1;
        command(0, SEG_SS, 0);
        stssaf_pulse = 0;
        boundaries(32'h127, 1, 1);
        command(SEG_CMD_DESCSW, SEG_CS, 0);
        stssaf_pulse = 1;
        command(SEG_CMD_INIT_SEG, SEG_DS, 0);
        stssaf_pulse = 0;
        boundaries(32'h567, 1, 0);

        // Limit checks keep their existing memory/check-enable/IO gates.
        check_en = 0;
        check(32'h567, 1, 0, 0, 0, 32'hFFFFFFFF);
        check_en = 1; is_mem_op = 0;
        check(32'h567, 1, 0, 0, 0, 32'hFFFFFFFF);
        is_mem_op = 1;
        command(SEG_CMD_UPDATE_SEG, SEG_IO, 0);
        check(32'hFFFFFFFF, 1, 0, 0, 1, 32'hFFFFFFFF);
        command(SEG_CMD_UPDATE_SEG, SEG_GDT, 0);
        check(32'hFFFFFFFF, 1, 0, 1, 0, 32'hFFFFFFFF);
        pe = 0;
        check(32'hFFFFFFFF, 1, 0, 1, 0, 32'hFFFFFFFF);
        $display("PASS: z486 segment limits: %0d size/mode/boundary checks, all command update paths", cases);
        $finish;
    end
endmodule
