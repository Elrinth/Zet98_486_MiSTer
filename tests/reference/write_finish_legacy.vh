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
wire [15:0] wr_IRET_to_v86_es;
wire [15:0] wr_IRET_to_v86_cs;
wire [15:0] wr_IRET_to_v86_ss;
wire [15:0] wr_IRET_to_v86_ds;
wire [15:0] wr_IRET_to_v86_fs;
wire [15:0] wr_IRET_to_v86_gs;
assign wr_IRET_to_v86_es = exe_buffer_shifted[79:64];
assign wr_IRET_to_v86_cs = glob_param_1[15:0];
assign wr_IRET_to_v86_ss = exe_buffer_shifted[111:96];
assign wr_IRET_to_v86_ds = exe_buffer_shifted[47:32];
assign wr_IRET_to_v86_fs = exe_buffer_shifted[15:0];
assign wr_IRET_to_v86_gs = exe_buffer[15:0];

wire [31:0] wr_ecx_minus_1;
assign wr_ecx_minus_1 = ecx - 32'd1;

wire [31:0] wr_task_switch_linear;
wire [31:0] wr_task_switch_linear_next;
reg  [31:0] wr_task_switch_linear_reg;
assign wr_task_switch_linear = (wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_9 && tr_cache[`DESC_BITS_TYPE] <= 4'd3)?     tr_base + 32'd14 : (wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_9 && tr_cache[`DESC_BITS_TYPE] > 4'd3)?      tr_base + 32'h20 : wr_task_switch_linear_next;
assign wr_task_switch_linear_next = (tr_cache[`DESC_BITS_TYPE] <= 4'd3)?    wr_task_switch_linear_reg + 32'd2 : wr_task_switch_linear_reg + 32'd4;
always @(posedge clk) begin if(rst_n == 1'b0)                                                               wr_task_switch_linear_reg <= 32'd0; else if(wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_9)    wr_task_switch_linear_reg <= wr_task_switch_linear; else if(wr_ready)                                                               wr_task_switch_linear_reg <= wr_task_switch_linear_next;
end


wire cond_0 = wr_cmd == `CMD_XADD && wr_cmdex == `CMDEX_XADD_FIRST;
wire cond_6 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_Ep_STEP_0 || wr_cmdex == `CMDEX_CALL_Ap_STEP_0);
wire cond_7 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_Ep_STEP_1 || wr_cmdex == `CMDEX_CALL_Ap_STEP_1);
wire cond_8 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_real_v8086_STEP_0 || wr_cmdex == `CMDEX_CALL_real_v8086_STEP_1);
wire cond_9 = ~(write_for_wr_ready);
wire cond_11 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_Ev_STEP_0 || wr_cmdex == `CMDEX_CALL_Jv_STEP_0);
wire cond_13 = wr_cmd == `CMD_CALL && wr_cmdex == `CMDEX_CALL_real_v8086_STEP_2;
wire cond_14 = wr_cmd == `CMD_CALL && (wr_cmdex == `CMDEX_CALL_protected_seg_STEP_0 || wr_cmdex == `CMDEX_CALL_protected_seg_STEP_1);
wire cond_16 = wr_cmd == `CMD_CALL && wr_cmdex == `CMDEX_CALL_protected_seg_STEP_2;
wire cond_17 = wr_cmd == `CMD_CALL_2 && wr_cmdex == `CMDEX_CALL_2_task_switch_STEP_0;
wire cond_18 = wr_cmd == `CMD_CALL_2 && (wr_cmdex == `CMDEX_CALL_2_call_gate_more_STEP_2 || wr_cmdex == `CMDEX_CALL_2_call_gate_more_STEP_3);
wire cond_19 = wr_cmd == `CMD_CALL_3 && ( wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_4 || wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_5 || wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_6 || wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_7);
wire cond_26 = wr_cmd == `CMD_INVD && wr_cmdex == `CMDEX_INVD_STEP_0;
wire cond_28 = wr_cmd == `CMD_INVLPG && wr_cmdex == `CMDEX_INVLPG_STEP_0;
wire cond_30 = wr_cmd == `CMD_io_allow && (wr_cmdex == `CMDEX_io_allow_1 || wr_cmdex == `CMDEX_io_allow_2);
wire cond_31 = wr_cmd == `CMD_HLT && wr_cmdex == `CMDEX_HLT_STEP_0;
wire cond_32 = wr_cmd == `CMD_SCAS;
wire cond_33 = ~(wr_string_ignore);
wire cond_34 = wr_prefix_group_1_rep != 2'd0;
wire cond_36 = ~(wr_string_ignore) && ~(wr_string_zf_finish) && wr_prefix_group_1_rep != 2'd0;
wire cond_41 = wr_cmd == `CMD_LxS && wr_cmdex != `CMDEX_LxS_STEP_LAST;
wire cond_43 = (wr_cmd == `CMD_MOV_to_seg || wr_cmd == `CMD_LLDT || wr_cmd == `CMD_LTR) && wr_cmdex == `CMDEX_MOV_to_seg_LLDT_LTR_STEP_1;
wire cond_52 = wr_cmd == `CMD_int_2  && wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_2;
wire cond_53 = wr_cmd == `CMD_int_2  && wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_3;
wire cond_54 = wr_cmd == `CMD_int_2 && ( wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_4 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_5 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_6 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_7 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_8 || wr_cmdex == `CMDEX_int_2_int_trap_gate_more_STEP_9);
wire cond_55 = wr_cmd == `CMD_int_3 && ( wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_0 || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_1 || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_2 || wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_3);
wire cond_57 = wr_cmd == `CMD_int && wr_cmdex == `CMDEX_int_STEP_0;
wire cond_58 = wr_cmd == `CMD_int && wr_cmdex == `CMDEX_int_STEP_1;
wire cond_59 = wr_cmd == `CMD_int && (wr_cmdex == `CMDEX_int_real_STEP_3 || wr_cmdex == `CMDEX_int_real_STEP_4);
wire cond_61 = wr_cmd == `CMD_int && (wr_cmdex == `CMDEX_int_protected_STEP_0 || wr_cmdex == `CMDEX_int_protected_STEP_1 || wr_cmdex == `CMDEX_int_protected_STEP_2);
wire cond_65 = wr_cmd == `CMD_int && (wr_cmdex == `CMDEX_int_real_STEP_0 || wr_cmdex == `CMDEX_int_real_STEP_1 || wr_cmdex == `CMDEX_int_real_STEP_2);
wire cond_67 = wr_cmd == `CMD_load_seg && wr_cmdex == `CMDEX_load_seg_STEP_1;
wire cond_70 = wr_cmd == `CMD_load_seg && wr_cmdex == `CMDEX_load_seg_STEP_2;
wire cond_75 = wr_cmd == `CMD_POP_seg && wr_cmdex == `CMDEX_POP_seg_STEP_1;
wire cond_80 = wr_cmd == `CMD_IRET && wr_cmdex <= `CMDEX_IRET_real_v86_STEP_2;
wire cond_84 = wr_cmd == `CMD_IRET && (wr_cmdex == `CMDEX_IRET_protected_STEP_0 || wr_cmdex == `CMDEX_IRET_task_switch_STEP_0 || wr_cmdex == `CMDEX_IRET_task_switch_STEP_1);
wire cond_85 = wr_cmd == `CMD_IRET && wr_cmdex >= `CMDEX_IRET_protected_STEP_1 && wr_cmdex <= `CMDEX_IRET_protected_STEP_3;
wire cond_86 = wr_cmd == `CMD_IRET && wr_cmdex >= `CMDEX_IRET_protected_to_v86_STEP_0 && wr_cmdex <= `CMDEX_IRET_protected_to_v86_STEP_4;
wire cond_87 = wr_cmd == `CMD_IRET && wr_cmdex == `CMDEX_IRET_protected_to_v86_STEP_5;
wire cond_92 = wr_cmd == `CMD_IRET_2 && wr_cmdex >= `CMDEX_IRET_2_protected_outer_STEP_0 && wr_cmdex <= `CMDEX_IRET_2_protected_outer_STEP_2;
wire cond_93 = wr_cmd == `CMD_IRET_2 && wr_cmdex == `CMDEX_IRET_2_protected_outer_STEP_4;
wire cond_97 = wr_cmd == `CMD_POP && wr_cmdex == `CMDEX_POP_modregrm_STEP_0;
wire cond_106 = wr_cmd == `CMD_CMPS && wr_cmdex == `CMDEX_CMPS_FIRST;
wire cond_107 = wr_cmd == `CMD_CMPS && wr_cmdex == `CMDEX_CMPS_LAST;
wire cond_119 = (wr_cmd == `CMD_LGDT || wr_cmd == `CMD_LIDT);
wire cond_120 = wr_cmdex == `CMDEX_LGDT_LIDT_STEP_1;
wire cond_123 = wr_cmdex == `CMDEX_LGDT_LIDT_STEP_2;
wire cond_124 = wr_cmd == `CMD_PUSHA;
wire cond_126 = wr_cmdex[2:0] < 3'd7;
wire cond_130 = wr_cmd == `CMD_ENTER && wr_cmdex == `CMDEX_ENTER_FIRST;
wire cond_132 = wr_cmd == `CMD_ENTER && (wr_cmdex == `CMDEX_ENTER_PUSH || wr_cmdex == `CMDEX_ENTER_LOOP);
wire cond_137 = wr_cmd == `CMD_WBINVD && wr_cmdex == `CMDEX_WBINVD_STEP_0;
wire cond_147 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_STEP_1;
wire cond_148 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_STEP_2;
wire cond_150 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_3;
wire cond_151 = wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_4;
wire cond_152 = wr_cmd == `CMD_LODS;
wire cond_154 = ~(wr_string_ignore) && ~(wr_string_finish) && wr_prefix_group_1_rep != 2'd0;
wire cond_156 = wr_cmd == `CMD_XCHG && wr_cmdex == `CMDEX_XCHG_modregrm;
wire cond_159 = wr_cmd == `CMD_INT_INTO && wr_cmdex == `CMDEX_INT_INTO_INT_STEP_0;
wire cond_160 = wr_cmd == `CMD_INT_INTO && wr_cmdex == `CMDEX_INT_INTO_INT3_STEP_0;
wire cond_161 = wr_cmd == `CMD_INT_INTO && wr_cmdex == `CMDEX_INT_INTO_INT1_STEP_0;
wire cond_162 = wr_cmd == `CMD_INT_INTO && wr_cmdex == `CMDEX_INT_INTO_INTO_STEP_0;
wire cond_163 = oflag;
wire cond_167 = wr_cmd == `CMD_IN;
wire cond_168 = ~(io_allow_check_needed) || wr_cmdex == `CMDEX_IN_protected;
wire cond_170 = (wr_cmd == `CMD_LAR || wr_cmd == `CMD_LSL || wr_cmd == `CMD_VERR || wr_cmd == `CMD_VERW) && (wr_cmdex == `CMDEX_LAR_LSL_VERR_VERW_STEP_1 || wr_cmdex == `CMDEX_LAR_LSL_VERR_VERW_STEP_2);
wire cond_174 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_same_STEP_3) || (wr_cmd == `CMD_IRET_2  && wr_cmdex == `CMDEX_IRET_2_protected_same_STEP_0) || (wr_cmd == `CMD_CALL_2  && wr_cmdex == `CMDEX_CALL_2_protected_seg_STEP_3) || (wr_cmd == `CMD_CALL_2  && wr_cmdex == `CMDEX_CALL_2_call_gate_same_STEP_2) || (wr_cmd == `CMD_JMP     && wr_cmdex == `CMDEX_JMP_protected_seg_STEP_0) || (wr_cmd == `CMD_JMP_2   && wr_cmdex == `CMDEX_JMP_2_call_gate_STEP_2) || (wr_cmd == `CMD_int_2   && wr_cmdex == `CMDEX_int_2_int_trap_gate_same_STEP_4);
wire cond_177 = (wr_cmd == `CMD_CALL_3 && wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_9) || (wr_cmd == `CMD_int_3  && wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_4);
wire cond_179 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_5) || (wr_cmd == `CMD_IRET_2  && wr_cmdex == `CMDEX_IRET_2_protected_outer_STEP_3);
wire cond_180 = (wr_cmd == `CMD_RET_far && wr_cmdex == `CMDEX_RET_far_outer_STEP_6) || (wr_cmd == `CMD_IRET_2  && wr_cmdex == `CMDEX_IRET_2_protected_outer_STEP_5) || (wr_cmd == `CMD_CALL_3  && wr_cmdex == `CMDEX_CALL_3_call_gate_more_STEP_8) || (wr_cmd == `CMD_int_3   && wr_cmdex == `CMDEX_int_3_int_trap_gate_more_STEP_5);
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
wire cond_194 = wr_string_finish;
wire cond_196 = wr_cmd == `CMD_INS;
wire cond_197 = wr_cmdex == `CMDEX_INS_real_1 || wr_cmdex == `CMDEX_INS_protected_1;
wire cond_198 = wr_string_finish || wr_prefix_group_1_rep == 2'd0;
wire cond_199 = wr_cmd == `CMD_OUTS;
wire cond_200 = io_allow_check_needed && wr_cmdex == `CMDEX_OUTS_first;
wire cond_201 = ~(write_io_for_wr_ready);
wire cond_203 = wr_cmd == `CMD_JMP && (wr_cmdex == `CMDEX_JMP_Jv_STEP_0 || wr_cmdex == `CMDEX_JMP_Ev_STEP_0);
wire cond_205 = wr_cmd == `CMD_JMP && (wr_cmdex == `CMDEX_JMP_Ep_STEP_0 || wr_cmdex == `CMDEX_JMP_Ap_STEP_0 ||  +  wr_cmdex == `CMDEX_JMP_Ep_STEP_1 || wr_cmdex == `CMDEX_JMP_Ap_STEP_1);
wire cond_206 = wr_cmd == `CMD_JMP && wr_cmdex == `CMDEX_JMP_real_v8086_STEP_0;
wire cond_207 = wr_cmd == `CMD_JMP && wr_cmdex == `CMDEX_JMP_task_switch_STEP_0;
wire cond_208 = wr_cmd == `CMD_JMP_2 && wr_cmdex == `CMDEX_JMP_2_call_gate_STEP_0;
wire cond_209 = wr_cmd == `CMD_JMP_2 && wr_cmdex == `CMDEX_JMP_2_call_gate_STEP_1;
wire cond_210 = wr_cmd == `CMD_OUT;
wire cond_211 = ~(io_allow_check_needed) || wr_cmdex == `CMDEX_OUT_protected;
wire cond_222 = wr_cmd == `CMD_BOUND && wr_cmdex == `CMDEX_BOUND_STEP_FIRST;
wire cond_225 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_1;
wire cond_226 = wr_cmd == `CMD_task_switch && (wr_cmdex == `CMDEX_task_switch_STEP_2 || wr_cmdex == `CMDEX_task_switch_STEP_3 || wr_cmdex == `CMDEX_task_switch_STEP_4 || wr_cmdex == `CMDEX_task_switch_STEP_5);
wire cond_227 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_6;
wire cond_229 = wr_cmd == `CMD_task_switch && (wr_cmdex == `CMDEX_task_switch_STEP_7 || wr_cmdex == `CMDEX_task_switch_STEP_8);
wire cond_230 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_9;
wire cond_231 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_10;
wire cond_232 = wr_cmd == `CMD_task_switch_2 && wr_cmdex <= `CMDEX_task_switch_2_STEP_13;
wire cond_234 = wr_cmd == `CMD_task_switch && wr_cmdex == `CMDEX_task_switch_STEP_11;
wire cond_236 = wr_cmd == `CMD_task_switch && wr_cmdex >= `CMDEX_task_switch_STEP_12 && wr_cmdex <= `CMDEX_task_switch_STEP_14;
wire cond_237 = wr_cmd == `CMD_task_switch_3;
wire cond_238 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_0;
wire cond_240 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_1;
wire cond_242 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_2;
wire cond_244 = wr_cmd == `CMD_task_switch_4 && wr_cmdex >= `CMDEX_task_switch_4_STEP_3 && wr_cmdex <= `CMDEX_task_switch_4_STEP_8;
wire cond_253 = wr_cmd == `CMD_task_switch_4 && wr_cmdex == `CMDEX_task_switch_4_STEP_9;
wire cond_258 = (wr_cmd == `CMD_SGDT || wr_cmd == `CMD_SIDT);
wire cond_259 = wr_cmdex == `CMDEX_SGDT_SIDT_STEP_1;
wire cond_261 = wr_cmd == `CMD_MOVS;
wire cond_263 = wr_cmd == `CMD_POPA;
wire cond_264 = wr_cmdex[2:0] == 3'd7;
wire cond_266 = wr_cmd == `CMD_debug_reg && wr_cmdex == `CMDEX_debug_reg_MOV_load_STEP_0;
assign wr_not_finished =
    (cond_0)? (`TRUE) :
    (cond_6)? (`TRUE) :
    (cond_7)? (`TRUE) :
    (cond_8)? (`TRUE) :
    (cond_11)? (`TRUE) :
    (cond_13)? (`TRUE) :
    (cond_14)? (`TRUE) :
    (cond_16)? (`TRUE) :
    (cond_17)? (`TRUE) :
    (cond_18)? (`TRUE) :
    (cond_19)? (`TRUE) :
    (cond_26)? (`TRUE) :
    (cond_28)? (`TRUE) :
    (cond_30)? (`TRUE) :
    (cond_31)? (`TRUE) :
    (cond_32 && cond_36)? (`TRUE) :
    (cond_41)? (`TRUE) :
    (cond_43)? (`TRUE) :
    (cond_52)? (`TRUE) :
    (cond_53)? (`TRUE) :
    (cond_54)? (`TRUE) :
    (cond_55)? (`TRUE) :
    (cond_57)? (`TRUE) :
    (cond_58)? (`TRUE) :
    (cond_59)? (`TRUE) :
    (cond_61)? (`TRUE) :
    (cond_65)? (`TRUE) :
    (cond_67)? (`TRUE) :
    (cond_70)? (`TRUE) :
    (cond_75)? (`TRUE) :
    (cond_80)? (`TRUE) :
    (cond_84)? (`TRUE) :
    (cond_85)? (`TRUE) :
    (cond_86)? (`TRUE) :
    (cond_87)? (`TRUE) :
    (cond_92)? (`TRUE) :
    (cond_93)? (`TRUE) :
    (cond_97)? (`TRUE) :
    (cond_106)? (`TRUE) :
    (cond_107 && cond_36)? (`TRUE) :
    (cond_119 && cond_120)? (`TRUE) :
    (cond_119 && ~cond_123)? (`TRUE) :
    (cond_124 && cond_126)? (`TRUE) :
    (cond_130)? (`TRUE) :
    (cond_132)? (`TRUE) :
    (cond_137)? (`TRUE) :
    (cond_147)? (`TRUE) :
    (cond_148)? (`TRUE) :
    (cond_150)? (`TRUE) :
    (cond_151)? (`TRUE) :
    (cond_152 && cond_154)? (`TRUE) :
    (cond_156)? (`TRUE) :
    (cond_159)? (`TRUE) :
    (cond_160)? (`TRUE) :
    (cond_161)? (`TRUE) :
    (cond_162 && cond_163)? (`TRUE) :
    (cond_167 && ~cond_168)? (`TRUE) :
    (cond_170)? (`TRUE) :
    (cond_174)? (`TRUE) :
    (cond_177)? (`TRUE) :
    (cond_179)? (`TRUE) :
    (cond_180)? (`TRUE) :
    (cond_183)? (`TRUE) :
    (cond_184)? (`TRUE) :
    (cond_185)? (`TRUE) :
    (cond_186)? (`TRUE) :
    (cond_187)? (`TRUE) :
    (cond_188)? (`TRUE) :
    (cond_189)? (`TRUE) :
    (cond_190)? (`TRUE) :
    (cond_191)? (`TRUE) :
    (cond_192 && cond_33 && ~cond_9 && ~cond_194 && cond_34)? (`TRUE) :
    (cond_196 && cond_197)? (`TRUE) :
    (cond_196 && ~cond_197 && cond_33 && ~cond_9 && ~cond_198)? (`TRUE) :
    (cond_199 && cond_200)? (`TRUE) :
    (cond_199 && ~cond_200 && cond_33 && ~cond_201 && ~cond_198)? (`TRUE) :
    (cond_203)? (`TRUE) :
    (cond_205)? (`TRUE) :
    (cond_206)? (`TRUE) :
    (cond_207)? (`TRUE) :
    (cond_208)? (`TRUE) :
    (cond_209)? (`TRUE) :
    (cond_210 && ~cond_211)? (`TRUE) :
    (cond_222)? (`TRUE) :
    (cond_225)? (`TRUE) :
    (cond_226)? (`TRUE) :
    (cond_227)? (`TRUE) :
    (cond_229)? (`TRUE) :
    (cond_230)? (`TRUE) :
    (cond_231)? (`TRUE) :
    (cond_232)? (`TRUE) :
    (cond_234)? (`TRUE) :
    (cond_236)? (`TRUE) :
    (cond_237)? (`TRUE) :
    (cond_238)? (`TRUE) :
    (cond_240)? (`TRUE) :
    (cond_242)? (`TRUE) :
    (cond_244)? (`TRUE) :
    (cond_253)? (`TRUE) :
    (cond_258 && cond_259)? (`TRUE) :
    (cond_261 && cond_33 && ~cond_9 && ~cond_194 && cond_34)? (`TRUE) :
    (cond_263 && ~cond_264)? (`TRUE) :
    (cond_266)? (`TRUE) :
    1'd0;
