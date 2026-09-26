// SPDX-License-Identifier: GPL-3.0-or-later
// Combinational equivalence of redirect/window selection over arbitrary
// registered frontend states. The clock intentionally never advances: this
// test sets the state directly and checks the pre-refactor equations in DUT.
`timescale 1ns/1ps
module z486_prefetch_windows_tb;
    logic clk=0, reset_n=0;
    logic [3:0] d1_adv, d1_preread_adv;
    logic [4:0] lit_off, pop_len;
    logic pop_now, q_flush, pf_ack_toggle, pf_fault, fetch_blocked;
    logic pf_suspend, halt_speculative, spec_req, spec_owner;
    logic spec_store_valid, spec_global_kill;
    logic [31:0] pf_flush_addr, pf_fault_addr, spec_linear, spec_store_linear;
    logic [127:0] pf_rdata;
    logic [2:0] pf_fault_code;
    wire [63:0] win_d1, win_d1_early;
    wire [5:0] d1_avail, lit_avail;
    wire [31:0] win_lit, pf_linear_addr, ifetch_fault_addr;
    wire q_full, pf_req_toggle, pf_redirect_queued, ifetch_fault;
    wire [2:0] ifetch_fault_code;
    integer flush_cases=0, hit_cases=0, simultaneous_fill=0;
    integer alignment_hits[0:15];
    prefetch dut (.*);
    // The original held-window optimization assumes a legal decoder cursor.
    // For arbitrary states compare with that original select itself; the
    // full-core test also checks its stronger next-cursor invariant.
    wire [31:0] old_hold_0 = dut.queue_next_reference[dut.d1_word[2:0]];
    wire [31:0] old_hold_1 = dut.queue_next_reference[3'(dut.d1_word+4'd1)];
    wire [31:0] old_hold_2 = dut.queue_next_reference[3'(dut.d1_word+4'd2)];
    wire [63:0] old_hold_window =
        dut.d1_boff == 2'd0 ? {old_hold_1,old_hold_0} :
        dut.d1_boff == 2'd1 ? {old_hold_2[7:0],old_hold_1,old_hold_0[31:8]} :
        dut.d1_boff == 2'd2 ? {old_hold_2[15:0],old_hold_1,old_hold_0[31:16]} :
                              {old_hold_2[23:0],old_hold_1,old_hold_0[31:24]};
    wire [63:0] old_selected_window = (q_flush || d1_adv == d1_preread_adv)
        ? dut.win_d1_early_reference : old_hold_window;
    initial begin
        for (integer n=0;n<16;n=n+1) alignment_hits[n]=0;
        #1; reset_n=1;
        for (integer trial=0;trial<200000;trial=trial+1) begin
            dut.pf_rptr=$urandom;
            dut.pf_wptr=dut.pf_rptr+4'($urandom_range(0,8));
            dut.pf_byte_offset=$urandom;
            dut.d1_word=dut.pf_rptr+4'($urandom_range(0,8));
            dut.d1_boff=$urandom;
            dut.pf_fetch_word_start=$urandom;
            dut.pf_fetch_addr=$urandom;
            dut.pf_suspended=$urandom;
            dut.pf_drop_inflight=$urandom;
            dut.pf_req_toggle=$urandom;
            dut.pf_ack_prev=$urandom;
            dut.pf_redirect_queued=$urandom;
            dut.spec_pend=$urandom;
            dut.spec_pend_addr=$urandom;
            dut.spec_addr=$urandom;
            dut.spec_off=$urandom;
            dut.spec_inflight=$urandom;
            dut.spec_valid=$urandom;
            dut.spec_poison=$urandom;
            dut.spec_line={$urandom,$urandom,$urandom,$urandom};
            for (integer n=0;n<8;n=n+1) dut.prefetch_queue[n]=$urandom;
            d1_adv=$urandom_range(0,11); d1_preread_adv=$urandom_range(0,11);
            lit_off=$urandom; pop_len=$urandom_range(0,15); pop_now=$urandom;
            q_flush=$urandom; pf_flush_addr=$urandom;
            pf_ack_toggle=$urandom; pf_fault=$urandom;
            pf_rdata={$urandom,$urandom,$urandom,$urandom};
            pf_fault_code=$urandom; pf_fault_addr=$urandom;
            fetch_blocked=$urandom; pf_suspend=$urandom; halt_speculative=$urandom;
            spec_req=$urandom; spec_linear=$urandom; spec_owner=$urandom;
            spec_store_valid=$urandom; spec_store_linear=$urandom; spec_global_kill=$urandom;
            #1;
            if ({dut.rptr_next,dut.wptr_next,dut.byte_offset_next,dut.d1_word_next,dut.d1_boff_next} !==
                {dut.rptr_next_reference,dut.wptr_next_reference,dut.byte_offset_next_reference,
                 dut.d1_word_next_reference,dut.d1_boff_next_reference})
                $fatal(1,"PREFETCH CURSOR EQUIVALENCE trial %0d",trial);
            for (integer n=0;n<8;n=n+1)
                if (dut.queue_next[n] !== dut.queue_next_reference[n])
                    $fatal(1,"PREFETCH QUEUE EQUIVALENCE trial %0d word %0d",trial,n);
            if (dut.win_d1_next !== old_selected_window ||
                win_d1_early !== dut.win_d1_early_reference)
                $fatal(1,"PREFETCH WINDOW EQUIVALENCE trial %0d",trial);
            if (q_flush) begin
                flush_cases++;
                if (dut.good_ack) simultaneous_fill++;
                if (dut.spec_flush_hit) begin
                    hit_cases++; alignment_hits[dut.spec_off]++;
                end
            end
        end
        for (integer n=0;n<16;n=n+1)
            if (alignment_hits[n]<100) $fatal(1,"Missing speculative alignment coverage %0d",n);
        if (simultaneous_fill<100) $fatal(1,"Missing flush/fill collision coverage");
        $display("PASS: 200000 prefetch states; %0d redirects, %0d target hits, %0d simultaneous fills; all 16 target alignments",flush_cases,hit_cases,simultaneous_fill);
        $finish;
    end
endmodule
