`timescale 1ns/1ps
// ATAPI CD-ROM unit test: drives the task file like NECCDD.SYS and serves an
// image (ISO or raw 2352-byte BIN) through a MiSTer-style block host.
module atapi_tb;
    reg clk = 0; always #5 clk = ~clk;
    reg reset = 1;
    reg [2:0] reg_index = 0;
    reg reg_write = 0, reg_read = 0, word_access = 0, ctrl_write = 0, read_alt = 0;
    reg [15:0] writedata = 0;
    reg [7:0] ctrl_data = 0;
    wire [15:0] readdata;
    wire irq, present;
    reg image_mounted = 0;
    reg [63:0] image_size = 0;
    wire [31:0] sd_lba;
    wire sd_rd;
    wire [5:0] sd_blk_cnt;
    wire [1:0] activity;
    wire [91:0] trace;
    reg sd_ack = 0, sd_buff_wr = 0;
    reg [8:0] sd_buff_addr = 0;
    reg [7:0] sd_buff_dout = 0;
    wire signed [15:0] audio_l, audio_r;
    // 20 clocks per 44.1 kHz sample keeps the audio checks short.
    pc98_atapi #(.CLK_HZ(44100 * 20)) dut(.*);

    reg [7:0] image[0:2097151];
    integer raw_mode, sectors, pcd_mode;
    // Host: serve one 512-byte block per request.
    always @(posedge clk) begin
        if (sd_rd && !sd_ack) begin
            repeat (3) @(posedge clk);
            sd_ack <= 1;
            for (integer i = 0; i < 512 * (sd_blk_cnt + 1); i = i + 1) begin
                @(posedge clk);
                sd_buff_addr <= i; sd_buff_dout <= img_byte(sd_lba * 512 + i); sd_buff_wr <= 1;
            end
            @(posedge clk); sd_buff_wr <= 0;
            @(posedge clk); sd_ack <= 0;
        end
    end

    // ISO/BIN bytes are computed (large discs); PCD comes from the array.
    function automatic [7:0] img_byte(input integer a);
        integer l, o;
        begin
            if (pcd_mode) img_byte = image[a];
            else if (raw_mode) begin
                l = a / 2352; o = a % 2352;
                img_byte = o < 16 ? ((o == 0 || o == 11) ? 8'h00 : 8'hff) : o < 2064 ? data_byte(l, o - 16) : 8'h5a;
            end else img_byte = data_byte(a / 2048, a % 2048);
        end
    endfunction
    task wr(input [2:0] r, input [15:0] v, input word);
        begin
            @(negedge clk); reg_index = r; writedata = v; word_access = word; reg_write = 1;
            @(negedge clk); reg_write = 0; word_access = 0;
        end
    endtask
    task rd(input [2:0] r, input word, output [15:0] v);
        begin
            @(negedge clk); reg_index = r; word_access = word; #1 v = readdata;
            reg_read = 1; @(negedge clk); reg_read = 0; word_access = 0;
        end
    endtask
    task wait_irq(input [8*40-1:0] what);
        integer t;
        begin
            t = 0;
            while (!irq) begin @(posedge clk); t = t + 1; if (t > 200000) $fatal(1, "no IRQ: %0s", what); end
        end
    endtask
    reg [15:0] v, st;
    reg [7:0] resp[0:4095];
    integer n;
    task packet(input [8*12-1:0] cdb);
        integer i;
        begin
            wr(6, 16'h00a0, 0);        // master
            wr(4, 16'h0000, 0); wr(5, 16'h0008, 0);
            wr(7, 16'h00a0, 0);
            rd(7, 0, st); if ((st & 8'h88) != 8'h08) $fatal(1, "no DRQ for packet: %h", st);
            for (i = 0; i < 6; i = i + 1) wr(0, {cdb[8*(10-2*i) +: 8], cdb[8*(11-2*i) +: 8]}, 1);
        end
    endtask
    // Collect a data-in phase: returns byte count; checks IRQ/reason/status.
    task data_in(input [8*40-1:0] what, output integer bytes);
        integer i, words;
        begin
            wait_irq(what);
            rd(2, 0, v); if (v[7:0] !== 8'h02) $fatal(1, "%0s: reason %h", what, v[7:0]);
            rd(4, 0, v); bytes = v[7:0]; rd(5, 0, v); bytes = bytes + 256 * v[7:0];
            rd(7, 0, st); if (st[7:0] !== 8'h58) $fatal(1, "%0s: status %h", what, st[7:0]);
            words = (bytes + 1) / 2;
            for (i = 0; i < words; i = i + 1) begin
                rd(0, 1, v); resp[2*i] = v[7:0]; resp[2*i+1] = v[15:8];
            end
        end
    endtask
    task done_ok(input [8*40-1:0] what);
        begin
            wait_irq(what);
            rd(2, 0, v); if (v[7:0] !== 8'h03) $fatal(1, "%0s: done reason %h", what, v[7:0]);
            rd(7, 0, st); if (st[7:0] !== 8'h50) $fatal(1, "%0s: done status %h", what, st[7:0]);
        end
    endtask
    task done_err(input [8*40-1:0] what, input [3:0] key);
        begin
            wait_irq(what);
            rd(1, 0, v); if (v[7:4] !== key) $fatal(1, "%0s: error %h want key %h", what, v[7:0], key);
            rd(7, 0, st); if (st[7:0] !== 8'h51) $fatal(1, "%0s: err status %h", what, st[7:0]);
        end
    endtask
    function [7:0] data_byte(input integer lba, input integer i);
        data_byte = (lba * 7 + i * 13 + (i >> 8)) & 255;
    endfunction
    function [7:0] bcd(input integer x);
        bcd = (x / 10) * 16 + x % 10;
    endfunction

    integer lba, i, bytes, frames;
    // ---- PCD disc: track 1 data (0-49), track 2 audio (50-79), track 3 audio (80-99)
    function [15:0] smp_l(input integer lba, input integer k); smp_l = lba * 600 + k + 1; endfunction
    function [15:0] smp_r(input integer lba, input integer k); smp_r = ~(lba * 600 + k); endfunction
    task put32le(input integer a, input [31:0] v); for (integer j = 0; j < 4; j++) image[a + j] = v >> (8 * j); endtask
    task build_pcd;
        integer t, l, f, base;
        integer starts[0:3];
        reg [7:0] ctl[0:3];
        reg [63:0] magic;
        begin
            magic = "PC98CD01";
            starts[0] = 0; starts[1] = 50; starts[2] = 80; starts[3] = 100;
            ctl[0] = 8'h14; ctl[1] = 8'h10; ctl[2] = 8'h10; ctl[3] = 8'h10;
            for (i = 0; i < 2352; i++) image[i] = 0;
            for (i = 0; i < 8; i++) image[i] = magic >> (8 * (7 - i));
            image[8] = 3; image[9] = 1; put32le(12, 100);
            for (t = 0; t < 4; t++) begin
                l = starts[t]; f = l + 150;
                put32le(16 + 4 * t, ctl[t] | (l << 8));
                image[512 + 4 * t] = 0; image[513 + 4 * t] = 0; image[514 + 4 * t] = l >> 8; image[515 + 4 * t] = l;
                image[1024 + 4 * t] = 0; image[1025 + 4 * t] = f / 4500; image[1026 + 4 * t] = (f / 75) % 60; image[1027 + 4 * t] = f % 75;
                image[1536 + 4 * t] = 0; image[1537 + 4 * t] = bcd(f / 4500); image[1538 + 4 * t] = bcd((f / 75) % 60); image[1539 + 4 * t] = bcd(f % 75);
            end
            for (lba = 0; lba < 100; lba++) begin
                base = 2352 * (lba + 1);
                if (lba < 50) begin
                    for (i = 0; i < 16; i++) image[base + i] = (i == 0 || i == 11) ? 0 : 8'hff;
                    image[base + 15] = 1;
                    for (i = 0; i < 2048; i++) image[base + 16 + i] = data_byte(lba, i);
                end else for (i = 0; i < 588; i++) begin
                    image[base + 4 * i] = smp_l(lba, i); image[base + 4 * i + 1] = smp_l(lba, i) >> 8;
                    image[base + 4 * i + 2] = smp_r(lba, i); image[base + 4 * i + 3] = smp_r(lba, i) >> 8;
                end
            end
        end
    endtask
    // Audio monitor: every new output sample is checked against the expected stream.
    integer exp_lba, exp_k, got = 0;
    reg monitor = 0;
    reg [15:0] last_l = 0;
    always @(posedge clk) if (monitor && audio_l !== last_l && audio_l !== 16'd0) begin
        last_l = audio_l;
        if (audio_l !== smp_l(exp_lba, exp_k) || audio_r !== smp_r(exp_lba, exp_k))
            $fatal(1, "audio sample %0d of lba %0d: %h/%h want %h/%h", exp_k, exp_lba, audio_l, audio_r, smp_l(exp_lba, exp_k), smp_r(exp_lba, exp_k));
        got = got + 1; exp_k = exp_k + 1;
        if (exp_k == 588) begin exp_k = 0; exp_lba = exp_lba + 1; end
    end
    task subq(output [7:0] astat);
        begin
            packet({8'h42, 8'h02, 8'h40, 8'h01, 24'h0, 16'd16, 24'h0}); data_in("subq", bytes);
            if (bytes != 16) $fatal(1, "subq bytes %0d", bytes);
            astat = resp[1];
            done_ok("subq done");
        end
    endtask
    task wait_status(input [7:0] want, input integer limit);
        reg [7:0] a;
        integer t;
        begin
            t = 0;
            a = 0;
            while (a !== want) begin
                subq(a); t = t + 1;
                if (t > limit) $fatal(1, "audio status %h never became %h", a, want);
                repeat (2000) @(negedge clk);
            end
        end
    endtask
    task pcd_tests;
        reg [7:0] a;
        integer w;
        begin
            // READ CAPACITY: last LBA 99.
            packet({8'h25, 88'h0}); data_in("cap", bytes);
            if ({resp[0], resp[1], resp[2], resp[3]} !== 99) $fatal(1, "capacity %h%h", resp[2], resp[3]);
            done_ok("cap done");
            // READ TOC, LBA: tracks 1-3 + lead-out.
            packet({8'h43, 8'h00, 32'h0, 8'd0, 16'h0100, 8'h00, 16'h0}); data_in("toc lba", bytes);
            if (bytes != 36 || resp[1] !== 34 || resp[2] !== 1 || resp[3] !== 3) $fatal(1, "toc lba header %0d %h %h %h", bytes, resp[1], resp[2], resp[3]);
            for (i = 0; i < 4; i++) begin
                if (resp[5 + 8 * i] !== (i == 0 ? 8'h14 : 8'h10) || resp[6 + 8 * i] !== (i == 3 ? 8'haa : i + 1) ||
                    {resp[8 + 8 * i], resp[9 + 8 * i], resp[10 + 8 * i], resp[11 + 8 * i]} !== (i == 0 ? 0 : i == 1 ? 50 : i == 2 ? 80 : 100))
                    $fatal(1, "toc lba entry %0d: %h %h %h", i, resp[5 + 8 * i], resp[6 + 8 * i], resp[11 + 8 * i]);
            end
            done_ok("toc lba done");
            // Binary MSF, from track 3: track 3 @ 00:03:05 (230), lead-out 00:03:25 (250).
            packet({8'h43, 8'h02, 32'h0, 8'd3, 16'h0100, 8'h00, 16'h0}); data_in("toc msf", bytes);
            if (bytes != 20 || resp[6] !== 3 || resp[10] !== 3 || resp[11] !== 5 || resp[14] !== 8'haa || resp[18] !== 3 || resp[19] !== 25)
                $fatal(1, "toc msf %0d: %h %h:%h / %h:%h", bytes, resp[6], resp[10], resp[11], resp[18], resp[19]);
            done_ok("toc msf done");
            packet({8'h43, 8'h02, 32'h0, 8'd4, 16'h0100, 8'h00, 16'h0}); done_err("toc track 4", 5);
            // NEC BCD mode; lead-out only.
            packet({8'h5a, 8'h00, 8'h0f, 32'h0, 16'd24, 24'h0}); data_in("mode sense", bytes); done_ok("mode done");
            packet({8'h43, 8'h02, 32'h0, 8'haa, 16'h0100, 8'h00, 16'h0}); data_in("toc aa", bytes);
            if (bytes != 12 || resp[6] !== 8'haa || resp[9] !== 0 || resp[10] !== 8'h03 || resp[11] !== 8'h25) $fatal(1, "toc aa %0d %h:%h", bytes, resp[10], resp[11]);
            done_ok("toc aa done");
            packet({8'h43, 8'h02, 32'h0, 8'd2, 16'h000c, 8'h00, 16'h0}); data_in("toc clip", bytes);
            if (bytes != 12 || resp[1] !== 26 || resp[6] !== 2 || resp[10] !== 8'h02 || resp[11] !== 8'h50) $fatal(1, "toc clip %0d %h %h:%h", bytes, resp[1], resp[10], resp[11]);
            done_ok("toc clip done");
            // Data sector from the PCD.
            packet({8'h28, 8'h00, 32'd7, 8'h00, 16'd1, 24'h0}); data_in("pcd read", bytes);
            for (i = 0; i < 2048; i++) if (resp[i] !== data_byte(7, i)) $fatal(1, "pcd sector byte %0d", i);
            done_ok("pcd read done");
            subq(a); if (a !== 8'h15) $fatal(1, "status after read %h (no audio yet: 15h)", a);
            // PLAY AUDIO MSF in BCD: 00:02:50 (lba 50) .. 00:02:53 -> 3 sectors.
            exp_lba = 50; exp_k = 0; got = 0; last_l = 0; monitor = 1;
            packet({8'h47, 8'h00, 8'h00, 8'h00, 8'h02, 8'h50, 8'h00, 8'h02, 8'h53, 24'h0}); done_ok("play msf");
            repeat (3000) @(negedge clk);
            packet({8'h42, 8'h02, 8'h40, 8'h01, 24'h0, 16'd16, 24'h0}); data_in("subq play", bytes);
            if (resp[1] !== 8'h11 || resp[5] !== 8'h10 || resp[6] !== 2 || resp[9] !== 0 || resp[10] !== 8'h02 || resp[11] !== 8'h50 ||
                resp[13] !== 0 || resp[14] !== 0 || resp[15] !== 0)
                $fatal(1, "subq while playing: %h ctl %h trk %h abs %h:%h:%h rel %h:%h:%h", resp[1], resp[5], resp[6], resp[9], resp[10], resp[11], resp[13], resp[14], resp[15]);
            done_ok("subq play done");
            wait_status(8'h13, 400);
            if (got != 3 * 588) $fatal(1, "played %0d samples, want %0d", got, 3 * 588);
            if (audio_l !== 0) $fatal(1, "output not silent after the end");
            // PLAY AUDIO(10) from track 3 (lba 80, 2 sectors) with a pause.
            exp_lba = 80; exp_k = 0; got = 0; last_l = 0;
            packet({8'h45, 8'h00, 32'd80, 8'h00, 16'd2, 24'h0}); done_ok("play10");
            repeat (8000) @(negedge clk);
            packet({8'h4b, 56'h0, 8'h00, 24'h0}); done_ok("pause");
            w = got; repeat (20000) @(negedge clk);
            if (got != w) $fatal(1, "samples advanced while paused");
            subq(a); if (a !== 8'h12) $fatal(1, "paused status %h", a);
            packet({8'h42, 8'h02, 8'h40, 8'h01, 24'h0, 16'd16, 24'h0}); data_in("subq pause", bytes);
            if (resp[6] !== 3) $fatal(1, "track while paused %h", resp[6]);
            done_ok("subq pause done");
            packet({8'h4b, 56'h0, 8'h01, 24'h0}); done_ok("resume");
            wait_status(8'h13, 400);
            if (got != 2 * 588) $fatal(1, "pause/resume played %0d samples", got);
            // STOP PLAY ends playback; a data READ does not.
            exp_lba = 55; exp_k = 0; got = 0; last_l = 0;
            packet({8'h45, 8'h00, 32'd55, 8'h00, 16'd20, 24'h0}); done_ok("play long");
            repeat (6000) @(negedge clk);
            packet({8'h4e, 88'h0}); done_ok("stop");
            subq(a); if (a !== 8'h13) $fatal(1, "stopped status %h", a);
            w = got; repeat (5000) @(negedge clk); if (got != w || audio_l !== 0) $fatal(1, "audio after stop");
            exp_lba = 60; exp_k = 0; got = 0; last_l = 0;
            packet({8'h45, 8'h00, 32'd60, 8'h00, 16'd20, 24'h0}); done_ok("play again");
            repeat (6000) @(negedge clk);
            if (got == 0) $fatal(1, "second play silent");
            monitor = 0;
            packet({8'h28, 8'h00, 32'd3, 8'h00, 16'd1, 24'h0}); data_in("read during play", bytes);
            for (i = 0; i < 2048; i++) if (resp[i] !== data_byte(3, i)) $fatal(1, "read during play byte %0d", i);
            done_ok("read during play done");
            subq(a); if (a !== 8'h11) $fatal(1, "status after a read during play %h", a);
            w = dut.rp; repeat (6000) @(negedge clk); if (dut.rp == w) $fatal(1, "audio stopped by a data read");
            packet({8'h4e, 88'h0}); done_ok("stop before resume test"); repeat (100) @(negedge clk);   // output clears at the next sample tick
            // A data read keeps the music playing; a PLAY from the reported
            // position then continues the stream (no repeat, no skip, no gap).
            monitor=1; exp_lba=70; exp_k=0; got=0; last_l=0;
            packet({8'h45, 8'h00, 32'd70, 8'h00, 16'd10, 24'h0}); done_ok("play for resume");
            repeat (20000) @(negedge clk);
            packet({8'h28, 8'h00, 32'd5, 8'h00, 16'd1, 24'h0}); data_in("read mid-play", bytes);
            done_ok("read mid-play done");
            subq(a); if (a !== 8'h11) $fatal(1, "status after mid-play read %h", a);
            w = dut.play_pos;
            if (w < 70 || w > 79) $fatal(1, "position after read %0d", w);
            packet({8'h45, 8'h00, 32'(w), 8'h00, 16'(80 - w), 24'h0}); done_ok("resume play");
            wait_status(8'h13, 400);
            if (got != 10 * 588) $fatal(1, "resumed stream played %0d samples, want %0d", got, 10 * 588);
            // End beyond the disc is clipped to the lead-out.
            monitor = 1; exp_lba = 98; exp_k = 0; got = 0; last_l = 0;
            packet({8'h45, 8'h00, 32'd98, 8'h00, 16'd50, 24'h0}); done_ok("play past end");
            wait_status(8'h13, 400);
            if (got != 2 * 588) $fatal(1, "clipped play %0d samples", got);
            $display("PASS: ATAPI PCD: capacity, multi-track TOC LBA/MSF/BCD/start/AA/clip, data read, PLAY MSF (BCD), PLAY(10), sub-channel, pause/resume, stop, play continues through data reads, PLAY at the current position continues seamlessly, lead-out clip");
        end
    endtask
    string path;
    initial begin
        if (!$value$plusargs("raw=%d", raw_mode)) raw_mode = 0;
        if (!$value$plusargs("sectors=%d", sectors)) sectors = 300;
        if (!$value$plusargs("pcd=%d", pcd_mode)) pcd_mode = 0;
        if (pcd_mode) begin raw_mode = 1; sectors = 100; end
        if (pcd_mode) build_pcd();
        else if (0) for (lba = 0; lba < sectors; lba = lba + 1)
            for (i = 0; i < 2048; i = i + 1)
                if (raw_mode) image[lba * 2352 + 16 + i] = data_byte(lba, i);
                else image[lba * 2048 + i] = data_byte(lba, i);
        if (0) for (lba = 0; lba < sectors; lba = lba + 1) begin
            for (i = 0; i < 16; i = i + 1) image[lba * 2352 + i] = (i == 0 || i == 11) ? 0 : 8'hff;
            for (i = 2064; i < 2352; i = i + 1) image[lba * 2352 + i] = 8'h5a; // EDC/ECC area
        end
        repeat (4) @(negedge clk); reset = 0;
        // Signature after power-up.
        rd(4, 0, v); if (v[7:0] !== 8'h14) $fatal(1, "signature low %h", v[7:0]);
        rd(5, 0, v); if (v[7:0] !== 8'heb) $fatal(1, "signature high %h", v[7:0]);
        // IDENTIFY DEVICE aborts with the signature; IDENTIFY PACKET returns 8580h.
        wr(6, 16'h00a0, 0); wr(7, 16'h00ec, 0); wait_irq("ec");
        rd(7, 0, st); if (st[7:0] !== 8'h41) $fatal(1, "EC status %h", st[7:0]);
        wr(7, 16'h00a1, 0); wait_irq("a1");
        rd(0, 1, v); if (v !== 16'h8580) $fatal(1, "identify word0 %h", v);
        for (i = 1; i < 256; i = i + 1) begin rd(0, 1, v); if (i == 27 && v !== "NE") $fatal(1, "model %h", v); end
        rd(7, 0, st); if (st[7:0] !== 8'h50) $fatal(1, "after identify %h", st[7:0]);
        // No disc yet: TEST UNIT READY -> not ready / 3Ah.
        packet({8'h00, 88'h0}); done_err("tur empty", 2);
        packet({8'h03, 24'h0, 8'd18, 56'h0}); data_in("sense", bytes);
        if (resp[2] !== 2 || resp[12] !== 8'h3a) $fatal(1, "sense %h/%h", resp[2], resp[12]);
        done_ok("sense done");
        // INQUIRY: NEC vendor/product, revision 1.0.
        packet({8'h12, 24'h0, 8'd36, 56'h0}); data_in("inquiry", bytes);
        if (bytes != 36 || resp[0] !== 5) $fatal(1, "inquiry len %0d type %h", bytes, resp[0]);
        for (i = 0; i < 20; i = i + 1)
            if (resp[8 + i] !== 8'(("NEC     CD-ROM DRIVE" >> (8 * (19 - i))) & 8'hff)) $fatal(1, "inquiry byte %0d", 8 + i);
        if (resp[32] !== "1") $fatal(1, "revision");
        done_ok("inquiry done");
        // Mount the image while the channel is held in reset (MGL launchers
        // mount during the boot-ROM load); the mount must not be lost.
        @(negedge clk); reset = 1;
        @(negedge clk); image_size = pcd_mode ? (sectors + 1) * 2352 : raw_mode ? sectors * 2352 : sectors * 2048; image_mounted = 1;
        @(negedge clk); image_mounted = 0; repeat (50) @(negedge clk); reset = 0;
        repeat (20000) @(negedge clk);
        packet({8'h00, 88'h0}); done_err("tur changed", 6);
        packet({8'h00, 88'h0}); done_ok("tur ready");
        if (pcd_mode) begin pcd_tests(); $finish; end
        // MODE SENSE(10) page 0Fh switches to BCD MSF.
        packet({8'h5a, 8'h00, 8'h0f, 32'h0, 16'd24, 24'h0}); data_in("mode sense", bytes);
        if (bytes != 24 || resp[8] !== 8'h0f || resp[2] !== 8'h01) $fatal(1, "mode sense %0d %h %h", bytes, resp[8], resp[2]);
        done_ok("mode done");
        // READ TOC format 0, MSF (BCD now): track 1 @ 00:02:00, lead-out.
        packet({8'h43, 8'h02, 32'h0, 8'd0, 16'h0800, 8'h00, 16'h0}); data_in("toc", bytes);
        frames = sectors + 150;
        if (bytes != 20 || resp[2] !== 1 || resp[3] !== 1 || resp[5] !== 8'h14 || resp[6] !== 1 ||
            resp[9] !== 0 || resp[10] !== 8'h02 || resp[11] !== 0 || resp[14] !== 8'haa ||
            resp[17] !== bcd(frames / 4500) || resp[18] !== bcd((frames / 75) % 60) || resp[19] !== bcd(frames % 75))
            $fatal(1, "toc %0d: %h %h %h / %h:%h:%h", bytes, resp[5], resp[6], resp[14], resp[17], resp[18], resp[19]);
        done_ok("toc done");
        // READ TOC format 1 via byte 9 = 40h (NECCDD session query).
        packet({8'h43, 8'h02, 32'h0, 8'd0, 16'h000c, 8'h40, 16'h0}); data_in("toc1", bytes);
        if (bytes != 12 || resp[1] !== 8'h0a || resp[6] !== 1) $fatal(1, "toc1 %0d", bytes);
        done_ok("toc1 done");
        // READ(10) 3 sectors from 100: one IRQ + 0800h bytes per sector, then done.
        packet({8'h28, 8'h00, 32'd100, 8'h00, 16'd3, 24'h0});
        for (lba = 100; lba < 103; lba = lba + 1) begin
            data_in("read10", bytes);
            if (bytes != 2048) $fatal(1, "sector bytes %0d", bytes);
            for (i = 0; i < 2048; i = i + 1)
                if (resp[i] !== data_byte(lba, i)) $fatal(1, "lba %0d byte %0d: %h want %h", lba, i, resp[i], data_byte(lba, i));
        end
        done_ok("read done");
        // Last sector and out of range.
        packet({8'h28, 8'h00, 32'(sectors - 1), 8'h00, 16'd1, 24'h0}); data_in("last", bytes);
        if (resp[2047] !== data_byte(sectors - 1, 2047)) $fatal(1, "last sector");
        done_ok("last done");
        packet({8'h28, 8'h00, 32'(sectors - 1), 8'h00, 16'd2, 24'h0}); done_err("range", 5);
        packet({8'h03, 24'h0, 8'd18, 56'h0}); data_in("sense2", bytes);
        if (resp[2] !== 5 || resp[12] !== 8'h21) $fatal(1, "sense2 %h/%h", resp[2], resp[12]);
        done_ok("sense2 done");
        // MODE SELECT(10) with 24 parameter bytes: data-out phase, then done.
        packet({8'h55, 8'h10, 40'h0, 16'd24, 24'h0});
        wait_irq("mode select");
        rd(2, 0, v); if (v[7:0] !== 8'h00) $fatal(1, "mode select reason %h", v[7:0]);
        for (i = 0; i < 12; i = i + 1) wr(0, 16'h0000, 1);
        done_ok("mode select done");
        // Unknown packet command -> illegal request.
        packet({8'hd4, 88'h0}); done_err("d4", 5);
        // Status read clears the IRQ; nIEN masks it.
        packet({8'h00, 88'h0}); wait_irq("tur");
        @(negedge clk); ctrl_data = 8'h02; ctrl_write = 1; @(negedge clk); ctrl_write = 0;
        if (irq) $fatal(1, "nIEN did not mask");
        rd(7, 0, st);
        @(negedge clk); ctrl_data = 8'h00; ctrl_write = 1; @(negedge clk); ctrl_write = 0;
        if (irq) $fatal(1, "status read did not clear IRQ");
        $display("PASS: ATAPI %0s, %0d sectors: signature, identify, sense, inquiry, media change, mode sense/BCD, TOC 0/1, READ(10) x3 + last + range, mode select, illegal, IRQ",
                 raw_mode ? "raw BIN" : "ISO", sectors);
        $finish;
    end
    initial begin #200000000; $fatal(1, "timeout"); end
endmodule
