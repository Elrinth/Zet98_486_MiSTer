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
assign rd_system_linear =
    (cond_33)? ( tr_base + 32'd102) :
    (cond_35)? ( tr_base + { 16'd0, rd_memory_last[15:0] } + { 16'd0, 3'd0, glob_param_1[15:3] }) :
    (cond_64)? ( idtr_base + { 22'd0, exc_vector[7:0], 2'b00 }) :
    (cond_65)? ( idtr_base + { 22'd0, exc_vector[7:0], 2'b10 }) :
    (cond_66)? ( idtr_base + { 21'd0, exc_vector[7:0], 3'b000 }) :
    (cond_88)? ( tr_base) :
    (cond_187)? ( tr_base + rd_offset_for_ss_from_tss) :
    (cond_189)? ( tr_base + rd_offset_for_esp_from_tss) :
    (cond_227)? ( gdtr_base + { 16'd0, tr[15:3], 3'd0 } + 32'd4) :
    (cond_232 && cond_233)? ( glob_desc_base + 32'd12) :
    (cond_232 && cond_234)? ( glob_desc_base + 32'h1C) :
    (cond_232 && cond_235)? ( rd_task_switch_linear_next) :
    (cond_237)? ( rd_task_switch_linear_next) :
    (cond_239)? ( gdtr_base + { 16'd0, glob_param_1[15:3], 3'd0 } + 32'd4) :
    32'd0;
