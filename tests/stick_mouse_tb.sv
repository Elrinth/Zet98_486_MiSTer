`timescale 1ns/1ps
module stick_mouse_tb;
    reg clk = 0; always #5 clk = ~clk;
    reg enable = 1;
    reg [15:0] usb_r0 = 0, usb_r1 = 0, snac_r0 = 16'h8080, snac_r1 = 16'h8080;
    reg [1:0] snac_valid = 0;
    wire signed [7:0] dx, dy;
    wire strobe;
    // 10 kHz "clock" -> 100 cycles per 100 Hz tick.
    stick_mouse #(.CLK_HZ(10000)) dut(.clk(clk), .enable(enable), .usb_r0(usb_r0), .usb_r1(usb_r1),
        .snac_valid(snac_valid), .snac_r0(snac_r0), .snac_r1(snac_r1), .dx(dx), .dy(dy), .strobe(strobe));

    integer strobes = 0;
    reg signed [7:0] lx, ly;
    always @(posedge clk) if (strobe) begin strobes = strobes + 1; lx = dx; ly = dy; end
    task tick_expect(input integer wx, input integer wy, input [8*32-1:0] what);
        integer s;
        begin
            repeat (110) @(posedge clk); s = strobes; repeat (110) @(posedge clk); #1;
            if (wx == 0 && wy == 0) begin
                if (strobes != s) $fatal(1, "%0s: unexpected movement %0d,%0d", what, lx, ly);
            end else if (strobes == s || lx != wx || ly != wy)
                $fatal(1, "%0s: got %0d,%0d (strobes %0d) want %0d,%0d", what, lx, ly, strobes - s, wx, wy);
        end
    endtask
    initial begin
        tick_expect(0, 0, "centred");
        usb_r0 = {8'd0, 8'd20}; tick_expect(0, 0, "dead zone");
        // Full right/up on USB (signed, -127 = up): (127-24)^2/256 = 41.
        usb_r0 = {8'h81, 8'h7f}; tick_expect(41, 41, "usb right+up");
        usb_r0 = {8'h7f, 8'h81}; tick_expect(-41, -41, "usb left+down");
        usb_r0 = {8'd0, 8'd64}; tick_expect(6, 0, "usb small");         // (64-24)^2/256
        usb_r0 = 0;
        // SNAC: unsigned, 00h = up, FFh = right. Ignored unless in analog mode.
        snac_r0 = {8'h00, 8'hff}; tick_expect(0, 0, "snac not analog");
        snac_valid = 2'b01; tick_expect(41, 42, "snac right+up");         // 127 -> 41, -128 -> 42
        snac_valid = 2'b11; snac_r1 = {8'h80, 8'hff}; usb_r0 = {8'd0, 8'h7f}; usb_r1 = {8'd0, 8'h7f};
        tick_expect(127, 42, "sum clamps to 127");
        enable = 0; tick_expect(0, 0, "off");
        $display("PASS: stick mouse dead zone, curve, USB/SNAC axes, analog gate, clamp, off");
        $finish;
    end
endmodule
