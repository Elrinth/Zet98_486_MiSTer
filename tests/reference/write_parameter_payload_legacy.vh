// Original global-parameter payload, enable, and qualifiers.
wire cond_0 = wr_cmd == `CMD_XADD && wr_cmdex == `CMDEX_XADD_FIRST;
wire cond_1 = wr_dst_is_memory && ~(write_for_wr_ready);
wire cond_2 = wr_cmd == `CMD_XADD && wr_cmdex == `CMDEX_XADD_LAST;
wire cond_3 = wr_modregrm_mod != 2'b11 || wr_modregrm_reg != wr_modregrm_rm;
wire cond_4 = wr_cmd == `CMD_JCXZ;
wire cond_5 = result_signals[0];
wire cond_6 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_Ep_STEP_0 || wr_cmdex == `CMDEX_CALL_Ap_STEP_0);
wire cond_7 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_Ep_STEP_1 || wr_cmdex == `CMDEX_CALL_Ap_STEP_1);
wire cond_8 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_real_v8086_STEP_0 || wr_cmdex == `CMDEX_CALL_real_v8086_STEP_1);
wire cond_9 = ~(write_for_wr_ready);
wire cond_10 = ~(wr_push_ss_fault);
wire cond_11 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_Ev_STEP_0 || wr_cmdex == `CMDEX_CALL_Jv_STEP_0);
wire cond_12 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_Ev_Jv_STEP_1 || wr_cmdex == `CMDEX_CALL_real_v8086_STEP_3);
wire cond_13 = wr_cmd == `CMD_CALL && wr_cmdex == `CMDEX_CALL_real_v8086_STEP_2;
wire cond_14 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_protected_seg_STEP_0 || wr_cmdex == `CMDEX_CALL_protected_seg_STEP_1);
wire cond_15 = ~(wr_new_push_ss_fault);
wire cond_16 = wr_cmd == `CMD_CALL && wr_cmdex == `CMDEX_CALL_protected_seg_STEP_2;
wire cond_17 = wr_cmd == `CMD_CALL_2 && wr_cmdex == `CMDEX_CALL_2_task_switch_STEP_0;
wire cond_18 = wr_cmd == `CMD_CALL_2 && (wr_cmdex == `CMDEX_CALL_2_call_gate_more_STEP_2 || wr_cmdex == `CMDEX_CALL_2_call_gate_more_STEP_3);
wire cond_19 = wr_cmd == `CMD_CALL_3 && ( wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_4 || wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_5 || wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_6 || wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_7);
wire cond_20 = wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_7;
wire cond_21 = wr_cmd == `CMD_PUSH_MOV_SEG && { wr_cmdex[3], 3'b0 } == `CMDEX_PUSH_MOV_SEG_implicit;
wire cond_22 = write_for_wr_ready && ~(wr_push_ss_fault);
wire cond_23 = wr_cmd == `CMD_PUSH_MOV_SEG && { wr_cmdex[3], 3'b0 } == `CMDEX_PUSH_MOV_SEG_modregrm;
wire cond_24 = wr_cmd == `CMD_NEG;
wire cond_25 = wr_cmd == `CMD_Jcc;
wire cond_26 = wr_cmd == `CMD_INVD && wr_cmdex == `CMDEX_INVD_STEP_0;
wire cond_27 = wr_cmd == `CMD_INVD && wr_cmdex == `CMDEX_INVD_STEP_1;
wire cond_28 = wr_cmd == `CMD_INVLPG && wr_cmdex == `CMDEX_INVLPG_STEP_0;
wire cond_29 = wr_cmd == `CMD_INVLPG && wr_cmdex == `CMDEX_INVLPG_STEP_1;
wire cond_30 = wr_cmd == `CMD_io_allow && (wr_cmdex == `CMDEX_io_allow_1 || wr_cmdex == `CMDEX_io_allow_2);
wire cond_31 = wr_cmd == `CMD_HLT && wr_cmdex == `CMDEX_HLT_STEP_0;
wire cond_32 = wr_cmd == `CMD_SCAS;
wire cond_33 = ~(wr_string_ignore);
wire cond_34 = wr_prefix_group_1_rep != 2'd0;
wire cond_35 = wr_string_ignore || wr_string_zf_finish;
wire cond_36 = ~(wr_string_ignore) && ~(wr_string_zf_finish) && wr_prefix_group_1_rep != 2'd0;
wire cond_37 = wr_cmd == `CMD_INC_DEC;
wire cond_38 = wr_cmd == `CMD_RET_near && wr_cmdex != `CMDEX_RET_near_LAST;
wire cond_39 = wr_cmd == `CMD_ARPL;
wire cond_40 = wr_cmd == `CMD_BSWAP;
wire cond_41 = wr_cmd == `CMD_LxS && wr_cmdex != `CMDEX_LxS_STEP_LAST;
wire cond_42 = wr_cmd == `CMD_LxS && wr_cmdex == `CMDEX_LxS_STEP_LAST;
wire cond_43 = (wr_cmd == `CMD_MOV_to_seg || wr_cmd == `CMD_LLDT || wr_cmd == `CMD_LTR) && wr_cmdex == `CMDEX_MOV_to_seg_LLDT_LTR_STEP_1;
wire cond_44 = (wr_cmd == `CMD_MOV_to_seg || wr_cmd == `CMD_LLDT || wr_cmd == `CMD_LTR) && wr_cmdex == `CMDEX_MOV_to_seg_LLDT_LTR_STEP_LAST;
wire cond_45 = wr_cmd == `CMD_MOV_to_seg && wr_decoder[13:11] == `SEGMENT_SS;
wire cond_46 = wr_cmd == `CMD_CLC;
wire cond_47 = wr_cmd == `CMD_CMC;
wire cond_48 = wr_cmd == `CMD_CLD;
wire cond_49 = wr_cmd == `CMD_STC;
wire cond_50 = wr_cmd == `CMD_STD;
wire cond_51 = wr_cmd == `CMD_SAHF;
wire cond_52 = wr_cmd == `CMD_int_2  && wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_2;
wire cond_53 = wr_cmd == `CMD_int_2  && wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_3;
wire cond_54 = wr_cmd == `CMD_int_2 && ( wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_4 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_5 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_6 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_7 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_8 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_9);
wire cond_55 = wr_cmd == `CMD_int_3 && ( wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_0 || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_1 || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_2 || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_3);
wire cond_56 = (wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_2 && ~(exc_push_error)) || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_3;
wire cond_57 = wr_cmd == `CMD_int && wr_cmdex == `CMDEX_int_STEP_0;
wire cond_58 = wr_cmd == `CMD_int && wr_cmdex == `CMDEX_int_STEP_1;
wire cond_59 = wr_cmd == `CMD_int && (wr_cmdex == `CMDEX_int_real_STEP_3 || wr_cmdex == `CMDEX_int_real_STEP_4);
wire cond_60 = wr_cmd == `CMD_int && wr_cmdex == `CMDEX_int_real_STEP_5;
wire cond_61 = wr_cmd == `CMD_int && (wr_cmdex == `CMDEX_int_protected_STEP_0 || wr_cmdex == `CMDEX_int_protected_STEP_1 || wr_cmdex == `CMDEX_int_protected_STEP_2);
wire cond_62 = wr_cmd == `CMD_int_2 && wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_5;
wire cond_63 = wr_cmd == `CMD_int_3 && wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_6;
wire cond_64 = v8086_mode;
wire cond_65 = wr_cmd == `CMD_int && (wr_cmdex == `CMDEX_int_real_STEP_0 || wr_cmdex == `CMDEX_int_real_STEP_1 || wr_cmdex == `CMDEX_int_real_STEP_2);
wire cond_66 = wr_cmd == `CMD_AAM || wr_cmd == `CMD_AAD;
wire cond_67 = wr_cmd == `CMD_load_seg && wr_cmdex == `CMDEX_load_seg_STEP_1;
wire cond_68 = real_mode;
wire cond_69 = protected_mode && glob_param_1[15:2] == 14'd0;
wire cond_70 = wr_cmd == `CMD_load_seg && wr_cmdex == `CMDEX_load_seg_STEP_2;
wire cond_71 = ~(protected_mode && (glob_param_1[15:2] == 14'd0 || glob_param_1[`MC_PARAM_1_FLAG_NO_WRITE_BIT]));
wire cond_72 = glob_param_1[18:16] == `SEGMENT_TR || (glob_param_1[18:16] < `SEGMENT_LDT && `DESC_IS_NOT_ACCESSED(glob_descriptor));
wire cond_73 = glob_param_1[18:16] == `SEGMENT_TR;
wire cond_74 = glob_param_1[18:16] == `SEGMENT_LDT || (glob_param_1[18:16] < `SEGMENT_LDT && `DESC_IS_ACCESSED(glob_descriptor));
wire cond_75 = wr_cmd == `CMD_POP_seg && wr_cmdex == `CMDEX_POP_seg_STEP_1;
wire cond_76 = wr_cmd == `CMD_POP_seg && wr_cmdex == `CMDEX_POP_seg_STEP_LAST;
wire cond_77 = wr_decoder[5:3] == `SEGMENT_SS;
wire cond_78 = { wr_cmd[6:2], 2'd0 } == `CMD_BTx;
wire cond_79 = wr_cmd[1:0] != 2'd0;
wire cond_80 = wr_cmd == `CMD_IRET && wr_cmdex <= `CMDEX_IRET_real_v86_STEP_2;
wire cond_81 = wr_cmdex == `CMDEX_IRET_real_v86_STEP_0;
wire cond_82 = wr_cmd == `CMD_IRET && wr_cmdex == `CMDEX_IRET_real_v86_STEP_3;
wire cond_83 = wr_operand_32bit;
wire cond_84 = wr_cmd == `CMD_IRET && (wr_cmdex == `CMDEX_IRET_protected_STEP_0 || wr_cmdex == `CMDEX_IRET_task_switch_STEP_0 || wr_cmdex == `CMDEX_IRET_task_switch_STEP_1);
wire cond_85 = wr_cmd == `CMD_IRET && wr_cmdex >= `CMDEX_IRET_protected_STEP_1 && wr_cmdex <= `CMDEX_IRET_protected_STEP_3;
wire cond_86 = wr_cmd == `CMD_IRET && wr_cmdex >= `CMDEX_IRET_protected_to_v86_STEP_0 && wr_cmdex <= `CMDEX_IRET_protected_to_v86_STEP_4;
wire cond_87 = wr_cmd == `CMD_IRET && wr_cmdex == `CMDEX_IRET_protected_to_v86_STEP_5;
wire cond_88 = wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_to_v86_STEP_6;
wire cond_89 = wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_same_STEP_1;
wire cond_90 = cpl <= iopl;
wire cond_91 = cpl == 2'd0;
wire cond_92 = wr_cmd == `CMD_IRET_2 && wr_cmdex >= `CMDEX_IRET_2_protected_outer_STEP_0 && wr_cmdex <= `CMDEX_IRET_2_protected_outer_STEP_2;
wire cond_93 = wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_outer_STEP_4;
wire cond_94 = wr_task_rpl <= iopl;
wire cond_95 = wr_task_rpl == 2'd0;
wire cond_96 = wr_cmd == `CMD_POP && wr_cmdex == `CMDEX_POP_implicit;
wire cond_97 = wr_cmd == `CMD_POP && wr_cmdex == `CMDEX_POP_modregrm_STEP_0;
wire cond_98 = wr_cmd == `CMD_POP && wr_cmdex == `CMDEX_POP_modregrm_STEP_1;
wire cond_99 = ~(wr_dst_is_memory) || write_for_wr_ready;
wire cond_100 = wr_cmd == `CMD_IDIV || wr_cmd == `CMD_DIV;
wire cond_101 = ~(wr_is_8bit);
wire cond_102 = wr_cmd == `CMD_Shift;
wire cond_103 = ~(result_signals[4]);
wire cond_104 = result_signals[3];
wire cond_105 = result_signals[2];
wire cond_106 = wr_cmd == `CMD_CMPS && wr_cmdex == `CMDEX_CMPS_FIRST;
wire cond_107 = wr_cmd == `CMD_CMPS && wr_cmdex == `CMDEX_CMPS_LAST;
wire cond_108 = wr_string_ignore || wr_string_zf_finish || wr_prefix_group_1_rep == 2'd0;
wire cond_109 = wr_cmd == `CMD_control_reg && wr_cmdex == `CMDEX_control_reg_SMSW_STEP_0;
wire cond_110 = wr_cmd == `CMD_control_reg && wr_cmdex == `CMDEX_control_reg_LMSW_STEP_0;
wire cond_111 = cr0_pe ^ result2[0];
wire cond_112 = wr_cmd == `CMD_control_reg && wr_cmdex == `CMDEX_control_reg_MOV_store_STEP_0;
wire cond_113 = wr_cmd == `CMD_control_reg && wr_cmdex == `CMDEX_control_reg_MOV_load_STEP_0;
wire cond_114 = wr_decoder[13:11] == 3'd0;
wire cond_115 = (cr0_pe ^ result2[0]) || (cr0_wp ^ result2[16]) || (cr0_pg ^ result[31]);
wire cond_116 = cr0_pe && result2[0] == 1'b0;
wire cond_117 = wr_decoder[13:11] == 3'd2;
wire cond_118 = wr_decoder[13:11] == 3'd3;
wire cond_119 = (wr_cmd == `CMD_LGDT || wr_cmd == `CMD_LIDT);
wire cond_120 = wr_cmdex == `CMDEX_LGDT_LIDT_STEP_1;
wire cond_121 = wr_cmd == `CMD_LGDT;
wire cond_122 = wr_cmd == `CMD_LIDT;
wire cond_123 = wr_cmdex == `CMDEX_LGDT_LIDT_STEP_2;
wire cond_124 = wr_cmd == `CMD_PUSHA;
wire cond_125 = wr_cmdex[2:0] == 3'd0;
wire cond_126 = wr_cmdex[2:0] < 3'd7;
wire cond_127 = wr_cmdex[2:0] == 3'd7 && write_for_wr_ready && ~(wr_push_ss_fault);
wire cond_128 = wr_cmd == `CMD_SETcc;
wire cond_129 = wr_cmd == `CMD_CMPXCHG;
wire cond_130 = wr_cmd == `CMD_ENTER && wr_cmdex == `CMDEX_ENTER_FIRST;
wire cond_131 = wr_cmd == `CMD_ENTER && wr_cmdex == `CMDEX_ENTER_LAST;
wire cond_132 = wr_cmd == `CMD_ENTER && (wr_cmdex == `CMDEX_ENTER_PUSH || wr_cmdex == `CMDEX_ENTER_LOOP);
wire cond_133 = wr_cmd == `CMD_IMUL;
wire cond_134 = wr_dst_is_edx_eax;
wire cond_135 = wr_cmd == `CMD_LEAVE;
wire cond_136 = { wr_cmd[6:1], 1'd0 } == `CMD_SHxD;
wire cond_137 = wr_cmd == `CMD_WBINVD && wr_cmdex == `CMDEX_WBINVD_STEP_0;
wire cond_138 = wr_cmd == `CMD_WBINVD && wr_cmdex == `CMDEX_WBINVD_STEP_1;
wire cond_139 = { wr_cmd[6:3], 3'd0 } == `CMD_Arith;
wire cond_140 = wr_cmd[2:0] != 3'b111 && wr_dst_is_memory && ~(write_for_wr_ready);
wire cond_141 = wr_cmd[2:0] != 3'b111;
wire cond_142 = wr_cmd == `CMD_MUL;
wire cond_143 = wr_cmd == `CMD_LOOP;
wire cond_144 = wr_address_16bit;
wire cond_145 = wr_cmd == `CMD_TEST;
wire cond_146 = wr_cmd == `CMD_CLTS;
wire cond_147 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_STEP_1;
wire cond_148 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_STEP_2;
wire cond_149 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_real_STEP_3;
wire cond_150 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_3;
wire cond_151 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_4;
wire cond_152 = wr_cmd == `CMD_LODS;
wire cond_153 = wr_string_ignore || wr_string_finish;
wire cond_154 = ~(wr_string_ignore) && ~(wr_string_finish) && wr_prefix_group_1_rep != 2'd0;
wire cond_155 = wr_cmd == `CMD_XCHG && wr_cmdex == `CMDEX_XCHG_implicit;
wire cond_156 = wr_cmd == `CMD_XCHG && wr_cmdex == `CMDEX_XCHG_modregrm;
wire cond_157 = wr_cmd == `CMD_XCHG && wr_cmdex == `CMDEX_XCHG_modregrm_LAST;
wire cond_158 = wr_cmd == `CMD_PUSH;
wire cond_159 = wr_cmd == `CMD_INT_INTO && wr_cmdex == `CMDEX_INT_INTO_INT_STEP_0;
wire cond_160 = wr_cmd == `CMD_INT_INTO && wr_cmdex == `CMDEX_INT_INTO_INT3_STEP_0;
wire cond_161 = wr_cmd == `CMD_INT_INTO && wr_cmdex == `CMDEX_INT_INTO_INT1_STEP_0;
wire cond_162 = wr_cmd == `CMD_INT_INTO && wr_cmdex == `CMDEX_INT_INTO_INTO_STEP_0;
wire cond_163 = oflag;
wire cond_164 = wr_cmd == `CMD_CPUID;
wire cond_165 = eax == 32'd0;
wire cond_166 = eax == 32'd1;
wire cond_167 = wr_cmd == `CMD_IN;
wire cond_168 = ~(io_allow_check_needed) || wr_cmdex == `CMDEX_IN_protected;
wire cond_169 = wr_cmd == `CMD_NOT;
wire cond_170 = (wr_cmd == `CMD_LAR || wr_cmd == `CMD_LSL || wr_cmd == `CMD_VERR || wr_cmd == `CMD_VERW) && (wr_cmdex == `CMDEX_LAR_LSL_VERR_VERW_STEP_1 || wr_cmdex == `CMDEX_LAR_LSL_VERR_VERW_STEP_2);
wire cond_171 = (wr_cmd == `CMD_LAR || wr_cmd == `CMD_LSL) && wr_cmdex == `CMDEX_LAR_LSL_VERR_VERW_STEP_LAST;
wire cond_172 = wr_dst_is_reg;
wire cond_173 = (wr_cmd == `CMD_VERR || wr_cmd == `CMD_VERW) && wr_cmdex == `CMDEX_LAR_LSL_VERR_VERW_STEP_LAST;
wire cond_174 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_same_STEP_3) || (wr_cmd == `CMD_IRET_2  && wr_cmdex == `CMDEX_IRET_2_protected_same_STEP_0) || (wr_cmd == `CMD_CALL_2  && wr_cmdex == `CMDEX_CALL_2_protected_seg_STEP_3) || (wr_cmd == `CMD_CALL_2  && wr_cmdex == `CMDEX_CALL_2_call_gate_same_STEP_2) || (wr_cmd == `CMD_JMP     && wr_cmdex == `CMDEX_JMP_protected_seg_STEP_0) || (wr_cmd == `CMD_JMP_2   && wr_cmdex == `CMDEX_JMP_2_call_gate_STEP_2) || (wr_cmd == `CMD_int_2   && wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_4);
wire cond_175 = `DESC_IS_NOT_ACCESSED(glob_descriptor);
wire cond_176 = wr_cmd != `CMD_JMP && wr_cmd != `CMD_JMP_2 && wr_cmd != `CMD_int_2;
wire cond_177 = (wr_cmd == `CMD_CALL_3 && wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_9) || (wr_cmd == `CMD_int_3  && wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_4);
wire cond_178 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_same_STEP_4) || (wr_cmd == `CMD_CALL_2  && wr_cmdex == `CMDEX_CALL_2_protected_seg_STEP_4) || (wr_cmd == `CMD_CALL_2  && wr_cmdex == `CMDEX_CALL_2_call_gate_same_STEP_3) || (wr_cmd == `CMD_CALL_3  && wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_10) || (wr_cmd == `CMD_JMP     && wr_cmdex == `CMDEX_JMP_protected_seg_STEP_1) || (wr_cmd == `CMD_JMP_2   && wr_cmdex == `CMDEX_JMP_2_call_gate_STEP_3);
wire cond_179 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_5) || (wr_cmd == `CMD_IRET_2  && wr_cmdex == `CMDEX_IRET_2_protected_outer_STEP_3);
wire cond_180 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_6) || (wr_cmd == `CMD_IRET_2  && wr_cmdex == `CMDEX_IRET_2_protected_outer_STEP_5) || (wr_cmd == `CMD_CALL_3  && wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_8) || (wr_cmd == `CMD_int_3   && wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_5);
wire cond_181 = `DESC_IS_NOT_ACCESSED(glob_descriptor) && glob_param_1[15:2] != 14'd0;
wire cond_182 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_7) ||  + (wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_outer_STEP_6);
wire cond_183 = (wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_protected_STEP_0 || wr_cmdex == `CMDEX_CALL_protected_STEP_1)) || (wr_cmd == `CMD_JMP  && (wr_cmdex == `CMDEX_JMP_protected_STEP_0  || wr_cmdex == `CMDEX_JMP_protected_STEP_1));
wire cond_184 = (wr_cmd == `CMD_CALL_2 && wr_cmdex == `CMDEX_CALL_2_task_gate_STEP_0) || (wr_cmd == `CMD_JMP    && wr_cmdex == `CMDEX_JMP_task_gate_STEP_0) || (wr_cmd == `CMD_int    && wr_cmdex == `CMDEX_int_task_gate_STEP_0);
wire cond_185 = (wr_cmd == `CMD_CALL_2 && wr_cmdex == `CMDEX_CALL_2_task_gate_STEP_1) || (wr_cmd == `CMD_JMP    && wr_cmdex == `CMDEX_JMP_task_gate_STEP_1) || (wr_cmd == `CMD_int    && wr_cmdex == `CMDEX_int_task_gate_STEP_1);
wire cond_186 = (wr_cmd == `CMD_CALL_2 && wr_cmdex == `CMDEX_CALL_2_call_gate_STEP_0) || (wr_cmd == `CMD_int    && wr_cmdex == `CMDEX_int_int_trap_gate_STEP_0);
wire cond_187 = (wr_cmd == `CMD_CALL_2 && wr_cmdex == `CMDEX_CALL_2_call_gate_STEP_1) || (wr_cmd == `CMD_int    && wr_cmdex == `CMDEX_int_int_trap_gate_STEP_1);
wire cond_188 = (wr_cmd == `CMD_CALL_2 && wr_cmdex == `CMDEX_CALL_2_call_gate_STEP_2) || (wr_cmd == `CMD_int    && wr_cmdex == `CMDEX_int_int_trap_gate_STEP_2);
wire cond_189 = (wr_cmd == `CMD_CALL_2 && (wr_cmdex == `CMDEX_CALL_2_call_gate_same_STEP_0 || wr_cmdex == `CMDEX_CALL_2_call_gate_same_STEP_1)) || (wr_cmd == `CMD_int_2 && (wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_0 || wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_1 || wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_2 || wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_3));
wire cond_190 = (wr_cmd == `CMD_CALL_2 && wr_cmdex == `CMDEX_CALL_2_call_gate_more_STEP_0) || (wr_cmd == `CMD_int_2  && wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_0);
wire cond_191 = (wr_cmd == `CMD_CALL_2 && wr_cmdex == `CMDEX_CALL_2_call_gate_more_STEP_1) || (wr_cmd == `CMD_int_2  && wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_1);
wire cond_192 = wr_cmd == `CMD_STOS;
wire cond_193 = ~(wr_string_es_fault);
wire cond_194 = wr_string_finish;
wire cond_195 = wr_string_ignore;
wire cond_196 = wr_cmd == `CMD_INS;
wire cond_197 = wr_cmdex == `CMDEX_INS_real_1 || wr_cmdex == `CMDEX_INS_protected_1;
wire cond_198 = wr_string_finish || wr_prefix_group_1_rep == 2'd0;
wire cond_199 = wr_cmd == `CMD_OUTS;
wire cond_200 = io_allow_check_needed && wr_cmdex == `CMDEX_OUTS_first;
wire cond_201 = ~(write_io_for_wr_ready);
wire cond_202 = wr_cmd == `CMD_PUSHF;
wire cond_203 = wr_cmd == `CMD_JMP && (wr_cmdex == `CMDEX_JMP_Jv_STEP_0 || wr_cmdex == `CMDEX_JMP_Ev_STEP_0);
wire cond_204 = wr_cmd == `CMD_JMP && (wr_cmdex == `CMDEX_JMP_Ev_Jv_STEP_1 || wr_cmdex == `CMDEX_JMP_real_v8086_STEP_1);
wire cond_205 = wr_cmd == `CMD_JMP && (wr_cmdex == `CMDEX_JMP_Ep_STEP_0 || wr_cmdex == `CMDEX_JMP_Ap_STEP_0 ||  +  wr_cmdex == `CMDEX_JMP_Ep_STEP_1 || wr_cmdex == `CMDEX_JMP_Ap_STEP_1);
wire cond_206 = wr_cmd == `CMD_JMP && wr_cmdex == `CMDEX_JMP_real_v8086_STEP_0;
wire cond_207 = wr_cmd == `CMD_JMP && wr_cmdex == `CMDEX_JMP_task_switch_STEP_0;
wire cond_208 = wr_cmd == `CMD_JMP_2 && wr_cmdex == `CMDEX_JMP_2_call_gate_STEP_0;
wire cond_209 = wr_cmd == `CMD_JMP_2 && wr_cmdex == `CMDEX_JMP_2_call_gate_STEP_1;
wire cond_210 = wr_cmd == `CMD_OUT;
wire cond_211 = ~(io_allow_check_needed) || wr_cmdex == `CMDEX_OUT_protected;
wire cond_212 = wr_cmd == `CMD_MOV;
wire cond_213 = wr_cmd == `CMD_LAHF;
wire cond_214 = wr_cmd == `CMD_CBW;
wire cond_215 = wr_cmd == `CMD_CWD;
wire cond_216 = wr_cmd == `CMD_POPF && wr_cmdex == `CMDEX_POPF_STEP_0;
wire cond_217 = (protected_mode && cpl == 2'd0) || real_mode;
wire cond_218 = (protected_mode && cpl <= iopl) || v8086_mode || real_mode;
wire cond_219 = wr_cmd == `CMD_CLI;
wire cond_220 = wr_cmd == `CMD_STI;
wire cond_221 = iflag == `FALSE;
wire cond_222 = wr_cmd == `CMD_BOUND && wr_cmdex == `CMDEX_BOUND_STEP_FIRST;
wire cond_223 = wr_cmd == `CMD_SALC && wr_cmdex == `CMDEX_SALC_STEP_0;
wire cond_224 = cflag;
wire cond_225 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_1;
wire cond_226 = wr_cmd == `CMD_task_switch && (wr_cmdex == `CMDEX_task_switch_STEP_2 || wr_cmdex == `CMDEX_task_switch_STEP_3 || wr_cmdex == `CMDEX_task_switch_STEP_4 || wr_cmdex == `CMDEX_task_switch_STEP_5);
wire cond_227 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_6;
wire cond_228 = glob_param_1[`TASK_SWITCH_SOURCE_BITS] == `TASK_SWITCH_FROM_JUMP || glob_param_1[`TASK_SWITCH_SOURCE_BITS] == `TASK_SWITCH_FROM_IRET;
wire cond_229 = wr_cmd == `CMD_task_switch && (wr_cmdex == `CMDEX_task_switch_STEP_7 || wr_cmdex == `CMDEX_task_switch_STEP_8);
wire cond_230 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_9;
wire cond_231 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_10;
wire cond_232 = wr_cmd == `CMD_task_switch_2 && wr_cmdex <= `CMDEX_task_switch_2_STEP_13;
wire cond_233 = tr_cache[`DESC_BITS_TYPE] > 4'd3 || wr_cmdex <= `CMDEX_task_switch_2_STEP_11;
wire cond_234 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_11;
wire cond_235 = glob_param_1[`TASK_SWITCH_SOURCE_BITS] == `TASK_SWITCH_FROM_CALL || glob_param_1[`TASK_SWITCH_SOURCE_BITS] == `TASK_SWITCH_FROM_INT;
wire cond_236 = wr_cmd == `CMD_task_switch && wr_cmdex >= `CMDEX_task_switch_STEP_12 && wr_cmdex <= `CMDEX_task_switch_STEP_14;
wire cond_237 = wr_cmd == `CMD_task_switch_3;
wire cond_238 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_0;
wire cond_239 = glob_param_1[`TASK_SWITCH_SOURCE_BITS] != `TASK_SWITCH_FROM_IRET;
wire cond_240 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_1;
wire cond_241 = glob_descriptor[`DESC_BITS_TYPE] >= 4'd9 && cr0_pg && cr3 != exe_buffer_shifted[463:432];
wire cond_242 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_2;
wire cond_243 = glob_param_2[2:0] == 3'b000;
wire cond_244 = wr_cmd == `CMD_task_switch_4 && wr_cmdex >= `CMDEX_task_switch_4_STEP_3 && wr_cmdex <= `CMDEX_task_switch_4_STEP_8;
wire cond_245 = wr_cmdex == `CMDEX_task_switch_4_STEP_3;
wire cond_246 = glob_param_2[1:0] == 2'b00 && ~(v8086_mode) && `DESC_IS_NOT_ACCESSED(glob_descriptor);
wire cond_247 = wr_cmdex == `CMDEX_task_switch_4_STEP_4;
wire cond_248 = wr_cmdex == `CMDEX_task_switch_4_STEP_5;
wire cond_249 = wr_cmdex == `CMDEX_task_switch_4_STEP_6;
wire cond_250 = wr_cmdex == `CMDEX_task_switch_4_STEP_7;
wire cond_251 = glob_param_2[1:0] == 2'b00 && `DESC_IS_ACCESSED(glob_descriptor);
wire cond_252 = glob_param_2[1:0] != 2'b00;
wire cond_253 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_9;
wire cond_254 = glob_param_3[16];
wire cond_255 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_10;
wire cond_256 = glob_param_3[17] && task_trap[0];
wire cond_257 = wr_cmd == `CMD_LEA;
wire cond_258 = (wr_cmd == `CMD_SGDT || wr_cmd == `CMD_SIDT);
wire cond_259 = wr_cmdex == `CMDEX_SGDT_SIDT_STEP_1;
wire cond_260 = wr_cmdex == `CMDEX_SGDT_SIDT_STEP_2;
wire cond_261 = wr_cmd == `CMD_MOVS;
wire cond_262 = wr_cmd == `CMD_MOVSX || wr_cmd == `CMD_MOVZX;
wire cond_263 = wr_cmd == `CMD_POPA;
wire cond_264 = wr_cmdex[2:0] == 3'd7;
wire cond_265 = wr_cmd == `CMD_debug_reg && wr_cmdex == `CMDEX_debug_reg_MOV_store_STEP_0;
wire cond_266 = wr_cmd == `CMD_debug_reg && wr_cmdex == `CMDEX_debug_reg_MOV_load_STEP_0;
wire cond_267 = wr_decoder[13:11] == 3'd1;
wire cond_268 = (wr_decoder[13:11] == 3'd4 || wr_decoder[13:11] == 3'd6);
wire cond_269 = (wr_decoder[13:11] == 3'd5 || wr_decoder[13:11] == 3'd7);
wire cond_270 = wr_cmd == `CMD_debug_reg && wr_cmdex == `CMDEX_debug_reg_MOV_load_STEP_1;
wire cond_271 = wr_cmd == `CMD_XLAT;
wire cond_272 = wr_cmd == `CMD_AAA || wr_cmd == `CMD_AAS;
wire cond_273 = wr_cmd == `CMD_DAA || wr_cmd == `CMD_DAS;
wire cond_274 = { wr_cmd[6:1], 1'd0 } == `CMD_BSx;
wire cond_275 = eax > 32'd1;
assign wr_glob_param_1_set =
    (cond_240)? (`TRUE) :
    (cond_242)? (`TRUE) :
    (cond_244 && cond_246 && ~cond_9 && cond_245)? (`TRUE) :
    (cond_244 && cond_246 && ~cond_9 && cond_247)? (`TRUE) :
    (cond_244 && cond_246 && ~cond_9 && cond_248)? (`TRUE) :
    (cond_244 && cond_246 && ~cond_9 && cond_249)? (`TRUE) :
    (cond_244 && cond_246 && ~cond_9 && cond_250)? (`TRUE) :
    (cond_244 && cond_251 && cond_245)? (`TRUE) :
    (cond_244 && cond_251 && cond_247)? (`TRUE) :
    (cond_244 && cond_251 && cond_248)? (`TRUE) :
    (cond_244 && cond_251 && cond_249)? (`TRUE) :
    (cond_244 && cond_251 && cond_250)? (`TRUE) :
    (cond_244 && cond_252 && cond_245)? (`TRUE) :
    (cond_244 && cond_252 && cond_247)? (`TRUE) :
    (cond_244 && cond_252 && cond_248)? (`TRUE) :
    (cond_244 && cond_252 && cond_249)? (`TRUE) :
    (cond_244 && cond_252 && cond_250)? (`TRUE) :
    1'd0;
assign wr_glob_param_1_value =
    (cond_240)? ( (glob_descriptor[`DESC_BITS_TYPE] <= 4'd3)? { 13'd0, `SEGMENT_LDT, exe_buffer_shifted[47:32] } : { 13'd0, `SEGMENT_LDT, exe_buffer_shifted[15:0] }) :
    (cond_242)? ( { 13'd0, `SEGMENT_SS, task_ss }) :
    (cond_244 && cond_246 && ~cond_9 && cond_245)? ( { 13'd0, `SEGMENT_DS, task_ds }) :
    (cond_244 && cond_246 && ~cond_9 && cond_247)? ( { 13'd0, `SEGMENT_ES, task_es }) :
    (cond_244 && cond_246 && ~cond_9 && cond_248)? ( { 13'd0, `SEGMENT_FS, glob_param_4[31:16] }) :
    (cond_244 && cond_246 && ~cond_9 && cond_249)? ( { 13'd0, `SEGMENT_GS, glob_param_4[15:0] }) :
    (cond_244 && cond_246 && ~cond_9 && cond_250)? ( { 13'd0, `SEGMENT_CS, task_cs }) :
    (cond_244 && cond_251 && cond_245)? ( { 13'd0, `SEGMENT_DS, task_ds }) :
    (cond_244 && cond_251 && cond_247)? ( { 13'd0, `SEGMENT_ES, task_es }) :
    (cond_244 && cond_251 && cond_248)? ( { 13'd0, `SEGMENT_FS, glob_param_4[31:16] }) :
    (cond_244 && cond_251 && cond_249)? ( { 13'd0, `SEGMENT_GS, glob_param_4[15:0] }) :
    (cond_244 && cond_251 && cond_250)? ( { 13'd0, `SEGMENT_CS, task_cs }) :
    (cond_244 && cond_252 && cond_245)? ( { 13'd0, `SEGMENT_DS, task_ds }) :
    (cond_244 && cond_252 && cond_247)? ( { 13'd0, `SEGMENT_ES, task_es }) :
    (cond_244 && cond_252 && cond_248)? ( { 13'd0, `SEGMENT_FS, glob_param_4[31:16] }) :
    (cond_244 && cond_252 && cond_249)? ( { 13'd0, `SEGMENT_GS, glob_param_4[15:0] }) :
    (cond_244 && cond_252 && cond_250)? ( { 13'd0, `SEGMENT_CS, task_cs }) :
    32'd0;
