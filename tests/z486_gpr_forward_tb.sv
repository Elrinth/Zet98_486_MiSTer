`timescale 1ns/1ps
module z486_gpr_forward_tb;
    import z486_pkg::*;
    logic load_wb_valid, load_wb_is_alu;
    logic [2:0] load_wb_dst;
    logic [1:0] load_wb_size;
    logic [31:0] opr_r;
    logic [31:0] random_state = 32'h9821486;
    integer cases = 0;
    // No clocks: explore arbitrary registered states of the combinational
    // read network, independently of which instructions produce those states.
    data_unit dut (.clk(1'b0), .reset_n(1'b0), .load_wb_valid,
        .load_wb_is_alu, .load_wb_dst, .load_wb_size, .opr_r);

    function automatic [31:0] random_word();
        random_state = random_state ^ (random_state << 13);
        random_state = random_state ^ (random_state >> 17);
        random_state = random_state ^ (random_state << 5);
        return random_state;
    endfunction

    initial begin
        for (integer trial=0; trial<20000; trial++) begin
            dut.eax=random_word(); dut.ecx=random_word();
            dut.edx=random_word(); dut.ebx=random_word();
            dut.esp=random_word(); dut.ebp=random_word();
            dut.esi=random_word(); dut.edi=random_word();
            load_wb_valid=1'(trial); load_wb_is_alu=1'(trial>>1);
            load_wb_dst=3'(trial>>2); load_wb_size=2'(trial>>5);
            dut.load_wb_forward_data_r=random_word();
            dut.recipe_memory_write.valid=1'(trial>>7);
            dut.recipe_memory_dst_onehot=8'(random_word());
            dut.recipe_memory_mode=2'(trial>>8);
            dut.recipe_memory_killed=1'(trial>>10);
            dut.recipe_shift_killed=1'(trial>>11);

            opr_r=random_word();
            #1;
            for (integer r=0; r<8; r++)
                for (integer s=0; s<4; s++) begin
                    if (dut.read_gpr_load_forwarded(3'(r),2'(s)) !==
                        dut.read_gpr_load_forwarded_reference(3'(r),2'(s)))
                        $fatal(1,"GPR forwarding mismatch trial=%0d reg=%0d size=%0d",trial,r,s);
                    cases++;
                end
        end
        $display("PASS: %0d forwarded GPR reads over arbitrary register/WB/partial-merge states",cases);
        $finish;
    end
endmodule
