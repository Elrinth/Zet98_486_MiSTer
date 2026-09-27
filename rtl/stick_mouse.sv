// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Right analog stick -> PC-98 mouse movement, for USB controllers (MiSTer
// joystick_r_analog: signed, +X right, +Y down) and SNAC DualShock pads
// (unsigned, 80h centre, 00h up/left). At 100 Hz each stick outside a dead
// zone adds a quadratic amount of movement, so small deflections stay precise.
// Output is a PS/2-convention delta (+X right, +Y up) with a one-clock strobe,
// added by MOUSECONV to the real mouse's movement.
module stick_mouse #(
    parameter CLK_HZ = 90000000
) (
    input wire clk,
    input wire enable,
    input wire [15:0] usb_r0, usb_r1,          // {Y, X} signed, per player
    input wire [1:0] snac_valid,               // pad in analog mode, per port
    input wire [15:0] snac_r0, snac_r1,        // {Y, X} unsigned, per port
    output reg signed [7:0] dx = 0, dy = 0,
    output reg strobe = 0
);
    localparam integer TICK = CLK_HZ / 100;
    localparam integer DEAD = 24;

    // Signed stick value -> movement, same sign, dead zone, (a-DEAD)^2/256.
    function automatic signed [9:0] curve(input signed [8:0] v);
        reg [8:0] a;
        reg [15:0] sq;
        begin
            a = v < 0 ? -v : v;
            if (a <= DEAD) curve = 0;
            else begin
                sq = (a - DEAD) * (a - DEAD);
                curve = v < 0 ? -$signed({2'b0, sq[15:8]}) : $signed({2'b0, sq[15:8]});
            end
        end
    endfunction
    function automatic signed [8:0] usb(input [7:0] b);
        usb = $signed({b[7], b});
    endfunction
    function automatic signed [8:0] snac(input [7:0] b);
        snac = $signed({1'b0, b}) - 9'sd128;
    endfunction

    // One squaring circuit steps through the eight axis values after each
    // tick: USB X0, X1, SNAC X0, X1, then the same for Y.
    reg [$clog2(TICK+1)-1:0] count = 0;
    reg [3:0] step = 8;
    reg signed [11:0] sx, sy;
    reg signed [8:0] v;
    reg use_v;
    always @* begin
        case (step[1:0])
            0: v = usb(step[2] ? usb_r0[15:8] : usb_r0[7:0]);
            1: v = usb(step[2] ? usb_r1[15:8] : usb_r1[7:0]);
            2: v = snac(step[2] ? snac_r0[15:8] : snac_r0[7:0]);
            default: v = snac(step[2] ? snac_r1[15:8] : snac_r1[7:0]);
        endcase
        use_v = step[1] ? snac_valid[step[0]] : 1'b1;
    end
    wire signed [9:0] c = use_v ? curve(v) : 10'sd0;
    reg publish = 0;
    always @(posedge clk) begin
        strobe <= 0;
        publish <= 0;
        if (!enable) begin count <= 0; step <= 8; end
        else if (step < 8) begin
            if (!step[2]) sx <= sx + c; else sy <= sy - c;   // stick down is +, PS/2 up is +
            step <= step + 1'b1;
            publish <= step == 7;
            count <= count + 1'b1;
        end else if (count != TICK - 1) count <= count + 1'b1;
        else begin count <= 0; step <= 0; sx <= 0; sy <= 0; end
        if (publish) begin
            dx <= sx > 127 ? 8'sd127 : sx < -127 ? -8'sd127 : sx[7:0];
            dy <= sy > 127 ? 8'sd127 : sy < -127 ? -8'sd127 : sy[7:0];
            strobe <= sx != 0 || sy != 0;
        end
    end
endmodule
