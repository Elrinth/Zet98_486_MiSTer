// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Feeds zero-order-hold staircases like the core's sound sources into
// audio_decimator on a 24.576 MHz clock and records every 512th clock, the
// framework's 48 kHz point sampling. Left: 10 kHz tone at the OPNA rate
// (7.9872 MHz / 144). Right: 13 kHz at the PCM86 44.1 kHz rate. A second
// instance in bypass records what the framework sees without the filter.
module audio_decimator_tb;
    localparam real CLK_NS = 1.0e9 / 24576000.0;
    localparam real OPNA_NS = 1.0e9 * 144.0 / 7987200.0;
    localparam real PCM_NS = 1.0e9 / 44100.0;
    localparam real AMP = 16000.0;
    localparam integer SKIP = 64, SAMPLES = 4096;

    reg clk = 0;
    always #(CLK_NS / 2.0) clk = ~clk;

    reg [15:0] in_l = 0, in_r = 0;
    integer nl = 0, nr = 0;
    always begin
        #(OPNA_NS);
        in_l = $rtoi($floor(AMP * $sin(6.283185307179586 * 10000.0 * nl * OPNA_NS * 1.0e-9) + 0.5));
        nl = nl + 1;
    end
    always begin
        #(PCM_NS);
        in_r = $rtoi($floor(AMP * $sin(6.283185307179586 * 13000.0 * nr * PCM_NS * 1.0e-9) + 0.5));
        nr = nr + 1;
    end

    wire [15:0] fl, fr, bl, br;
    audio_decimator #(.COEF_FILE("rtl/assets/audio-decimator-coeffs.mem")) filtered (
        .clk(clk), .enable(1'b1), .in_l(in_l), .in_r(in_r), .out_l(fl), .out_r(fr));
    audio_decimator #(.COEF_FILE("rtl/assets/audio-decimator-coeffs.mem")) bypass (
        .clk(clk), .enable(1'b0), .in_l(in_l), .in_r(in_r), .out_l(bl), .out_r(br));

    integer fd, count = 0;
    reg [8:0] div = 0;
    reg [1023:0] path;
    initial begin
        if (!$value$plusargs("out=%s", path)) path = "audio_decimator.txt";
        fd = $fopen(path, "w");
    end
    always @(posedge clk) begin
        div <= div + 9'd1;
        if (div == 9'd0) begin
            if (count >= SKIP)
                $fdisplay(fd, "%0d %0d %0d %0d", $signed(fl), $signed(fr), $signed(bl), $signed(br));
            count <= count + 1;
            if (count == SKIP + SAMPLES - 1) begin
                $fclose(fd);
                $finish;
            end
        end
    end
endmodule
