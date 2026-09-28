// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// PlayStation controllers on the MiSTer user port (SNAC), standard pinout:
//   USER_OUT[1] ATT port 1, USER_OUT[0] ATT port 2 (active low)
//   USER_OUT[2] CMD, USER_OUT[5] CLK, USER_IN[4] DAT, USER_IN[3] ACK (unused)
// Polls both ports alternately (~60 Hz each) with the standard 0x01 0x42 read
// at 250 kHz: CMD/DAT change on the falling clock edge and are sampled on the
// rising edge, bytes LSB first, a fixed gap instead of waiting for ACK
// (waiting for USER_IN[3] corrupted a DualShock 2's 5Ah byte on hardware).
// Reports MiSTer joystick bits: 0 right, 1 left, 2 down, 3 up, 4 fire 1,
// 5 fire 2. D-pad plus the left stick (analog mode) give the directions;
// Cross/Square are fire 1, Circle/Triangle fire 2. A missing pad reads as
// 0xFF/ID 0xFF and reports nothing pressed.
// A pad that answers in digital mode (ID 41h) is switched to analog once per
// plug-in, as analog PlayStation games do: 43h enter config, 44h analog
// (unlocked, so the ANALOG button still toggles it), 43h exit. The right
// stick (PC-98 mouse) needs analog mode. A digital-only pad ignores this.
module snac_psx_pad #(
    parameter CLK_HZ = 90000000
) (
    input wire clk,
    input wire enable,
    input wire [6:0] user_in,
    output reg [6:0] user_out = 7'h7f,
    output reg [5:0] joy1 = 0,
    output reg [5:0] joy2 = 0,
    // Mouse emulation: right stick {Y, X} (unsigned, 80h centre) of pads in
    // analog mode, and mouse buttons {right, left} = {R3|R1, L3|L1}.
    output reg [1:0] analog = 0,
    output reg [15:0] right1 = 16'h8080, right2 = 16'h8080,
    output reg [1:0] mbtn1 = 0, mbtn2 = 0,
    // Debug (trace builds): port 1's last read, {ID, 5Ah, buttons lo/hi,
    // right X/Y, left X/Y}.
    output reg [63:0] raw1 = 0
);
    localparam integer HALF = CLK_HZ / 500000;        // 2 us: 250 kHz clock
    localparam integer GAP = CLK_HZ / 50000;          // 20 us between bytes
    localparam integer FRAME = CLK_HZ / 120;          // one port per 8.3 ms
    localparam BYTES = 9;

    reg [1:0] dat_sync = 2'b11;
    reg [1:0] en_sync = 0;
    always @(posedge clk) begin
        dat_sync <= {dat_sync[0], user_in[4]};
        en_sync <= {en_sync[0], enable};
    end

    localparam IDLE=0, SELECT=1, LOW=2, HIGH=3, NEXT=4, DONE=5;
    reg [2:0] state = IDLE;
    reg port = 0;
    reg [23:0] timer = 0;
    reg [3:0] byte_index = 0;
    reg [2:0] bit_index = 0;
    reg [7:0] tx = 0, rx = 0;
    reg [7:0] id, handshake, buttons_lo, buttons_hi, left_x, left_y, right_x, right_y;
    reg att = 1, cmd = 1, sclk = 1;
    // Per port: setup step to send next (0 = plain read) and whether this
    // plug-in has been set up already.
    reg [1:0] step1 = 0, step2 = 0, step = 0;
    reg [1:0] configured = 0;

    function automatic [7:0] command(input [1:0] st, input [3:0] index);
        case (st)
            2'd1: command = index == 0 ? 8'h01 : index == 1 ? 8'h43 : index == 3 ? 8'h01 : 8'h00;
            2'd2: command = index == 0 ? 8'h01 : index == 1 ? 8'h44 : index == 3 ? 8'h01 :
                            index == 4 ? 8'h02 : 8'h00;
            2'd3: command = index == 0 ? 8'h01 : index == 1 ? 8'h43 : index >= 4 ? 8'h5a : 8'h00;
            default: command = index == 0 ? 8'h01 : index == 1 ? 8'h42 : 8'h00;
        endcase
    endfunction

    // Stick outside the centre third counts as a direction.
    wire analog_mode = id == 8'h73;
    wire st_left  = analog_mode && left_x < 8'h40, st_right = analog_mode && left_x > 8'hc0;
    wire st_up    = analog_mode && left_y < 8'h40, st_down  = analog_mode && left_y > 8'hc0;
    // A real pad answers the 42h read with its ID and then 5Ah.
    wire present  = id != 8'hff && id != 8'h00 && handshake == 8'h5a;
    // L3/L1 = left mouse button, R3/R1 = right (buttons active low).
    wire [1:0] mouse_buttons = !present ? 2'b0 :
        {!buttons_lo[2] || !buttons_hi[3], !buttons_lo[1] || !buttons_hi[2]};
    // Buttons are active low.
    wire [5:0] mapped = !present ? 6'b0 : {
        !buttons_hi[5] || !buttons_hi[4],                   // fire 2: Circle, Triangle
        !buttons_hi[6] || !buttons_hi[7],                   // fire 1: Cross, Square
        !buttons_lo[4] || st_up,                            // up
        !buttons_lo[6] || st_down,                          // down
        !buttons_lo[7] || st_left,                          // left
        !buttons_lo[5] || st_right                          // right
    };

    always @(posedge clk) begin
        if (!en_sync[1]) begin
            state <= IDLE; timer <= 0; att <= 1; cmd <= 1; sclk <= 1;
            joy1 <= 0; joy2 <= 0; user_out <= 7'h7f;
            analog <= 0; mbtn1 <= 0; mbtn2 <= 0;
            step1 <= 0; step2 <= 0; configured <= 0;
        end else begin
            user_out <= {1'b1, sclk, 1'b1, 1'b1, cmd, port ? 1'b1 : att, port ? att : 1'b1};
            if (timer != 0) timer <= timer - 1'b1;
            else case (state)
                IDLE: begin
                    att <= 0; byte_index <= 0; state <= SELECT; timer <= GAP;
                    step <= port ? step2 : step1;
                end
                SELECT: begin
                    tx <= command(step, byte_index); bit_index <= 0; state <= LOW;
                end
                LOW: begin                      // falling edge: present CMD bit
                    sclk <= 0; cmd <= tx[bit_index]; timer <= HALF; state <= HIGH;
                end
                HIGH: begin                     // rising edge: sample DAT
                    sclk <= 1; rx <= {dat_sync[1], rx[7:1]}; timer <= HALF;
                    if (bit_index == 7) state <= NEXT;
                    else begin bit_index <= bit_index + 1'b1; state <= LOW; end
                end
                NEXT: begin
                    cmd <= 1;
                    if (step == 0) case (byte_index)
                        1: id <= rx;
                        2: handshake <= rx;
                        3: buttons_lo <= rx;
                        4: buttons_hi <= rx;
                        5: right_x <= rx;
                        6: right_y <= rx;
                        7: left_x <= rx;
                        8: left_y <= rx;
                        default: ;
                    endcase
                    if (byte_index == BYTES-1) begin state <= DONE; timer <= GAP; end
                    else begin byte_index <= byte_index + 1'b1; state <= SELECT; timer <= GAP; end
                end
                DONE: begin
                    att <= 1;
                    if (step != 0) begin
                        // Setup transaction: outputs keep the last read.
                        if (port) step2 <= step + 1'b1; else step1 <= step + 1'b1;
                        if (step == 3) configured[port] <= 1;
                    end else begin
                        if (!present) configured[port] <= 0;
                        else if (!configured[port] && id == 8'h41) begin
                            if (port) step2 <= 1; else step1 <= 1;
                        end
                    end
                    if (step == 0 && port) begin
                        joy2 <= mapped; mbtn2 <= mouse_buttons;
                        analog[1] <= present && analog_mode; right2 <= {right_y, right_x};
                    end else if (step == 0) begin
                        raw1 <= {id, handshake, buttons_lo, buttons_hi, right_x, right_y, left_x, left_y};
                        joy1 <= mapped; mbtn1 <= mouse_buttons;
                        analog[0] <= present && analog_mode; right1 <= {right_y, right_x};
                    end
                    port <= !port; state <= IDLE; timer <= FRAME;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
