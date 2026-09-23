wire cond_18 = wr_cmd == `CMD_CALL_2 && (wr_cmdex == `CMDEX_CALL_2_call_gate_more_STEP_2 || wr_cmdex == `CMDEX_CALL_2_call_gate_more_STEP_3);
wire cond_19 = wr_cmd == `CMD_CALL_3 && ( wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_4 || wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_5 || wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_6 || wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_7);
wire cond_21 = wr_cmd == `CMD_PUSH_MOV_SEG && { wr_cmdex[3], 3'b0 } == `CMDEX_PUSH_MOV_SEG_implicit;
wire cond_54 = wr_cmd == `CMD_int_2 && ( wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_4 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_5 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_6 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_7 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_8 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_9);
wire cond_55 = wr_cmd == `CMD_int_3 && ( wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_0 || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_1 || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_2 || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_3);
wire cond_60 = wr_cmd == `CMD_int && wr_cmdex == `CMDEX_int_real_STEP_5;
wire cond_62 = wr_cmd == `CMD_int_2 && wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_5;
wire cond_63 = wr_cmd == `CMD_int_3 && wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_6;
wire cond_65 = wr_cmd == `CMD_int && (wr_cmdex == `CMDEX_int_real_STEP_0 || wr_cmdex == `CMDEX_int_real_STEP_1 || wr_cmdex == `CMDEX_int_real_STEP_2);
wire cond_82 = wr_cmd == `CMD_IRET && wr_cmdex == `CMDEX_IRET_real_v86_STEP_3;
wire cond_83 = wr_operand_32bit;
wire cond_87 = wr_cmd == `CMD_IRET && wr_cmdex == `CMDEX_IRET_protected_to_v86_STEP_5;
wire cond_89 = wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_same_STEP_1;
wire cond_93 = wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_outer_STEP_4;
wire cond_189 = (wr_cmd == `CMD_CALL_2 && (wr_cmdex == `CMDEX_CALL_2_call_gate_same_STEP_0 || wr_cmdex == `CMDEX_CALL_2_call_gate_same_STEP_1)) || (wr_cmd == `CMD_int_2 && (wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_0 || wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_1 || wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_2 || wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_3));
wire cond_216 = wr_cmd == `CMD_POPF && wr_cmdex == `CMDEX_POPF_STEP_0;
wire cond_240 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_1;
wire cond_253 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_9;

// Frozen before write-stage control predecode.
assign rflag_to_reg =
    (cond_60)? (  `FALSE) :
    (cond_62)? (  `FALSE) :
    (cond_63)? (  `FALSE) :
    (cond_82 && cond_83)? (  glob_param_3[16]) :
    (cond_87)? (  glob_param_3[16]) :
    (cond_89 && cond_83)? (  glob_param_3[16]) :
    (cond_93 && cond_83)? (  glob_param_5[16]) :
    (cond_216 && cond_83)? (  result2[16]) :
    (cond_240)? (  task_eflags[16]) :
    rflag;
assign wr_push_length_word =
    (cond_18)? (  ~(glob_param_3[19])) :
    (cond_19)? (  ~(glob_param_3[19])) :
    (cond_21)? (`TRUE) :
    (cond_54)? (  ~(glob_param_3[19])) :
    (cond_55)? ( ~(glob_param_3[19])) :
    (cond_65)? (`TRUE) :
    (cond_189)? (  ~(glob_param_1[19])) :
    (cond_253)? (  ~(glob_param_3[17])) :
    1'd0;
assign wr_push_length_dword =
    (cond_18)? ( glob_param_3[19]) :
    (cond_19)? ( glob_param_3[19]) :
    (cond_54)? ( glob_param_3[19]) :
    (cond_55)? ( glob_param_3[19]) :
    (cond_189)? ( glob_param_1[19]) :
    (cond_253)? ( glob_param_3[17]) :
    1'd0;
