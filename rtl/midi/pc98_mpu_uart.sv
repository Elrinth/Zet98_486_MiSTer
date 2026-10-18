// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Original implementation of the MPU-PC98II, E0D0/E0D2, IRQ6, following the
// behaviour of NP2kai cbus/mpu98ii.c.
// FF resets; FE is returned only outside UART mode. 3F enters UART mode and
// returns FE. Outside UART mode (intelligent mode) every command is ACKed (FE),
// E0-EF take one data byte, D0-D7 ("want to send data") pass one MIDI message
// (running status kept) and DF one system message to MIDI out, and
// clock-to-host (95/94) sends FD every E7-set number of internal clocks at
// tempo (E0) x relative tempo (E1) x timebase (C2-C8). KAJA MMD (Cyber Arms)
// drives its music from these FD ticks and waits for every ACK.
// The sequencer plays 8 tracks and the conductor (Start Play 09-0B, Stop Play
// 05-07, Act Tr EC, Conductor 8E/8F): every internal clock counts down the
// active tracks; a track at zero sends its pending event and requests the next
// one (F0+n), the conductor requests with F9. The host answers a request with
// a timing byte and an event (status or running-status data, or an F8/F9/FC
// mark; FC ends the track). Arsys NMD (Star Cruiser II) paces its MT-32 setup
// this way and waits for the requests without a timeout. A0-AF return the
// play counters, version 1.0 and the tempo after the ACK.
// All state is on clk; serial input alone crosses through a two-flop synchronizer.
module pc98_mpu_uart #(
    parameter integer CLOCK_HZ = 50000000,
    parameter integer BAUD = 31250,
    parameter integer FIFO_BITS = 4,
    parameter integer RESET_PANIC = 0
) (
    input wire clk, reset, enable,
    input wire [15:0] io_address, io_writedata,
    input wire [1:0] io_select,
    input wire io_read, io_write,
    output reg [7:0] io_readdata,
    output wire io_oe, irq,
    input wire midi_rx,
    output wire midi_tx,
    output reg rx_overrun, rx_framing_error, tx_overrun
);
    localparam integer BIT_TICKS = (CLOCK_HZ + BAUD/2) / BAUD;
    localparam integer TIMER_BITS = $clog2(BIT_TICKS);
    localparam integer FIFO_DEPTH = 1 << FIFO_BITS;
    reg previous_read, previous_write;
    wire decoded = enable && io_select[0] &&
                   (io_address == 16'he0d0 || io_address == 16'he0d2);
    wire read_start = decoded && io_read && !previous_read;
    wire write_start = decoded && io_write && !previous_write;
    wire command_write = write_start && io_address[1];
    wire data_read = read_start && !io_address[1];
    wire reset_command = command_write && io_writedata[7:0] == 8'hff;
    wire clear = reset || !enable || reset_command;
    reg uart_mode, ack_pending;

    reg [7:0] tx_fifo[0:FIFO_DEPTH-1], rx_fifo[0:FIFO_DEPTH-1];
    reg [FIFO_BITS-1:0] tx_head, tx_tail, rx_head, rx_tail;
    reg [FIFO_BITS:0] tx_count, rx_count;
    wire tx_full = tx_count == FIFO_DEPTH;
    wire rx_full = rx_count == FIFO_DEPTH;
    // Intelligent-mode state.
    reg param_pending = 0;               // next data write is an E0-EF parameter
    reg [3:0] param_cmd = 0;
    reg short_msg = 0, long_msg = 0;     // D0-D7 / DF message in progress
    reg [7:0] host_rstat = 0;            // D0-D7 running status
    reg [1:0] short_left = 0;            // bytes still to come in a D0-D7 message
    reg [7:0] long_first = 0;            // first byte of a DF message
    reg [1:0] long_count = 0;
    reg clk_to_host = 0;
    reg [7:0] tempo = 100, reltempo = 8'h40, hclk_data = 240;
    reg [3:0] timebase = 5;              // timebase / 24
    wire data_write = write_start && !io_address[1];
    wire [7:0] wd = io_writedata[7:0];
    wire im_data = data_write && !uart_mode;
    wire msg_byte = im_data && !param_pending && (short_msg || long_msg);
    wire seq_byte = im_data && !param_pending && !short_msg && !long_msg;
    // MIDI bytes leave intelligent mode through a 4-byte stage (an event or a
    // running-status message); UART-mode data goes to the FIFO directly.
    reg [7:0] stg[0:3];
    reg [2:0] stg_n = 0;
    reg stage_overrun = 0;
    wire uart_push = data_write && uart_mode && !tx_full;
    wire stg_pop = stg_n != 0 && !tx_full && !uart_push;
    wire tx_push = uart_push || stg_pop;
    wire [7:0] tx_in = uart_push ? wd : stg[0];
    reg [9:0] tx_shift = 10'h3ff;
    reg [3:0] tx_bits = 0;
    reg [TIMER_BITS-1:0] tx_timer = 0;
    reg reset_seen = 0, enable_seen = 0;
    reg panic_pending = 0, panic_lead = 1;
    reg [3:0] panic_channel = 0, panic_phase = 0;
    wire panic_event = RESET_PANIC && (reset_command ||
        (reset && !reset_seen && enable) || (enable != enable_seen));
    wire tx_pop = !clear && !tx_bits && tx_count != 0 && !panic_pending && !panic_event;
    wire [7:0] panic_byte = panic_lead ? 8'hf7 : // End interrupted SysEx.
        (panic_phase == 0 || panic_phase == 3 || panic_phase == 6 || panic_phase == 9) ? {4'hb,panic_channel} :
        panic_phase == 1 ? 8'd64 :  // Sustain off.
        panic_phase == 4 ? 8'd120 : // All Sound Off, including sustained voices.
        panic_phase == 7 ? 8'd123 : // All Notes Off.
        panic_phase == 10 ? 8'd121 : 8'd0; // Reset All Controllers.
    assign midi_tx = (!RESET_PANIC && (!enable || reset)) || !tx_bits ? 1'b1 : tx_shift[0];
    assign io_oe = decoded && io_read;

    // Sequencer state (mpu98ii.c tr[], cond, intphase, intreq, recvevent).
    reg play = 0, cond_on = 0;
    reg [7:0] acttr = 0;
    reg [7:0] tstep[0:7];
    reg [1:0] tremain[0:7], tdatas[0:7];
    // Per-track event bytes {running status, data 2, data 1, data 0}, only
    // ever accessed at the current track: an MLAB with asynchronous read.
    // A reset clears the running status through trv (no RAM clear).
    (* ramstyle = "MLAB, no_rw_check" *) reg [31:0] trk[0:7];
    reg [7:0] trv = 0;
    reg [7:0] cstep = 0;
    reg c_step_ph = 0, c_cmd_ph = 0, c_follow = 0;
    reg [3:0] c_param = 0;
    reg [3:0] intphase = 0;              // 1 conductor, 2-9 tracks 1-8
    reg [7:0] intreq = 0;
    reg rv_step = 0, rv_event = 0, rv_data = 0;
    reg [7:0] remainstep = 0;            // internal clocks not yet searched
    reg searching = 0;
    // Conductor D0-D7 / DF: the message bytes follow at a later F9 request.
    reg c_short = 0, c_long = 0;
    reg [1:0] c_short_left = 0, c_long_count = 0;
    reg [7:0] c_rstat = 0, c_long_first = 0;
    reg aux_valid = 0;                   // request reply or FC for the host
    reg [7:0] aux_byte = 0;
    wire aux_push;
    wire [2:0] cur = intphase[2:0] - 3'd2;   // track of phases 2-9
    wire host_has_data = ack_pending || rx_count != 0 || intreq != 0;
    assign irq = enable && !reset && host_has_data;

    // Register a read result once, before its destructive FIFO/ACK side effect.
    // The legacy bus keeps RD asserted for multiple clocks while the CPU waits.
    always @(posedge clk) begin
        if (reset || !enable) begin
            previous_read <= 0;
            previous_write <= 0;
            io_readdata <= 8'hff;
        end else begin
            previous_read <= io_read;
            previous_write <= io_write;
            if (read_start) begin
                if (io_address[1])
                    io_readdata <= {!host_has_data, tx_full || stg_n != 0, 6'b0};
                else io_readdata <= ack_pending ? 8'hfe :
                                    rx_count != 0 ? rx_fifo[rx_head] :
                                    intreq != 0 ? intreq : 8'hff;
            end
        end
    end

    always @(posedge clk) begin
        if (clear) begin
            uart_mode <= 0;
            // Roland technical reference p22: leaving UART mode via FF
            // does not return FE. A later reset outside UART mode does.
            ack_pending <= reset_command && enable && !reset && !uart_mode;
        end else begin
            if (data_read && ack_pending) ack_pending <= 0;
            if (command_write && !uart_mode) begin
                ack_pending <= 1;
                if (wd == 8'h3f) uart_mode <= 1;
            end
        end
    end

    // A command from the host (ACKed) or from the conductor (not ACKed), and
    // an E0-EF parameter from either.
    reg [7:0] seq_cmd_val = 0, seq_param_val = 0;
    reg seq_cmd_fire = 0, seq_param_fire = 0;
    reg [3:0] seq_param_cmd = 0;
    wire host_cmd = command_write && !uart_mode;
    wire cmd_fire = host_cmd || seq_cmd_fire;
    wire [7:0] cmd_val = host_cmd ? wd : seq_cmd_val;
    wire host_param = im_data && param_pending;
    wire param_fire = host_param || seq_param_fire;
    wire [3:0] param_sel = host_param ? param_cmd : seq_param_cmd;
    wire [7:0] param_val = host_param ? wd : seq_param_val;
    wire play_stop = cmd_val < 8'h30 && cmd_val[1:0] != 0 && cmd_val[3:2] == 2'b01;
    wire play_start = cmd_val < 8'h30 && cmd_val[1:0] != 0 && cmd_val[3:2] == 2'b10;

    // Intelligent-mode commands, parameters and the internal clock.
    // Internal clocks per second = tempo x reltempo/64 x timebase*24 / 60,
    // i.e. step_rate/160 with step_rate = tempo x reltempo x timebase.
    // The accumulator advances once per 64 clocks (at most 3.3k internal
    // clocks/s against a CLOCK_HZ/64 rate), so it needs 28 bits, not 40
    // (CLOCK_HZ up to 100 MHz).
    localparam [39:0] STEP_DIV40 = (40'd160 * CLOCK_HZ + 40'd32) / 40'd64;
    localparam [27:0] STEP_DIV = STEP_DIV40[27:0];
    reg [19:0] step_rate = 20'd100 * 8'h40 * 4'd5;
    reg [27:0] step_acc = 0;
    reg [5:0] step_pre = 0;
    reg [7:0] hclk_rem = 0;
    reg [1:0] hclk_cnt = 0;
    reg fd_fire = 0, tick = 0;
    wire [7:0] hclk_quarter = hclk_data[7:2] == 0 ? 8'd64 : {2'b0, hclk_data[7:2]};
    function automatic [7:0] hclk_step(input [1:0] frac, input [1:0] idx);
        hclk_step = hclk_quarter + ((frac == 1 && idx == 0) || (frac == 2 && !idx[0]) ||
                                    (frac == 3 && idx != 3) ? 8'd1 : 8'd0);
    endfunction
    wire [7:0] long_head = long_count == 0 ? wd : long_first;
    always @(posedge clk) begin
        fd_fire <= 0;
        tick <= 0;
        step_rate <= tempo * reltempo * timebase;
        if (clear) begin
            param_pending <= 0; clk_to_host <= 0;
            short_msg <= 0; long_msg <= 0; host_rstat <= 0; short_left <= 0; long_count <= 0;
            tempo <= 100; reltempo <= 8'h40; hclk_data <= 240; timebase <= 5;
            step_acc <= 0; step_pre <= 0; hclk_rem <= 0; hclk_cnt <= 0;
        end else begin
            if (host_cmd) begin
                param_pending <= wd[7:4] == 4'he;
                param_cmd <= wd[3:0];
                short_msg <= wd[7:3] == 5'b11010;
                long_msg <= wd == 8'hdf;
                long_count <= 0;
                short_left <= 0;
            end else if (host_param) param_pending <= 0;
            if (cmd_fire) case (cmd_val)
                8'h94: clk_to_host <= 0;
                8'h95: clk_to_host <= 1;
                8'hb1: reltempo <= 8'h40;
                8'hc2, 8'hc3, 8'hc4, 8'hc5, 8'hc6, 8'hc7, 8'hc8: timebase <= cmd_val[3:0];
                default: ;
            endcase
            if (param_fire) case (param_sel)
                4'h0: begin tempo <= param_val; reltempo <= 8'h40; end
                4'h1: reltempo <= param_val;
                4'h7: begin hclk_data <= param_val; hclk_rem <= 0; end
                default: ;
            endcase
            // D0-D7: one channel message; a data byte first reuses the
            // running status. DF: a SysEx ends at F7, F2/F3 take 3 bytes.
            if (msg_byte && short_msg) begin
                if (short_left == 0) begin
                    if (wd[7]) begin
                        if (wd[7:4] == 4'hf) short_msg <= 0;
                        else begin
                            host_rstat <= wd;
                            short_left <= wd[7:5] == 3'b110 ? 2'd1 : 2'd2;
                        end
                    end else if (host_rstat[7:5] == 3'b110) short_msg <= 0;
                    else short_left <= 2'd1;
                end else begin
                    short_left <= short_left - 1'b1;
                    if (short_left == 1) short_msg <= 0;
                end
            end
            if (msg_byte && long_msg) begin
                if (long_count == 0) long_first <= wd;
                if (long_count != 3) long_count <= long_count + 1'b1;
                if (long_head == 8'hf0 ? wd == 8'hf7 :
                    (long_head == 8'hf2 || long_head == 8'hf3) ? long_count == 2 : 1'b1)
                    long_msg <= 0;
            end
            if (uart_mode || !(clk_to_host || play)) begin
                step_acc <= 0; step_pre <= 0;
            end else if (step_pre != 6'd63) begin
                step_pre <= step_pre + 1'b1;
            end else if (step_acc + step_rate >= STEP_DIV) begin
                step_pre <= 0;
                // One internal clock (midiint): a sequencer step, and
                // clock-to-host reloads an empty E7 countdown, FD at zero.
                step_acc <= step_acc + step_rate - STEP_DIV;
                tick <= 1;
                if (clk_to_host) begin
                    if (hclk_rem == 0) hclk_cnt <= hclk_cnt + 1'b1;
                    hclk_rem <= (hclk_rem == 0 ? hclk_step(hclk_data[1:0], hclk_cnt) : hclk_rem) - 1'b1;
                    fd_fire <= (hclk_rem == 0 ? hclk_step(hclk_data[1:0], hclk_cnt) : hclk_rem) == 1;
                end
            end else begin
                step_pre <= 0;
                step_acc <= step_acc + step_rate;
            end
        end
    end

    // Sequencer. One search phase per clock; a request stops the search until
    // the host has sent the timing byte and the event, then it resumes.
    wire tick_play = tick && play;
    wire start_search = tick_play && remainstep == 0;
    wire pass_end = searching && !seq_byte && intphase >= 10;
    wire [7:0] rs_after_pass = remainstep - 1'b1 + (tick_play ? 8'd1 : 8'd0);
    wire [2:0] stg_base = stg_n - (stg_pop ? 3'd1 : 3'd0);
    wire msg_running = short_msg && short_left == 0 && !wd[7];
    wire cond_msg_byte = seq_byte && !rv_step && !rv_event && !rv_data && (c_short || c_long);
    wire c_running = c_short && c_short_left == 0 && !wd[7];
    wire out_running = msg_byte ? msg_running : c_running;
    wire [7:0] c_long_head = c_long_count == 0 ? wd : c_long_first;
    integer i;
    wire [31:0] trk_rd = trk[cur];
    wire [7:0] tdat0_c = trk_rd[7:0], tdat1_c = trk_rd[15:8], tdat2_c = trk_rd[23:16];
    wire [7:0] trstat_c = trv[cur] ? trk_rd[31:24] : 8'd0;
    reg [31:0] tw;
    reg twe;
    always @(posedge clk) begin
        tw = trk_rd;
        twe = 0;
        seq_cmd_fire <= 0;
        seq_param_fire <= 0;
        stage_overrun <= 0;
        if (stg_pop) begin
            stg[0] <= stg[1]; stg[1] <= stg[2]; stg[2] <= stg[3];
            stg_n <= stg_n - 1'b1;
        end
        if (clear) begin
            play <= 0; cond_on <= 0; acttr <= 0; trv <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                tstep[i] <= 0; tremain[i] <= 0; tdatas[i] <= 0;
            end
            cstep <= 0; c_step_ph <= 0; c_cmd_ph <= 0; c_follow <= 0;
            intphase <= 0; intreq <= 0; rv_step <= 0; rv_event <= 0; rv_data <= 0;
            remainstep <= 0; searching <= 0; aux_valid <= 0; stg_n <= 0;
            c_short <= 0; c_long <= 0;
        end else begin
            // The host reads a request after any queued byte.
            if (data_read && !ack_pending && rx_count == 0 && intreq != 0) intreq <= 0;
            if (aux_push) aux_valid <= 0;
            if (msg_byte || cond_msg_byte) begin
                // A D0-D7 data byte first sends the running status.
                if (stg_base + (out_running ? 3'd2 : 3'd1) > 4) stage_overrun <= 1;
                else if (out_running) begin
                    stg[stg_base[1:0]] <= msg_byte ? host_rstat : c_rstat; stg[stg_base[1:0] + 2'd1] <= wd;
                    stg_n <= stg_base + 3'd2;
                end else begin
                    stg[stg_base[1:0]] <= wd;
                    stg_n <= stg_base + 3'd1;
                end
            end
            if (cmd_fire) begin
                if (play_stop) begin
                    play <= 0; rv_step <= 0; rv_event <= 0; rv_data <= 0;
                    intphase <= 0; intreq <= 0; searching <= 0; remainstep <= 0;
                    for (i = 0; i < 8; i = i + 1) begin
                        tstep[i] <= 0; tremain[i] <= 0; tdatas[i] <= 0;
                    end
                    cstep <= 0; c_step_ph <= 0; c_cmd_ph <= 0; c_follow <= 0;
                    c_short <= 0; c_long <= 0;
                end else if (play_start) begin
                    play <= 1; remainstep <= 0;
                end
                if (cmd_val == 8'h8e) cond_on <= 0;
                if (cmd_val == 8'h8f) cond_on <= 1;
                if (cmd_val == 8'hb8) for (i = 0; i < 8; i = i + 1) tstep[i] <= 0;
                if (host_cmd && cmd_val[7:4] == 4'ha) begin
                    aux_valid <= !cmd_val[3] || cmd_val[3:0] == 4'hb || cmd_val[3:0] == 4'hc ||
                                 cmd_val[3:0] == 4'hd || cmd_val[3:0] == 4'hf;
                    aux_byte <= !cmd_val[3] ? tstep[cmd_val[2:0]] : cmd_val[3:0] == 4'hc ? 8'd1 :
                                cmd_val[3:0] == 4'hf ? tempo : 8'd0;
                end
            end
            if (param_fire && param_sel == 4'hc) acttr <= param_val;
            if (seq_byte) begin
                if (rv_step) begin
                    // Timing byte: F0 and above wait 240 clocks with no event.
                    rv_step <= 0;
                    tdatas[cur] <= 0;
                    if (wd < 8'hf0) begin
                        tstep[cur] <= wd; rv_event <= 1;
                    end else begin
                        tstep[cur] <= 8'hf0; tremain[cur] <= 0; searching <= 1;
                    end
                end else if (rv_event) begin
                    // A status sets the event length; a data byte reuses the
                    // track running status; F8/F9/FC marks are one byte.
                    rv_event <= 0;
                    if (wd[7:4] == 4'hf) begin
                        tw[7:0] = wd; twe = 1; tdatas[cur] <= 2'd1; tremain[cur] <= 0;
                        searching <= 1;
                    end else if (wd[7]) begin
                        tw[31:24] = wd; tw[7:0] = wd; twe = 1; trv[cur] <= 1; tdatas[cur] <= 2'd1;
                        tremain[cur] <= wd[7:5] == 3'b110 ? 2'd1 : 2'd2; rv_data <= 1;
                    end else begin
                        tw[7:0] = trstat_c; tw[15:8] = wd; twe = 1; tdatas[cur] <= 2'd2;
                        if (trstat_c[7:5] == 3'b110) begin
                            tremain[cur] <= 0; searching <= 1;
                        end else begin
                            tremain[cur] <= 2'd1; rv_data <= 1;
                        end
                    end
                end else if (rv_data) begin
                    if (tdatas[cur] == 1) tw[15:8] = wd; else tw[23:16] = wd;
                    twe = 1;
                    tdatas[cur] <= tdatas[cur] + 1'b1;
                    tremain[cur] <= tremain[cur] - 1'b1;
                    if (tremain[cur] == 1) begin rv_data <= 0; searching <= 1; end
                end else if (c_short) begin
                    // Conductor D0-D7 message (own running status).
                    if (c_short_left == 0) begin
                        if (wd[7]) begin
                            if (wd[7:4] == 4'hf) c_short <= 0;
                            else begin
                                c_rstat <= wd;
                                c_short_left <= wd[7:5] == 3'b110 ? 2'd1 : 2'd2;
                            end
                        end else if (c_rstat[7:5] == 3'b110) c_short <= 0;
                        else c_short_left <= 2'd1;
                    end else begin
                        c_short_left <= c_short_left - 1'b1;
                        if (c_short_left == 1) c_short <= 0;
                    end
                end else if (c_long) begin
                    // Conductor DF system message: SysEx to F7, F2/F3 3 bytes.
                    if (c_long_count == 0) c_long_first <= wd;
                    if (c_long_count != 3) c_long_count <= c_long_count + 1'b1;
                    if (c_long_head == 8'hf0 ? wd == 8'hf7 :
                        (c_long_head == 8'hf2 || c_long_head == 8'hf3) ? c_long_count == 2 : 1'b1)
                        c_long <= 0;
                end else if (c_follow) begin
                    c_follow <= 0;
                    seq_param_fire <= 1; seq_param_cmd <= c_param; seq_param_val <= wd;
                    searching <= 1;
                end else if (c_step_ph) begin
                    // Conductor timing byte, then a command.
                    c_step_ph <= 0;
                    if (wd < 8'hf0) cstep <= wd;
                    else begin cstep <= 8'hf0; c_cmd_ph <= 0; searching <= 1; end
                end else if (c_cmd_ph) begin
                    c_cmd_ph <= 0;
                    if (wd < 8'hf0) begin
                        seq_cmd_fire <= 1; seq_cmd_val <= wd;
                        if (wd[7:3] == 5'b11010) begin c_short <= 1; c_short_left <= 0; end
                        if (wd == 8'hdf) begin c_long <= 1; c_long_count <= 0; end
                        if (wd[7:4] == 4'he) begin c_follow <= 1; c_param <= wd[3:0]; end
                        else searching <= 1;
                    end else begin
                        if (wd == 8'hfc) begin aux_valid <= 1; aux_byte <= 8'hfc; end
                        searching <= 1;
                    end
                end
            end
            // A new internal clock starts a search when none is pending;
            // otherwise it is counted and searched after the current one.
            if (start_search) begin
                remainstep <= 1; intphase <= 1; searching <= 1;
                if (cond_on && cstep != 0) cstep <= cstep - 1'b1;
                for (i = 0; i < 8; i = i + 1)
                    if (acttr[i] && tstep[i] != 0) tstep[i] <= tstep[i] - 1'b1;
            end else if (pass_end) begin
                remainstep <= rs_after_pass;
                if (rs_after_pass != 0) begin
                    intphase <= 1;
                    if (cond_on && cstep != 0) cstep <= cstep - 1'b1;
                    for (i = 0; i < 8; i = i + 1)
                        if (acttr[i] && tstep[i] != 0) tstep[i] <= tstep[i] - 1'b1;
                end else begin
                    intphase <= 0; searching <= 0;
                end
            end else begin
                if (tick_play && remainstep != 8'hff) remainstep <= remainstep + 1'b1;
                if (searching && !seq_byte) begin
                    if (intphase == 1) begin
                        if (cond_on && cstep == 0) begin
                            intreq <= 8'hf9; c_step_ph <= 1; c_cmd_ph <= 1; searching <= 0;
                        end else intphase <= 2;
                    end else if (acttr[cur] && tstep[cur] == 0) begin
                        if (tdatas[cur] != 0 && tremain[cur] == 0 && tdat0_c == 8'hfc) begin
                            tdatas[cur] <= 0; aux_valid <= 1; aux_byte <= 8'hfc; searching <= 0;
                        end else if (tdatas[cur] != 0 && tremain[cur] == 0 && tdat0_c[7:4] != 4'hf) begin
                            // Send the event, then request the next one.
                            if (stg_n == 0 && !msg_byte) begin
                                stg[0] <= tdat0_c; stg[1] <= tdat1_c; stg[2] <= tdat2_c;
                                stg_n <= {1'b0, tdatas[cur]};
                                tdatas[cur] <= 0;
                                intreq <= {5'b11110, cur}; rv_step <= 1; searching <= 0;
                            end
                        end else begin
                            tdatas[cur] <= 0;
                            intreq <= {5'b11110, cur}; rv_step <= 1; searching <= 0;
                        end
                    end else intphase <= intphase + 1'b1;
                end
            end
        end
        if (twe) trk[cur] <= tw;
    end

    // Full queues apply normal MPU busy backpressure; a software violation is
    // dropped and latched in tx_overrun, never allowed to overwrite queued data.
    always @(posedge clk) begin
        if (clear) begin
            tx_head <= 0; tx_tail <= 0; tx_count <= 0;
            tx_overrun <= 0;
        end else begin
            if ((data_write && uart_mode && tx_full) || stage_overrun)
                tx_overrun <= 1;
            if (tx_push) begin
                tx_fifo[tx_tail] <= tx_in;
                tx_tail <= tx_tail + 1'b1;
            end
            if (tx_pop) tx_head <= tx_head + 1'b1;
            case ({tx_push, tx_pop})
                2'b10: tx_count <= tx_count + 1'b1;
                2'b01: tx_count <= tx_count - 1'b1;
                default: ;
            endcase
        end
    end

    // The serializer survives guest reset long enough to finish its current
    // byte and send panic. Queued game bytes are discarded by clear above.
    // New game traffic queues behind panic with ordinary FIFO backpressure.
    always @(posedge clk) begin
        reset_seen <= reset;
        enable_seen <= enable;
        if (!RESET_PANIC && clear) begin
            tx_shift <= 10'h3ff; tx_bits <= 0; tx_timer <= 0;
        end else begin
            if (!tx_bits) begin
                if (panic_pending && !panic_event) begin
                    tx_shift <= {1'b1,panic_byte,1'b0};
                    tx_bits <= 10; tx_timer <= BIT_TICKS-1;
                    if (panic_lead) panic_lead <= 0;
                    else if (panic_phase == 11) begin
                        panic_phase <= 0;
                        panic_channel <= panic_channel + 1'b1;
                        if (panic_channel == 15) panic_pending <= 0;
                    end else panic_phase <= panic_phase + 1'b1;
                end else if (tx_pop) begin
                    tx_shift <= {1'b1,tx_fifo[tx_head],1'b0};
                    tx_bits <= 10; tx_timer <= BIT_TICKS-1;
                end
            end else if (tx_timer != 0) tx_timer <= tx_timer - 1'b1;
            else begin
                tx_shift <= {1'b1,tx_shift[9:1]};
                tx_bits <= tx_bits - 1'b1;
                tx_timer <= BIT_TICKS-1;
            end
            if (panic_event) begin
                panic_pending <= 1; panic_lead <= 1;
                panic_channel <= 0; panic_phase <= 0;
            end
        end
    end

    (* async_reg = "true" *) reg rx_meta = 1, rx_sync = 1;
    always @(posedge clk) begin
        rx_meta <= midi_rx;
        rx_sync <= rx_meta;
    end
    localparam RX_IDLE=0, RX_START=1, RX_DATA=2, RX_STOP=3, RX_BREAK=4;
    reg [2:0] rx_state;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift;
    reg [TIMER_BITS-1:0] rx_timer;
    wire rx_finish = rx_state == RX_STOP && rx_timer == 0;
    wire rx_pop = data_read && !ack_pending && rx_count != 0;
    wire rx_push = rx_finish && rx_sync && uart_mode && (!rx_full || rx_pop);
    wire fd_push = fd_fire && !uart_mode && (!rx_full || rx_pop);   // clock to host
    assign aux_push = aux_valid && !uart_mode && !rx_push && !fd_push && (!rx_full || rx_pop);
    always @(posedge clk) begin
        if (clear) begin
            rx_state <= RX_IDLE; rx_bit <= 0; rx_timer <= 0; rx_shift <= 0;
            rx_head <= 0; rx_tail <= 0; rx_count <= 0;
            rx_overrun <= 0; rx_framing_error <= 0;
        end else begin
            if (rx_push || fd_push || aux_push) begin
                rx_fifo[rx_tail] <= rx_push ? rx_shift : fd_push ? 8'hfd : aux_byte;
                rx_tail <= rx_tail + 1'b1;
            end
            if (rx_pop) rx_head <= rx_head + 1'b1;
            case ({rx_push || fd_push || aux_push, rx_pop})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: ;
            endcase
            if (rx_finish && !rx_sync) rx_framing_error <= 1;
            if (rx_finish && rx_sync && uart_mode && rx_full && !rx_pop)
                rx_overrun <= 1;
            case (rx_state)
                RX_IDLE: if (!rx_sync) begin
                    rx_state <= RX_START;
                    rx_timer <= BIT_TICKS/2-1;
                end
                RX_START: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                    else if (rx_sync) rx_state <= RX_IDLE;
                    else begin
                        rx_state <= RX_DATA;
                        rx_bit <= 0;
                        rx_timer <= BIT_TICKS-1;
                    end
                RX_DATA: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                    else begin
                        rx_shift[rx_bit] <= rx_sync;
                        rx_bit <= rx_bit + 1'b1;
                        rx_timer <= BIT_TICKS-1;
                        if (rx_bit == 7) rx_state <= RX_STOP;
                    end
                RX_STOP: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                    else rx_state <= rx_sync ? RX_IDLE : RX_BREAK;
                RX_BREAK: if (rx_sync) rx_state <= RX_IDLE;
                default: rx_state <= RX_IDLE;
            endcase
        end
    end
endmodule
