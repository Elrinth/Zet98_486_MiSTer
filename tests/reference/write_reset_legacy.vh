/*
 * Copyright (c) 2014, Aleksander Osman
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * 
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
// Original ao486 reset decoder; oracle for reset predecode equivalence.
wire cond_4 = wr_cmd == `CMD_JCXZ;
wire cond_5 = result_signals[0];
wire cond_9 = ~(write_for_wr_ready);
wire cond_12 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_Ev_Jv_STEP_1 || wr_cmdex == `CMDEX_CALL_real_v8086_STEP_3);
wire cond_25 = wr_cmd == `CMD_Jcc;
wire cond_27 = wr_cmd == `CMD_INVD && wr_cmdex == `CMDEX_INVD_STEP_1;
wire cond_29 = wr_cmd == `CMD_INVLPG && wr_cmdex == `CMDEX_INVLPG_STEP_1;
wire cond_32 = wr_cmd == `CMD_SCAS;
wire cond_33 = ~(wr_string_ignore);
wire cond_35 = wr_string_ignore || wr_string_zf_finish;
wire cond_38 = wr_cmd == `CMD_RET_near && wr_cmdex != `CMDEX_RET_near_LAST;
wire cond_42 = wr_cmd == `CMD_LxS && wr_cmdex == `CMDEX_LxS_STEP_LAST;
wire cond_44 = (wr_cmd == `CMD_MOV_to_seg || wr_cmd == `CMD_LLDT || wr_cmd == `CMD_LTR) && wr_cmdex == `CMDEX_MOV_to_seg_LLDT_LTR_STEP_LAST;
wire cond_60 = wr_cmd == `CMD_int && wr_cmdex == `CMDEX_int_real_STEP_5;
wire cond_62 = wr_cmd == `CMD_int_2 && wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_5;
wire cond_63 = wr_cmd == `CMD_int_3 && wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_6;
wire cond_76 = wr_cmd == `CMD_POP_seg && wr_cmdex == `CMDEX_POP_seg_STEP_LAST;
wire cond_82 = wr_cmd == `CMD_IRET && wr_cmdex == `CMDEX_IRET_real_v86_STEP_3;
wire cond_88 = wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_to_v86_STEP_6;
wire cond_89 = wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_same_STEP_1;
wire cond_107 = wr_cmd == `CMD_CMPS && wr_cmdex == `CMDEX_CMPS_LAST;
wire cond_108 = wr_string_ignore || wr_string_zf_finish || wr_prefix_group_1_rep == 2'd0;
wire cond_110 = wr_cmd == `CMD_control_reg && wr_cmdex == `CMDEX_control_reg_LMSW_STEP_0;
wire cond_113 = wr_cmd == `CMD_control_reg && wr_cmdex == `CMDEX_control_reg_MOV_load_STEP_0;
wire cond_119 = (wr_cmd == `CMD_LGDT || wr_cmd == `CMD_LIDT);
wire cond_123 = wr_cmdex == `CMDEX_LGDT_LIDT_STEP_2;
wire cond_138 = wr_cmd == `CMD_WBINVD && wr_cmdex == `CMDEX_WBINVD_STEP_1;
wire cond_143 = wr_cmd == `CMD_LOOP;
wire cond_146 = wr_cmd == `CMD_CLTS;
wire cond_149 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_real_STEP_3;
wire cond_152 = wr_cmd == `CMD_LODS;
wire cond_153 = wr_string_ignore || wr_string_finish;
wire cond_162 = wr_cmd == `CMD_INT_INTO && wr_cmdex == `CMDEX_INT_INTO_INTO_STEP_0;
wire cond_163 = oflag;
wire cond_164 = wr_cmd == `CMD_CPUID;
wire cond_167 = wr_cmd == `CMD_IN;
wire cond_168 = ~(io_allow_check_needed) || wr_cmdex == `CMDEX_IN_protected;
wire cond_178 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_same_STEP_4) || (wr_cmd == `CMD_CALL_2  && wr_cmdex == `CMDEX_CALL_2_protected_seg_STEP_4) || (wr_cmd == `CMD_CALL_2  && wr_cmdex == `CMDEX_CALL_2_call_gate_same_STEP_3) || (wr_cmd == `CMD_CALL_3  && wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_10) || (wr_cmd == `CMD_JMP     && wr_cmdex == `CMDEX_JMP_protected_seg_STEP_1) || (wr_cmd == `CMD_JMP_2   && wr_cmdex == `CMDEX_JMP_2_call_gate_STEP_3);
wire cond_182 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_7) ||  + (wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_outer_STEP_6);
wire cond_192 = wr_cmd == `CMD_STOS;
wire cond_194 = wr_string_finish;
wire cond_195 = wr_string_ignore;
wire cond_196 = wr_cmd == `CMD_INS;
wire cond_197 = wr_cmdex == `CMDEX_INS_real_1 || wr_cmdex == `CMDEX_INS_protected_1;
wire cond_198 = wr_string_finish || wr_prefix_group_1_rep == 2'd0;
wire cond_199 = wr_cmd == `CMD_OUTS;
wire cond_200 = io_allow_check_needed && wr_cmdex == `CMDEX_OUTS_first;
wire cond_201 = ~(write_io_for_wr_ready);
wire cond_204 = wr_cmd == `CMD_JMP && (wr_cmdex == `CMDEX_JMP_Ev_Jv_STEP_1 || wr_cmdex == `CMDEX_JMP_real_v8086_STEP_1);
wire cond_210 = wr_cmd == `CMD_OUT;
wire cond_211 = ~(io_allow_check_needed) || wr_cmdex == `CMDEX_OUT_protected;
wire cond_216 = wr_cmd == `CMD_POPF && wr_cmdex == `CMDEX_POPF_STEP_0;
wire cond_255 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_10;
wire cond_261 = wr_cmd == `CMD_MOVS;
wire cond_270 = wr_cmd == `CMD_debug_reg && wr_cmdex == `CMDEX_debug_reg_MOV_load_STEP_1;
assign wr_req_reset_pr =
    (cond_4 && cond_5)? (`TRUE) :
    (cond_12)? (`TRUE) :
    (cond_25 && cond_5)? (`TRUE) :
    (cond_38)? (`TRUE) :
    (cond_60)? (`TRUE) :
    (cond_62)? (`TRUE) :
    (cond_63)? (`TRUE) :
    (cond_82)? (`TRUE) :
    (cond_88)? (`TRUE) :
    (cond_89)? (`TRUE) :
    (cond_110)? (`TRUE) :
    (cond_113)? (`TRUE) :
    (cond_143 && cond_5)? (`TRUE) :
    (cond_149)? (`TRUE) :
    (cond_178)? (`TRUE) :
    (cond_182)? (`TRUE) :
    (cond_204)? (`TRUE) :
    (cond_255)? (`TRUE) :
    1'd0;
assign wr_req_reset_rd =
    (cond_4 && cond_5)? (`TRUE) :
    (cond_12)? (`TRUE) :
    (cond_25 && cond_5)? (`TRUE) :
    (cond_27)? (`TRUE) :
    (cond_29)? (`TRUE) :
    (cond_32 && cond_35)? (`TRUE) :
    (cond_38)? (`TRUE) :
    (cond_42)? (`TRUE) :
    (cond_44)? (`TRUE) :
    (cond_60)? (`TRUE) :
    (cond_62)? (`TRUE) :
    (cond_63)? (`TRUE) :
    (cond_76)? (`TRUE) :
    (cond_82)? (`TRUE) :
    (cond_88)? (`TRUE) :
    (cond_89)? (`TRUE) :
    (cond_107 && cond_108)? (`TRUE) :
    (cond_110)? (`TRUE) :
    (cond_113)? (`TRUE) :
    (cond_119 && cond_123)? (`TRUE) :
    (cond_138)? (`TRUE) :
    (cond_143 && cond_5)? (`TRUE) :
    (cond_146)? (`TRUE) :
    (cond_149)? (`TRUE) :
    (cond_152 && cond_153)? (`TRUE) :
    (cond_162 && ~cond_163)? (`TRUE) :
    (cond_164)? (`TRUE) :
    (cond_167 && cond_168)? (`TRUE) :
    (cond_178)? (`TRUE) :
    (cond_182)? (`TRUE) :
    (cond_192 && cond_33 && ~cond_9 && cond_194)? (`TRUE) :
    (cond_192 && cond_195)? (`TRUE) :
    (cond_196 && ~cond_197 && cond_33 && ~cond_9 && cond_198)? (`TRUE) :
    (cond_196 && ~cond_197 && cond_195)? (`TRUE) :
    (cond_199 && ~cond_200 && cond_33 && ~cond_201 && cond_198)? (`TRUE) :
    (cond_199 && ~cond_200 && cond_195)? (`TRUE) :
    (cond_204)? (`TRUE) :
    (cond_210 && cond_211 && ~cond_201)? (`TRUE) :
    (cond_216)? (`TRUE) :
    (cond_255)? (`TRUE) :
    (cond_261 && cond_33 && ~cond_9 && cond_194)? (`TRUE) :
    (cond_261 && cond_195)? (`TRUE) :
    (cond_270)? (`TRUE) :
    1'd0;
assign wr_req_reset_dec =
    (cond_4 && cond_5)? (`TRUE) :
    (cond_12)? (`TRUE) :
    (cond_25 && cond_5)? (`TRUE) :
    (cond_38)? (`TRUE) :
    (cond_60)? (`TRUE) :
    (cond_62)? (`TRUE) :
    (cond_63)? (`TRUE) :
    (cond_82)? (`TRUE) :
    (cond_88)? (`TRUE) :
    (cond_89)? (`TRUE) :
    (cond_110)? (`TRUE) :
    (cond_113)? (`TRUE) :
    (cond_143 && cond_5)? (`TRUE) :
    (cond_149)? (`TRUE) :
    (cond_178)? (`TRUE) :
    (cond_182)? (`TRUE) :
    (cond_204)? (`TRUE) :
    (cond_255)? (`TRUE) :
    1'd0;
assign wr_req_reset_exe =
    (cond_4 && cond_5)? (`TRUE) :
    (cond_12)? (`TRUE) :
    (cond_25 && cond_5)? (`TRUE) :
    (cond_27)? (`TRUE) :
    (cond_29)? (`TRUE) :
    (cond_32 && cond_35)? (`TRUE) :
    (cond_38)? (`TRUE) :
    (cond_42)? (`TRUE) :
    (cond_44)? (`TRUE) :
    (cond_60)? (`TRUE) :
    (cond_62)? (`TRUE) :
    (cond_63)? (`TRUE) :
    (cond_76)? (`TRUE) :
    (cond_82)? (`TRUE) :
    (cond_88)? (`TRUE) :
    (cond_89)? (`TRUE) :
    (cond_107 && cond_108)? (`TRUE) :
    (cond_110)? (`TRUE) :
    (cond_113)? (`TRUE) :
    (cond_119 && cond_123)? (`TRUE) :
    (cond_138)? (`TRUE) :
    (cond_143 && cond_5)? (`TRUE) :
    (cond_146)? (`TRUE) :
    (cond_149)? (`TRUE) :
    (cond_152 && cond_153)? (`TRUE) :
    (cond_162 && ~cond_163)? (`TRUE) :
    (cond_164)? (`TRUE) :
    (cond_167 && cond_168)? (`TRUE) :
    (cond_178)? (`TRUE) :
    (cond_182)? (`TRUE) :
    (cond_192 && cond_33 && ~cond_9 && cond_194)? (`TRUE) :
    (cond_192 && cond_195)? (`TRUE) :
    (cond_196 && ~cond_197 && cond_33 && ~cond_9 && cond_198)? (`TRUE) :
    (cond_196 && ~cond_197 && cond_195)? (`TRUE) :
    (cond_199 && ~cond_200 && cond_33 && ~cond_201 && cond_198)? (`TRUE) :
    (cond_199 && ~cond_200 && cond_195)? (`TRUE) :
    (cond_204)? (`TRUE) :
    (cond_210 && cond_211 && ~cond_201)? (`TRUE) :
    (cond_216)? (`TRUE) :
    (cond_255)? (`TRUE) :
    (cond_261 && cond_33 && ~cond_9 && cond_194)? (`TRUE) :
    (cond_261 && cond_195)? (`TRUE) :
    (cond_270)? (`TRUE) :
    1'd0;
assign wr_req_reset_micro =
    (cond_4 && cond_5)? (`TRUE) :
    (cond_12)? (`TRUE) :
    (cond_25 && cond_5)? (`TRUE) :
    (cond_27)? (`TRUE) :
    (cond_29)? (`TRUE) :
    (cond_32 && cond_35)? (`TRUE) :
    (cond_38)? (`TRUE) :
    (cond_42)? (`TRUE) :
    (cond_44)? (`TRUE) :
    (cond_60)? (`TRUE) :
    (cond_62)? (`TRUE) :
    (cond_63)? (`TRUE) :
    (cond_76)? (`TRUE) :
    (cond_82)? (`TRUE) :
    (cond_88)? (`TRUE) :
    (cond_89)? (`TRUE) :
    (cond_107 && cond_108)? (`TRUE) :
    (cond_110)? (`TRUE) :
    (cond_113)? (`TRUE) :
    (cond_119 && cond_123)? (`TRUE) :
    (cond_138)? (`TRUE) :
    (cond_143 && cond_5)? (`TRUE) :
    (cond_146)? (`TRUE) :
    (cond_149)? (`TRUE) :
    (cond_152 && cond_153)? (`TRUE) :
    (cond_162 && ~cond_163)? (`TRUE) :
    (cond_164)? (`TRUE) :
    (cond_167 && cond_168)? (`TRUE) :
    (cond_178)? (`TRUE) :
    (cond_182)? (`TRUE) :
    (cond_192 && cond_33 && ~cond_9 && cond_194)? (`TRUE) :
    (cond_192 && cond_195)? (`TRUE) :
    (cond_196 && ~cond_197 && cond_33 && ~cond_9 && cond_198)? (`TRUE) :
    (cond_196 && ~cond_197 && cond_195)? (`TRUE) :
    (cond_199 && ~cond_200 && cond_33 && ~cond_201 && cond_198)? (`TRUE) :
    (cond_199 && ~cond_200 && cond_195)? (`TRUE) :
    (cond_204)? (`TRUE) :
    (cond_210 && cond_211 && ~cond_201)? (`TRUE) :
    (cond_216)? (`TRUE) :
    (cond_255)? (`TRUE) :
    (cond_261 && cond_33 && ~cond_9 && cond_194)? (`TRUE) :
    (cond_261 && cond_195)? (`TRUE) :
    (cond_270)? (`TRUE) :
    1'd0;
