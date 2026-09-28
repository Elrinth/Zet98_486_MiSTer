`timescale 1ns/1ps
// Two modelled PlayStation pads on the SNAC pins: port 1 digital (ID 41h),
// port 2 DualShock in analog mode (ID 73h). DAT is open collector with a
// pull-up; each pad drives it only while its ATT is low. With ds1 set, port 1
// is a DualShock in digital mode that follows the 43h/44h/43h setup.
module snac_psx_pad_tb;
    reg clk = 0; always #100 clk = ~clk;          // 5 MHz keeps the sim short
    reg enable = 0;
    wire [6:0] user_out;
    wire [5:0] joy1, joy2;
    wire [1:0] analog, mbtn1, mbtn2;
    wire [15:0] right1, right2;
    wire att1 = user_out[1], att2 = user_out[0], cmd = user_out[2], sclk = user_out[5];
    reg dat1 = 1, dat2 = 1;
    reg present1 = 1, present2 = 1;
    wire dat = (present1 ? dat1 : 1'b1) & (present2 ? dat2 : 1'b1);
    // Port 2 answers each byte but the last with a 2 us ACK pulse 8 us later
    // (as a DualShock does); port 1 sends no ACK (timeout path).
    reg ack2 = 1;
    wire [6:0] user_in = {1'b1, 1'b1, dat, ack2, 3'b111};
    realtime att2_fall, att2_low_max = 0;
    always @(negedge att2) att2_fall = $realtime;
    always @(posedge att2) if (present2 && $realtime - att2_fall > att2_low_max) att2_low_max = $realtime - att2_fall;
    snac_psx_pad #(.CLK_HZ(5000000)) dut(.clk(clk), .enable(enable), .user_in(user_in),
        .user_out(user_out), .joy1(joy1), .joy2(joy2),
        .analog(analog), .right1(right1), .right2(right2), .mbtn1(mbtn1), .mbtn2(mbtn2));

    reg [7:0] resp1[0:8], resp2[0:8];
    reg [7:0] got1[0:8], got2[0:8];
    integer b1 = 0, k1 = 0, b2 = 0, k2 = 0, polls1 = 0, polls2 = 0;
    // Port 1 DualShock model: mode state and setup transactions seen.
    reg ds1 = 0, cfg1 = 0, mode1 = 0;
    reg [7:0] lock1 = 0;
    integer setup1 = 0, setup2 = 0, base1 = 0;
    function automatic [7:0] pad1_byte(input integer n);
        pad1_byte = (n == 1 && ds1) ? (cfg1 ? 8'hf3 : mode1 ? 8'h73 : 8'h41) : resp1[n];
    endfunction
    wire [3:0] len1 = (ds1 && (cfg1 || mode1)) ? 4'd9 : 4'd5;
    // Pad side: present the next bit on each falling edge, capture CMD on rising.
    always @(negedge att1) begin b1 = 0; k1 = 0; polls1 = polls1 + 1; end
    always @(negedge att2) begin b2 = 0; k2 = 0; polls2 = polls2 + 1; end
    always @(negedge sclk) begin
        if (!att1) dat1 = b1 < len1 ? pad1_byte(b1) >> k1 : 1'b1;   // digital pad: 5 bytes
        if (!att2) dat2 = resp2[b2][k2];
    end
    always @(posedge sclk) begin
        if (!att1) begin got1[b1][k1] = cmd; k1 = k1 + 1; if (k1 == 8) begin k1 = 0; b1 = b1 + 1; end end
        if (!att2) begin
            got2[b2][k2] = cmd; k2 = k2 + 1;
            if (k2 == 8) begin
                k2 = 0; b2 = b2 + 1;
                if (b2 < 9 && present2) fork begin #8000; ack2 = 0; #2000; ack2 = 1; end join_none
            end
        end
    end
    always @(posedge att1) begin
        dat1 = 1;
        if (b1 >= 2 && got1[1] != 8'h42) begin
            setup1 = setup1 + 1;
            if (ds1) begin
                if (got1[1] == 8'h43) cfg1 = got1[3] == 8'h01;
                else if (got1[1] == 8'h44 && cfg1) begin mode1 = got1[3] == 8'h01; lock1 = got1[4]; end
            end
        end
    end
    always @(posedge att2) begin
        dat2 = 1;
        if (b2 >= 2 && got2[1] != 8'h42) setup2 = setup2 + 1;
    end
    always @(posedge clk) if (!att1 && !att2) $fatal(1, "both ports selected");

    task wait_polls(input integer n);
        integer s1, s2;
        begin
            s1 = polls1; s2 = polls2;
            wait (polls1 >= s1 + n && polls2 >= s2 + n);
            wait (att1 && att2);
            repeat (20) @(posedge clk);
        end
    endtask
    task check_joy(input [5:0] w1, input [5:0] w2, input [8*40-1:0] what);
        if (joy1 !== w1 || joy2 !== w2)
            $fatal(1, "%0s: joy1=%b (want %b) joy2=%b (want %b)", what, joy1, w1, joy2, w2);
    endtask
    integer i;
    initial begin
        // Idle pads: no buttons, sticks centred.
        resp1[0]=8'hff; resp1[1]=8'h41; resp1[2]=8'h5a; resp1[3]=8'hff; resp1[4]=8'hff;
        for (i=5;i<9;i=i+1) resp1[i]=8'hff;
        resp2[0]=8'hff; resp2[1]=8'h73; resp2[2]=8'h5a; resp2[3]=8'hff; resp2[4]=8'hff;
        resp2[5]=8'h80; resp2[6]=8'h80; resp2[7]=8'h80; resp2[8]=8'h80;
        repeat (50) @(posedge clk);
        if (user_out !== 7'h7f) $fatal(1, "disabled SNAC drove the user port");
        enable = 1;
        // Port 1 answers in digital mode: one read, three setup transactions
        // (ignored by this digital-only pad), then plain reads again.
        wait_polls(5);
        check_joy(0, 0, "idle pads");
        if (setup1 != 3 || setup2 != 0)
            $fatal(1, "setup transactions: port 1 %0d (want 3), port 2 %0d (want 0)", setup1, setup2);
        for (i=0;i<9;i=i+1)
            if (got1[i] !== (i==0 ? 8'h01 : i==1 ? 8'h42 : 8'h00) && i < 5)
                $fatal(1, "port 1 command byte %0d = %h", i, got1[i]);
        if (got2[0] !== 8'h01 || got2[1] !== 8'h42 || got2[4] !== 8'h00) $fatal(1, "port 2 command bytes");
        // Port 1: Up (lo bit 4) + Cross (hi bit 6). Port 2: stick right + Circle.
        resp1[3] = 8'hef; resp1[4] = 8'hbf;
        resp2[7] = 8'hff; resp2[4] = 8'hdf;
        wait_polls(2);
        check_joy(6'b010000 | 6'b001000, 6'b100000 | 6'b000001, "up+cross / stick right+circle");
        // Port 1: Left + Square. Port 2: d-pad down + Triangle, stick up.
        resp1[3] = 8'h7f; resp1[4] = 8'h7f;
        resp2[3] = 8'hbf; resp2[4] = 8'hef; resp2[7] = 8'h80; resp2[8] = 8'h00;
        wait_polls(2);
        check_joy(6'b010010, 6'b101100, "left+square / down+up+triangle");
        // Digital pad's missing analog bytes must not create stick input.
        resp1[3] = 8'hff; resp1[4] = 8'hff; resp1[7] = 8'h00; resp1[8] = 8'h00;
        resp2[3] = 8'hff; resp2[4] = 8'hff; resp2[8] = 8'h80;
        wait_polls(2);
        check_joy(0, 0, "released");
        // Mouse emulation: right stick of the analog pad, L1 / R3 as buttons.
        resp2[5] = 8'h20; resp2[6] = 8'he0; resp1[4] = 8'hfb; resp2[3] = 8'hfb;
        wait_polls(2);
        if (analog !== 2'b10 || right2 !== 16'he020 || mbtn1 !== 2'b01 || mbtn2 !== 2'b10)
            $fatal(1, "mouse outputs: analog=%b right2=%h mbtn1=%b mbtn2=%b", analog, right2, mbtn1, mbtn2);
        resp2[5] = 8'h80; resp2[6] = 8'h80; resp1[4] = 8'hff; resp2[3] = 8'hff;
        wait_polls(2);
        if (mbtn1 !== 0 || mbtn2 !== 0) $fatal(1, "mouse buttons stuck");
        // A device without the 5Ah handshake is not a pad: no input.
        resp1[2] = 8'h00; resp1[3] = 8'h00; resp1[4] = 8'h00;
        wait_polls(2);
        check_joy(0, 0, "no 5Ah handshake");
        resp1[2] = 8'h5a; resp1[3] = 8'hff; resp1[4] = 8'hff;
        // A brief misread is not an unplug: no second setup.
        wait_polls(5);
        base1 = setup1;
        wait_polls(4);
        if (base1 != 3 || setup1 != base1) $fatal(1, "digital-only pad setups %0d/%0d after a misread (want 3)", base1, setup1);
        // A DualShock plugged into port 1 in digital mode is switched to
        // analog, unlocked, once; the ANALOG button then stays in charge.
        present1 = 0;
        wait_polls(70);                 // unplugged for ~0.6 s
        ds1 = 1; cfg1 = 0; mode1 = 0;
        for (i=5;i<9;i=i+1) resp1[i]=8'h80;
        present1 = 1;
        wait_polls(6);
        if (setup1 != base1 + 3 || !mode1 || lock1 !== 8'h02 || cfg1)
            $fatal(1, "DualShock setup: setups=%0d mode=%b lock=%h cfg=%b", setup1, mode1, lock1, cfg1);
        if (analog !== 2'b11) $fatal(1, "DualShock not reported in analog mode: %b", analog);
        resp1[5] = 8'h10; resp1[6] = 8'hf0;
        wait_polls(2);
        if (right1 !== 16'hf010) $fatal(1, "port 1 right stick %h", right1);
        mode1 = 0;                      // user presses ANALOG: back to digital
        wait_polls(4);
        if (setup1 != base1 + 3 || analog[0] !== 0) $fatal(1, "ANALOG toggle overridden: setups=%0d analog=%b", setup1, analog);
        // A misread right after the ANALOG press must not force analog again.
        resp1[2] = 8'h00; wait_polls(2); resp1[2] = 8'h5a;
        wait_polls(6);
        if (setup1 != base1 + 3 || mode1) $fatal(1, "misread re-ran the setup after ANALOG: setups=%0d mode=%b", setup1, mode1);
        ds1 = 0; resp1[5] = 8'h80; resp1[6] = 8'h80;
        // Unplugged ports read FFh (pull-up) and report nothing.
        present1 = 0; present2 = 0;
        wait_polls(2);
        check_joy(0, 0, "no pads");
        enable = 0; repeat (10) @(posedge clk);
        if (user_out !== 7'h7f || joy1 !== 0 || joy2 !== 0) $fatal(1, "disable did not release port");
        $display("PASS: SNAC PlayStation pads: ACK ignored, 01/42 polling, DualShock analog setup once per plug-in (unlocked, misreads ignored), digital+analog mapping, 5Ah handshake, right stick/mouse buttons, both ports, unplugged, off");
        $finish;
    end
    initial begin #6000000000; $fatal(1, "SNAC timeout"); end
endmodule
