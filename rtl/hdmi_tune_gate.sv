// SPDX-License-Identifier: GPL-3.0-or-later
// Keep scaler measurement clocks running; configuration only gates data/CE.
// Enable is registered in the input-video domain before reaching that logic.
module hdmi_tune_gate (
    input wire enable,
    input wire [15:0] raw_tune,
    output wire [15:0] gated_tune
);
    reg [1:0] enable_video = 2'b00;
    always @(posedge raw_tune[6]) enable_video <= {enable_video[0], enable};
    // Bits 6 and 7 are clocks. Gating them with a configuration bit can
    // create a spurious rising edge when it changes while a clock is high.
    assign gated_tune = {raw_tune[15:8] & {8{enable_video[1]}},
                         raw_tune[7:6],
                         raw_tune[5:0] & {6{enable_video[1]}}};
endmodule
