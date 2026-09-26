// SPDX-License-Identifier: GPL-3.0-or-later
// Exercise the real emu wrapper and hps_io. Only the mixed-language machine
// and Intel clock primitives are replaced; HPS disk commands are not mocked.
`timescale 1ns/1ps
module mister_disk_interface_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    tri [48:0] bus;
    reg enable = 0, strobe = 0;
    reg [15:0] host_data = 0;
    assign bus[48:38] = 0;
    assign bus[35:33] = {1'b0, enable, strobe};
    assign bus[31:16] = host_data;
    emu #(.NATIVE_IMAGES(0)) dut (.CLK_50M(clk), .RESET(1'b0), .HPS_BUS(bus));
    // Disable unrelated configuration ROM/keyboard logic for Icarus, whose
    // generate scope rules differ from Quartus for this upstream PS/2 block.
    defparam dut.hps_io.CONF_STR_BRAM = 0;
    defparam dut.hps_io.PS2DIV = 0;
    defparam dut.video_out.BOOT_TEXT_FILE="rtl/assets/boot-text.mem";
    defparam dut.video_out.BOOT_FONT_FILE="rtl/assets/boot-font.mem";
    defparam dut.floppy_icon.FONT_FILE="rtl/assets/boot-font.mem";
    integer received = 0;
    integer active_slot = 0;
    reg check_receive = 0;
    reg [15:0] response;

    always @(posedge clk) begin
        if (check_receive && dut.Zet98_top.mist_buffwr) begin
            if (dut.Zet98_top.mist_buffaddr !== received[8:0])
                $fatal(1, "Receive buffer address mismatch at byte %0d", received);
            if (dut.Zet98_top.mist_buffdout !== (received[7:0] ^ active_slot[7:0]))
                $fatal(1, "Receive payload mismatch at byte %0d", received);
            received = received + 1;
        end
    end

    task word_io(input [15:0] value);
        @(negedge clk);
        enable = 1; strobe = 1; host_data = value;
        @(negedge clk);
        strobe = 0;
        repeat (4) @(negedge clk);
        response = bus[15:0];
    endtask

    task finish_command;
        @(negedge clk);
        enable = 0; strobe = 0;
        repeat (3) @(negedge clk);
        if (dut.Zet98_top.mist_ack !== 0)
            $fatal(1, "ACK was not released at end of HPS command");
    endtask

    task sector(input integer slot, input bit writing);
        active_slot = slot;
        dut.Zet98_top.mist_lba = 32'h12345678 + slot;
        dut.Zet98_top.mist_rd = writing ? 0 : 4'b1 << slot;
        dut.Zet98_top.mist_wr = writing ? 4'b1 << slot : 0;
        word_io(16'h16);
        if (response !== (16'h8080 | (slot << 2) | (writing ? 2 : 1)))
            $fatal(1, "Invalid single-block request for slot %0d: %h", slot, response);
        word_io(0);
        word_io(0);
        if (response !== 16'h5678 + slot) $fatal(1, "LBA low mismatch");
        word_io(0);
        if (response !== 16'h1234) $fatal(1, "LBA high mismatch");
        finish_command;

        word_io((slot << 8) | (writing ? 16'h18 : 16'h17));
        if (dut.Zet98_top.mist_ack !== 1)
            $fatal(1, "Missing legacy ACK for slot %0d (%s)", slot, writing ? "write" : "read");
        if (dut.sd_ack !== (4'b1 << slot)) $fatal(1, "Incorrect per-slot HPS ACK");
        // The serialized disk engine may release its request as soon as ACK
        // arrives. ACK must stay asserted until the whole sector completes.
        dut.Zet98_top.mist_rd = 0;
        dut.Zet98_top.mist_wr = 0;
        received = 0;
        check_receive = !writing;
        for (integer i = 0; i < 512; i = i + 1) begin
            word_io(i[7:0] ^ slot[7:0]);
            if (dut.Zet98_top.mist_ack !== 1) $fatal(1, "ACK ended before sector completion");
            if (writing && response[7:0] !== (i[7:0] ^ 8'ha5))
                $fatal(1, "Host write payload mismatch at byte %0d: %h", i, response);
        end
        finish_command;
        check_receive = 0;
        if (!writing && received != 512) $fatal(1, "Incomplete sector: %0d bytes", received);
    endtask

    initial begin
        force dut.hps_io.EXT_BUS[32] = 1'b0;
        repeat (5) @(negedge clk);
        for (integer slot = 0; slot < 4; slot = slot + 1) begin
            sector(slot, 0);
            sector(slot, 1);
            for (integer ro = 0; ro < 2; ro = ro + 1) begin
                word_io(16'h1c);
                word_io((1 << slot) | (ro << 7));
                if (dut.Zet98_top.mist_mounted !== (4'b1 << slot))
                    $fatal(1, "Wrong mounted image slot");
                if (dut.Zet98_top.mist_readonly !== {4{ro[0]}})
                    $fatal(1, "Read-only metadata was narrowed");
                finish_command;
            end
        end
        $display("PASS: real MiSTer wrapper/HPS disk interface, all 4 slots, 4096 transferred bytes, ACK lifetime, LBA, block count, mount metadata");
        $finish;
    end
    initial begin #1000000; $fatal(1, "Disk interface test timed out"); end
endmodule

module pll(input refclk, rst, output outclk_0, outclk_1, outclk_2, locked);
    assign {outclk_0, outclk_1, outclk_2} = {3{refclk}};
    assign locked = !rst;
endmodule

module altddio_out #(
    parameter extend_oe_disable = "", intended_device_family = "", invert_output = "",
    lpm_hint = "", lpm_type = "", oe_reg = "", power_up_high = "", width = 1
) (
    input datain_h, datain_l, outclock, aclr, aset, oe, outclocken, sclr, sset,
    output dataout
);
    assign dataout = outclock ? datain_h : datain_l;
endmodule

// Pin-compatible machine stub. The bench acts as the serialized disk engine.
module Zet98MiSTer #(parameter SYSFREQ = 20000, CPU486 = 0, EXT_RAM_MB = 0, LOWMEM_CACHE = 0, LOWMEM_CACHE_KB = 8, UPPER_RAM_ICACHE = 0, PEGC_ENABLE = 0, SND = 2, USE_JT08 = 0, USE_IDE_BOOTROM = 0) (
    input ramclk, cpuclk, vidclk, plllock,
    input [64:0] sysrtc,
    output pMemCke, pMemCs_n, pMemRas_n, pMemCas_n, pMemWe_n, pMemUdq, pMemLdq, pMemBa1, pMemBa0,
    output [12:0] pMemAdr, inout [15:0] pMemDat,
    output [28:0] pDdrAddress,
    output [63:0] pDdrWriteData,
    output [7:0] pDdrByteEnable, pDdrBurstCount,
    output pDdrRead, pDdrWrite,
    input pDdrBusy, pDdrReadValid,
    input [63:0] pDdrReadData,
    input [19:0] LDR_ADDR, input [7:0] LDR_WDAT, input LDR_OE, LDR_WR, LDR_DONE,
    output LDR_ACK,
    input pBootHold,
    output [1:0] pFloppyPresent,
    output [127:0] pCPUDebug,
    input pPs2Clkin, pPs2Datin, pPmsClkin, pPmsDatin,
    output pPs2Clkout, pPs2Datout, pPmsClkout, pPmsDatout,
    input [5:0] pJoyA, pJoyB,
    input [1:0] pFDSYNC, pFDEJECT,
    input [3:0] mist_mounted, mist_readonly,
    input [63:0] mist_imgsize,
    output reg [31:0] mist_lba = 0,
    output reg [3:0] mist_rd = 0,
    output reg [3:0] mist_wr = 0,
    input mist_ack,
    input [8:0] mist_buffaddr,
    input [7:0] mist_buffdout,
    output [7:0] mist_buffdin,
    input mist_buffwr,
    output reg [15:0] pIDEAddress, pIDEWriteData,
    output reg [1:0] pIDESelect,
    output reg pIDERead, pIDEWrite, pIDEResetn,
    input [15:0] pIDEReadData,
    input pIDEOE, pIDEIRQ,
    input [1:0] pCPUSpeed,
    input [7:0] pMPUReadData,
    input pMPUOE, pMPUIRQ,
    output pLed, output [1:0] pFloppyAccess, input [1:0] pDip1, input [7:0] pDip2,
    input pSramld, pSramst,
    output [7:0] pVideoR, pVideoG, pVideoB,
    output pVideoHS, pVideoVS, pVideoEN, pVideoClk,
    output [15:0] pSndL, pSndR,
    input pStartupBeeps, rstn
);
    initial begin
        pIDEAddress=0; pIDEWriteData=0; pIDESelect=3;
        pIDERead=0; pIDEWrite=0; pIDEResetn=0;
    end
    assign mist_buffdin = mist_buffaddr[7:0] ^ 8'ha5;
    assign LDR_ACK = 0;
    assign pFloppyAccess = 0;
    assign pFloppyPresent = 0;
    assign pCPUDebug = 0;
    assign {pVideoR, pVideoG, pVideoB, pVideoHS, pVideoVS, pVideoEN, pVideoClk} = 0;
    assign {pPs2Clkout, pPs2Datout, pPmsClkout, pPmsDatout} = 4'b1111;
endmodule
