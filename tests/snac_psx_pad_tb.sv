`timescale 1ns/1ps
// Two modelled PlayStation pads on the SNAC pins: port 1 digital (ID 41h),
// port 2 DualShock in analog mode (ID 73h). DAT is open collector with a
// pull-up; each pad drives it only while its ATT is low.
module snac_psx_pad_tb;
    reg clk = 0; always #100 clk = ~clk;          // 5 MHz keeps the sim short
    reg enable = 0;
    wire [6:0] user_out;
    wire [5:0] joy1, joy2;
    wire att1 = user_out[1], att2 = user_out[0], cmd = user_out[2], sclk = user_out[5];
    reg dat1 = 1, dat2 = 1;
    reg present1 = 1, present2 = 1;
    wire dat = (present1 ? dat1 : 1'b1) & (present2 ? dat2 : 1'b1);
    wire [6:0] user_in = {1'b1, 1'b1, dat, 1'b1, 3'b111};
    snac_psx_pad #(.CLK_HZ(5000000)) dut(.clk(clk), .enable(enable), .user_in(user_in),
        .user_out(user_out), .joy1(joy1), .joy2(joy2));

    reg [7:0] resp1[0:8], resp2[0:8];
    reg [7:0] got1[0:8], got2[0:8];
    integer b1 = 0, k1 = 0, b2 = 0, k2 = 0, polls1 = 0, polls2 = 0;
    // Pad side: present the next bit on each falling edge, capture CMD on rising.
    always @(negedge att1) begin b1 = 0; k1 = 0; polls1 = polls1 + 1; end
    always @(negedge att2) begin b2 = 0; k2 = 0; polls2 = polls2 + 1; end
    always @(negedge sclk) begin
        if (!att1) dat1 = b1 < 5 ? resp1[b1][k1] : 1'b1;   // digital pad: 5 bytes
        if (!att2) dat2 = resp2[b2][k2];
    end
    always @(posedge sclk) begin
        if (!att1) begin got1[b1][k1] = cmd; k1 = k1 + 1; if (k1 == 8) begin k1 = 0; b1 = b1 + 1; end end
        if (!att2) begin got2[b2][k2] = cmd; k2 = k2 + 1; if (k2 == 8) begin k2 = 0; b2 = b2 + 1; end end
    end
    always @(posedge att1) dat1 = 1;
    always @(posedge att2) dat2 = 1;
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
        wait_polls(2);
        check_joy(0, 0, "idle pads");
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
        // Unplugged ports read FFh (pull-up) and report nothing.
        present1 = 0; present2 = 0;
        wait_polls(2);
        check_joy(0, 0, "no pads");
        enable = 0; repeat (10) @(posedge clk);
        if (user_out !== 7'h7f || joy1 !== 0 || joy2 !== 0) $fatal(1, "disable did not release port");
        $display("PASS: SNAC PlayStation pads: 01/42 polling, digital+analog mapping, both ports, unplugged, off");
        $finish;
    end
    initial begin #2000000000; $fatal(1, "SNAC timeout"); end
endmodule
