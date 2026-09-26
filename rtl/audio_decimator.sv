// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Band-limits the mixed core audio to 48 kHz before the MiSTer framework
// point-samples it. The OPNA (55.5 kHz) and PCM86 (44.1 kHz) outputs are
// zero-order-hold staircases; sampled directly at 48 kHz their images fold
// back into the audible band (a 10 kHz FM tone also shows up at 2.5 kHz).
//
// Runs on CLK_AUDIO (24.576 MHz), the same clock as sys/audio_out, so the
// 48 kHz output needs no further crossing:
//   capture   the clk_sys-domain mix, accepted when stable for two clocks
//   CIC2 /32  24.576 MHz -> 768 kHz
//   FIR /16   255-tap equiripple, 0-18 kHz pass, >=28 kHz -75 dB -> 48 kHz
// Coefficients come from scripts/design_audio_decimator.py. One multiplier per
// channel, history and coefficients in block RAM. enable=0 passes the
// captured input through unchanged.
module audio_decimator #(
    parameter COEF_FILE="../../rtl/assets/audio-decimator-coeffs.mem"
) (
    input wire clk,
    input wire enable,              // asynchronous, synchronized here
    input wire [15:0] in_l, in_r,   // signed, from another clock domain
    output reg [15:0] out_l, out_r
);
    // Same stable-value capture as sys/audio_out.
    reg [15:0] l1 = 0, l2 = 0, cl = 0, r1 = 0, r2 = 0, cr = 0;
    reg [1:0] en_sync = 0;
    always @(posedge clk) begin
        l1 <= in_l; l2 <= l1; if (l1 == l2) cl <= l2;
        r1 <= in_r; r2 <= r1; if (r1 == r2) cr <= r2;
        en_sync <= {en_sync[0], enable};
    end

    // CIC2, R=32: gain 1024, 26-bit wrap-around arithmetic.
    reg [4:0] phase = 0;
    reg [3:0] slot = 0;
    reg [25:0] il1 = 0, il2 = 0, ir1 = 0, ir2 = 0;
    reg [25:0] dl1 = 0, dl2 = 0, dr1 = 0, dr2 = 0;
    wire tick = phase == 5'd31;
    wire [25:0] cl1 = il2 - dl1, cr1 = ir2 - dr1;
    wire [25:0] cl2 = cl1 - dl2, cr2 = cr1 - dr2;
    always @(posedge clk) begin
        phase <= phase + 5'd1;
        il1 <= il1 + {{10{cl[15]}}, cl}; il2 <= il2 + il1;
        ir1 <= ir1 + {{10{cr[15]}}, cr}; ir2 <= ir2 + ir1;
        if (tick) begin
            dl1 <= il2; dl2 <= cl1;
            dr1 <= ir2; dr2 <= cr1;
            slot <= slot + 4'd1;
        end
    end

    // History: 256 x {left,right} 18-bit samples (input x4).
    (* ramstyle="M10K,no_rw_check" *) reg [35:0] history[0:255];
    (* ramstyle="M10K" *) reg [17:0] coef[0:255];
    initial $readmemh(COEF_FILE, coef);
    reg [7:0] wptr = 0;
    always @(posedge clk) if (tick) begin
        history[wptr] <= {cl2[25:8], cr2[25:8]};
        wptr <= wptr + 8'd1;
    end

    // One 48 kHz output per sixteen history writes. Reads go oldest first,
    // so writes during the 255-cycle pass never reach an unread entry.
    reg run = 0;
    reg [7:0] tap = 0, base = 0;
    reg [35:0] hq;
    reg [17:0] cq;
    reg [2:0] valid = 0;
    reg last_d1 = 0, last_d2 = 0, last_d3 = 0;
    reg signed [35:0] pl, pr;
    reg signed [43:0] accl, accr;
    wire start = tick && slot == 4'd15;
    always @(posedge clk) begin
        if (start) begin
            run <= 1'b1; tap <= 8'd0; base <= wptr + 8'd2;
        end else if (run) begin
            tap <= tap + 8'd1;
            if (tap == 8'd254) run <= 1'b0;
        end
        // start samples wptr before this tick's write, so +2 is the oldest
        // of the 255 newest entries once that write lands.
        hq <= history[base + tap];
        cq <= coef[tap];
        valid <= {valid[1:0], run};
        last_d1 <= run && tap == 8'd254; last_d2 <= last_d1; last_d3 <= last_d2;
        pl <= $signed(hq[35:18]) * $signed(cq);
        pr <= $signed(hq[17:0]) * $signed(cq);
        if (valid[1] && !valid[2]) begin
            accl <= pl; accr <= pr;
        end else if (valid[1]) begin
            accl <= accl + pl; accr <= accr + pr;
        end
    end

    // acc = y * 2^23 (coefficients x2^21, samples x4); round and saturate.
    function automatic [15:0] sat16(input signed [43:0] acc);
        reg signed [43:0] y;
        begin
            y = (acc + 44'sd4194304) >>> 23;
            if (y > 44'sd32767) sat16 = 16'h7fff;
            else if (y < -44'sd32768) sat16 = 16'h8000;
            else sat16 = y[15:0];
        end
    endfunction
    reg [15:0] fl = 0, fr = 0;
    always @(posedge clk) begin
        if (last_d3) begin
            fl <= sat16(accl); fr <= sat16(accr);
        end
        out_l <= en_sync[1] ? fl : cl;
        out_r <= en_sync[1] ? fr : cr;
    end
endmodule
