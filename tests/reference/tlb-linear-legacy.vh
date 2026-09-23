// Original ao486 TLB address update and request qualifiers.
wire cond_0 = state == STATE_IDLE;
wire cond_1 = tlbflushsingle_do;
wire cond_2 = tlbflushall_do || tlbflushall_do_waiting;
wire cond_3 = ~(wr_reset) && tlbwrite_do && ~(write_ac) && cr0_am && acflag && tlbwrite_cpl == 2'd3 &&
             ( (tlbwrite_length_full == 3'd2 && tlbwrite_address[0] != 1'b0) || (tlbwrite_length_full == 3'd4 && tlbwrite_address[1:0] != 2'b00) )
    ;
wire cond_4 = ~(wr_reset) && tlbwrite_do && ~(write_pf) && ~(write_ac);
wire cond_5 = ~(exe_reset) && tlbcheck_do && ~(tlbcheck_done) && ~(check_pf);
wire cond_6 = ~(rd_reset) && tlbread_do && ~(read_ac) && cr0_am && acflag && tlbread_cpl == 2'd3 &&
             ( (tlbread_length_full == 4'd2 && tlbread_address[0] != 1'b0) || (tlbread_length_full == 4'd4 && tlbread_address[1:0] != 2'b00))
    ;
wire cond_7 = ~(rd_reset) && tlbread_do && ~(read_pf) && ~(read_ac);
wire cond_8 = ~(pr_reset) && tlbcoderequest_do && ~(code_pf) && ~(tlbcode_do);
wire cond_9 = state == STATE_WRITE_DOUBLE;
wire cond_10 = write_double_state == WRITE_DOUBLE_CHECK;
wire [31:0] linear_to_reg =
    (cond_0 && ~cond_1 && ~cond_2 && ~cond_3 && cond_4)? ( tlbwrite_address) :
    (cond_0 && ~cond_1 && ~cond_2 && ~cond_3 && ~cond_4 && cond_5)? ( tlbcheck_address) :
    (cond_0 && ~cond_1 && ~cond_2 && ~cond_3 && ~cond_4 && ~cond_5 && ~cond_6 && cond_7)? ( tlbread_address) :
    (cond_0 && ~cond_1 && ~cond_2 && ~cond_3 && ~cond_4 && ~cond_5 && ~cond_6 && ~cond_7 && cond_8)? ( tlbcoderequest_address) :
    (cond_9 && cond_10)? ( { linear[31:12], 12'd0 } + 32'h00001000) :
    (cond_9 && ~cond_10)? ( write_double_linear) :
    linear;
