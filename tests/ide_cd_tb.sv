`timescale 1ns/1ps
// pc98_ide with the ATAPI CD on bank 1: port-level CPU accesses (0432h bank,
// 0640h-064Eh task file, 074Ch control) reach the right device; a CD sector
// read works through the controller while the hard disk stays on bank 0.
module ide_cd_tb;
    reg clk = 0; always #5 clk = ~clk;
    reg reset = 1;
    reg [15:0] io_address = 0, io_writedata = 0;
    reg [1:0] io_select = 0;
    reg io_read = 0, io_write = 0;
    wire [15:0] io_readdata;
    wire io_oe, irq;
    reg image_mounted = 0, image_readonly = 0;
    reg [63:0] image_size = 0;
    wire [31:0] sd_lba, cd_lba;
    wire sd_rd, sd_wr, cd_rd;
    reg sd_ack = 0, sd_buff_wr = 0, cd_ack = 0, cd_buff_wr = 0;
    reg [8:0] sd_buff_addr = 0, cd_buff_addr = 0;
    reg [7:0] sd_buff_dout = 0, cd_buff_dout = 0;
    wire [7:0] sd_buff_din;
    reg cd_mounted = 0;
    reg [63:0] cd_size = 0;
    wire signed [15:0] cd_audio_l, cd_audio_r;
    wire [5:0] cd_blk_cnt;
    wire [1:0] cd_activity;
    wire [91:0] cd_trace;
    pc98_ide dut(.*);

    // CD host: sector n byte i = n ^ i (ISO layout).
    always @(posedge clk) if (cd_rd && !cd_ack) begin
        repeat (2) @(posedge clk); cd_ack <= 1;
        for (integer i = 0; i < 512 * (cd_blk_cnt + 1); i = i + 1) begin
            @(posedge clk); cd_buff_addr <= i; cd_buff_dout <= ((cd_lba * 512 + i) / 2048) ^ i[7:0]; cd_buff_wr <= 1;
        end
        @(posedge clk); cd_buff_wr <= 0; @(posedge clk); cd_ack <= 0;
    end
    // HDD host (unused data): just complete requests.
    always @(posedge clk) if ((sd_rd || sd_wr) && !sd_ack) begin
        repeat (2) @(posedge clk); sd_ack <= 1; repeat (520) @(posedge clk); sd_ack <= 0;
    end

    task out(input [15:0] a, input [15:0] d, input [1:0] sel);
        begin
            @(negedge clk); io_address = a; io_writedata = d; io_select = sel; io_write = 1;
            @(negedge clk); io_write = 0; @(negedge clk);
        end
    endtask
    task in(input [15:0] a, input [1:0] sel, output [15:0] d);
        begin
            @(negedge clk); io_address = a; io_select = sel; io_read = 1;
            @(negedge clk); #1 d = io_readdata; if (!io_oe) $fatal(1, "no OE at %h", a);
            io_read = 0; @(negedge clk);
        end
    endtask
    task wait_irq;
        integer t;
        begin t = 0; while (!irq) begin @(posedge clk); t = t + 1; if (t > 100000) $fatal(1, "no IRQ"); end end
    endtask
    reg [15:0] v;
    integer i, bytes;
    initial begin
        repeat (4) @(negedge clk); reset = 0;
        @(negedge clk); image_size = 64'd1048576; image_mounted = 1; @(negedge clk); image_mounted = 0;
        @(negedge clk); cd_size = 64'd2048 * 50; cd_mounted = 1; @(negedge clk); cd_mounted = 0;
        repeat (5000) @(negedge clk);   // probe: 4 blocks + lead-out
        // Bank 0: hard disk answers IDENTIFY DEVICE with a fixed-disk word 0.
        out(16'h0432, 16'h0000, 2'b01);
        out(16'h064c, 16'h00a0, 2'b01); out(16'h064e, 16'h00ec, 2'b01);
        wait_irq; in(16'h064e, 2'b01, v);
        in(16'h0640, 2'b11, v); if (v !== 16'h0040) $fatal(1, "HDD identify word0 %h", v);
        for (i = 1; i < 256; i = i + 1) in(16'h0640, 2'b11, v);
        // Bank 1: CD signature and INQUIRY.
        out(16'h0432, 16'h0001, 2'b01);
        out(16'h064c, 16'h00a0, 2'b01);
        in(16'h0648, 2'b01, v); if (v[7:0] !== 8'h14) $fatal(1, "CD signature %h", v[7:0]);
        in(16'h064a, 2'b01, v); if (v[7:0] !== 8'heb) $fatal(1, "CD signature hi %h", v[7:0]);
        // Clear the media-change unit attention first.
        out(16'h064e, 16'h00a0, 2'b01);
        for (i = 0; i < 6; i = i + 1) out(16'h0640, 16'h0000, 2'b11);
        wait_irq; in(16'h064e, 2'b01, v);
        // READ(10) LBA 7, 1 sector.
        out(16'h064e, 16'h00a0, 2'b01);
        out(16'h0640, 16'h0028, 2'b11); out(16'h0640, 16'h0000, 2'b11); out(16'h0640, 16'h0700, 2'b11);
        out(16'h0640, 16'h0000, 2'b11); out(16'h0640, 16'h0001, 2'b11); out(16'h0640, 16'h0000, 2'b11);
        wait_irq;
        in(16'h0644, 2'b01, v); if (v[7:0] !== 8'h02) $fatal(1, "reason %h", v[7:0]);
        in(16'h064e, 2'b01, v); if (v[7:0] !== 8'h58) $fatal(1, "status %h", v[7:0]);
        for (i = 0; i < 1024; i = i + 1) begin
            in(16'h0640, 2'b11, v);
            if (v !== {8'(7 ^ ((2*i+1) & 255)), 8'(7 ^ ((2*i) & 255))}) $fatal(1, "CD word %0d = %h", i, v);
        end
        wait_irq; in(16'h064e, 2'b01, v); if (v[7:0] !== 8'h50) $fatal(1, "CD done %h", v[7:0]);
        // Back to bank 0: HDD registers untouched by the CD traffic.
        out(16'h0432, 16'h0000, 2'b01);
        in(16'h064e, 2'b01, v); if (v[7:0] !== 8'h50) $fatal(1, "HDD status after CD %h", v[7:0]);
        in(16'h0648, 2'b01, v); if (v[7:0] === 8'h14) $fatal(1, "HDD shows CD registers");
        $display("PASS: IDE bank routing: HDD on bank 0, ATAPI CD on bank 1 (signature, READ(10) through ports), shared IRQ");
        $finish;
    end
    initial begin #100000000; $fatal(1, "timeout"); end
endmodule
