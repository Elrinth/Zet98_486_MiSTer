`timescale 1ns/1ps
// CD trace logger: drive events through the trace port, decode the UART
// output and compare the text lines.
module cd_trace_tb;
    localparam integer CLK_HZ = 11520000;          // 100 clocks per bit, 11.52 clocks per us
    reg clk = 0; always #43.4 clk = ~clk;
    reg [91:0] trace = 0;
    reg hdd = 0, fdd = 0;
    reg [63:0] pad1 = 0;
    wire tx;
    pc98_cd_trace #(.CLK_HZ(CLK_HZ)) dut(.clk(clk), .trace(trace), .hdd_busy(hdd), .fdd_busy(fdd), .pad1(pad1), .video(72'h0),
        .pcm_ctl(1'b0), .pcm_port(8'h0), .pcm_data(8'h0), .pcm_push(1'b0),
        .gfx_wr(1'b0), .gfx_reg(4'h0), .gfx_data(16'h0),
        .cpu_sample(64'h0), .frame_ev(1'b0), .frame_data(72'h0), .tx(tx));

    // UART receiver model: sample mid-bit.
    string text = "";
    reg [7:0] buffer[0:4095];
    integer count = 0;
    // Does the received text contain want (bytes, MSB first)?
    function automatic integer contains(input [8*40-1:0] want, input integer len);
        integer p, i, ok;
        begin
            contains = 0;
            for (p = 0; p + len <= count; p = p + 1) begin
                ok = 1;
                for (i = 0; i < len; i = i + 1)
                    if (buffer[p + i] !== want[8*(len-1-i) +: 8]) ok = 0;
                if (ok) contains = contains + 1;
            end
        end
    endfunction
    always begin
        @(negedge tx);
        repeat (50) @(posedge clk);
        if (tx !== 0) $fatal(1, "bad start bit");
        begin
            reg [7:0] c;
            for (int i = 0; i < 8; i++) begin repeat (100) @(posedge clk); c[i] = tx; end
            repeat (100) @(posedge clk);
            if (tx !== 1) $fatal(1, "bad stop bit");
            text = {text, string'(c)};
            buffer[count] = c; count = count + 1;
        end
    end

    task set_status(input [7:0] s); trace[90:83] = s; endtask
    task wait_ms(input integer n); repeat (n * (CLK_HZ / 1000)) @(posedge clk); endtask
    initial begin
        set_status(8'h15);
        wait_ms(2);
        // PLAY AUDIO MSF: 47 00 00 02 00 00 05 00 00 00
        @(posedge clk);
        trace[80:1] = {8'h00, 8'h00, 8'h00, 8'h05, 8'h00, 8'h00, 8'h02, 8'h00, 8'h00, 8'h47};
        trace[0] = 1; @(posedge clk); trace[0] = 0;
        set_status(8'h11);
        // A slow fetch (13 ms) while the HDD is busy.
        wait_ms(1); trace[81] = 1; hdd = 1; wait_ms(13); hdd = 0; trace[81] = 0;
        // A quick fetch (6 ms) is not reported.
        wait_ms(1); trace[81] = 1; wait_ms(6); trace[81] = 0;
        // READ SUB-CHANNEL polled five times, then another command: one C
        // line, "R 00 04", then the new command.
        repeat (5) begin
            trace[80:1] = {8'h00, 8'h00, 8'h10, 8'h00, 8'h00, 8'h00, 8'h01, 8'h40, 8'h02, 8'h42};
            trace[0] = 1; @(posedge clk); trace[0] = 0; repeat (200) @(posedge clk);
        end
        trace[80:1] = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00};
        trace[0] = 1; @(posedge clk); trace[0] = 0;
        // Starvation for 3 ms.
        wait_ms(1); trace[82] = 1; wait_ms(3); trace[82] = 0;
        // Pad bytes: a change is reported; a second change within 100 ms waits.
        pad1 = 64'h735affff_7f80_8080; wait_ms(5); pad1 = 64'h735affff_ff80_8080;
        wait_ms(140);
        $display("%s", text);
        if (text.len() == 0) $fatal(1, "no output");
        if (contains(" C 47 00 00 02 00 00 05 00 00 00", 32) != 1) $fatal(1, "command line");
        if (contains(" S 11", 5) != 1) $fatal(1, "status line");
        if (contains(" F 00 0d 01", 11) != 1) $fatal(1, "slow fetch line");
        if (contains(" F ", 3) != 1) $fatal(1, "short fetch must not be reported");
        if (contains(" U", 2) != 1) $fatal(1, "starvation start line");
        if (contains(" u 00 03", 8) != 1) $fatal(1, "starvation end line");
        if (contains(" C 42 02 40 01 00 00 00 10 00 00", 32) != 1) $fatal(1, "first 42h line");
        if (contains(" R 00 04", 8) != 1) $fatal(1, "repeat count line");
        if (contains(" C 00 00 00 00 00 00 00 00 00 00", 32) != 1) $fatal(1, "command after repeats");
        if (contains(" P 73 5a ff ff 7f 80 80 80", 26) != 1) $fatal(1, "first pad line");
        if (contains(" P 73 5a ff ff ff 80 80 80", 26) != 1) $fatal(1, "second pad line (after the 100 ms limit)");
        $display("PASS: CD trace logger: command, status, slow fetch with HDD flag, starvation start/end, rate-limited pad bytes, repeated 42h counted");
        $finish;
    end
    initial begin #2000000000; $fatal(1, "timeout"); end
endmodule
