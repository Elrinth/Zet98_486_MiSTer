// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Real wrapper, ATA controller and HPS command parser; only the VHDL machine
// and clock primitives use the shared stubs from mister_disk_interface_tb.
module mister_ide_interface_tb;
    parameter NATIVE=0;
    reg clk=0; always #5 clk=!clk;
    tri [48:0] bus;
    reg enable=0,strobe=0;
    reg [15:0] host_data=0,response;
    assign bus[48:38]=0;
    assign bus[35:33]={1'b0,enable,strobe};
    assign bus[31:16]=host_data;
    emu #(.NATIVE_IMAGES(NATIVE)) dut(.CLK_50M(clk),.RESET(1'b0),.HPS_BUS(bus));
    defparam dut.hps_io.CONF_STR_BRAM=0;
    defparam dut.hps_io.PS2DIV=0;
    defparam dut.video_out.BOOT_TEXT_FILE="rtl/assets/boot-text.mem";
    defparam dut.video_out.BOOT_FONT_FILE="rtl/assets/boot-font.mem";
    defparam dut.floppy_icon.TILE_MAP_FILE="rtl/assets/floppy-tile-map.mem";
    defparam dut.floppy_icon.TILE_PIXELS_FILE="rtl/assets/floppy-tile-pixels.mem";
    defparam dut.floppy_icon.FONT_FILE="rtl/assets/boot-font.mem";
    integer floppy_bytes=0;
    always @(posedge clk) begin
        if(dut.sd_ack[2] && (dut.Zet98_top.mist_ack || dut.Zet98_top.mist_buffwr))
            $fatal(1,"IDE transfer leaked into diskemu");
        if(dut.Zet98_top.mist_mounted[2]) $fatal(1,"IDE mount leaked into diskemu");
        if(dut.Zet98_top.mist_buffwr) floppy_bytes=floppy_bytes+1;
    end
    task word_io(input [15:0] value);
        @(negedge clk); enable=1;strobe=1;host_data=value;
        @(negedge clk);strobe=0;
        repeat(4) @(negedge clk); response=bus[15:0];
    endtask
    task finish_command;
        @(negedge clk);enable=0;strobe=0;
        repeat(4) @(negedge clk);
    endtask
    task outw(input [15:0] port,input [15:0] value);
        @(negedge clk);
        dut.Zet98_top.pIDEAddress=port; dut.Zet98_top.pIDEWriteData=value;
        dut.Zet98_top.pIDEWrite=1;
        repeat(4) @(negedge clk); dut.Zet98_top.pIDEWrite=0;
        repeat(3) @(negedge clk);
    endtask
    task inw(input [15:0] port,output [15:0] value);
        @(negedge clk);dut.Zet98_top.pIDEAddress=port; dut.Zet98_top.pIDERead=1;
        repeat(4) @(negedge clk); value=dut.Zet98_top.pIDEReadData;
        dut.Zet98_top.pIDERead=0;
        repeat(3) @(negedge clk);
    endtask
    task set_taskfile(input [7:0] sector);
        outw('h644,1);outw('h646,sector);outw('h648,0);outw('h64a,0);outw('h64c,'he0);
    endtask
    task check_request(input integer slot,input bit writing,input [31:0] lba);
        word_io('h16);
        // Header probes advance Main's round-robin pointer. Poll once more
        // if the other pending slot is offered first; do not assume priority.
        if(NATIVE && response!==(16'h8080|(slot<<2)|(writing?2:1))) begin
            word_io(0);word_io(0);word_io(0);finish_command;word_io('h16);
        end
        if(response!==(16'h8080|(slot<<2)|(writing?2:1))) $fatal(1,"wrong HPS slot/type %h",response);
        word_io(0);word_io(0);
        if(response!==lba[15:0]) $fatal(1,"slot LBA low");
        word_io(0);if(response!==lba[31:16]) $fatal(1,"slot LBA high");
        finish_command;
    endtask
    reg [15:0] value;
    integer i;
    initial begin
        force dut.hps_io.EXT_BUS[32]=1'b0;
        repeat(5) @(negedge clk);dut.Zet98_top.pIDEResetn=1;
        // Main sends image size before its mount notification.
        word_io('h1d);word_io(NATIVE ? 'h1000 : 0);word_io(8);word_io(0);word_io(0);finish_command;
        word_io('h1c);word_io(4);finish_command;
        if(NATIVE) begin
            repeat(10) @(negedge clk); check_request(2,0,0);
            word_io('h217);
            for(i=0;i<512;i=i+1) begin
                case(i/4)
                    1: value=5>>(8*(i%4));
                    2: value=4096>>(8*(i%4));
                    3: value=524288>>(8*(i%4));
                    4: value=512>>(8*(i%4));
                    5: value=32>>(8*(i%4));
                    6: value=16>>(8*(i%4));
                    7: value=2>>(8*(i%4));
                    default: value=0;
                endcase
                word_io(value & 255);
            end
            finish_command; repeat(15) @(negedge clk);
            // Mount a small synthetic D88 so slot 1 follows its unchanged path.
            word_io('h1d);word_io(1024);word_io(0);word_io(0);word_io(0);finish_command;
            word_io('h1c);word_io(2);finish_command;repeat(10) @(negedge clk);
            check_request(1,0,0);word_io('h117);
            for(i=0;i<512;i=i+1) word_io(i==29 ? 4 : 0);
            finish_command;repeat(15) @(negedge clk);
            if(floppy_bytes) $fatal(1,"probe leaked into legacy disk buffer");
        end
        inw('h430,value);if(value!=16'hff01) $fatal(1,"IDE image missing");
        set_taskfile('h12);
        if(!NATIVE) outw('h64e,'h20);
        // A separate floppy request is serviced while IDE waits. Slot-specific
        // LBAs, buffers, mounts and ACKs must remain isolated in both directions.
        dut.Zet98_top.mist_lba='hdeadbeef;dut.Zet98_top.mist_rd=2;
        if(NATIVE) begin repeat(10) @(negedge clk);outw('h64e,'h20);end
        check_request(1,0,'hdeadbeef);
        word_io('h117);dut.Zet98_top.mist_rd=0;
        for(i=0;i<512;i=i+1) word_io(i^'h55);
        finish_command;
        if(floppy_bytes!=512) $fatal(1,"floppy data lost");
        check_request(2,0,'h12+(NATIVE ? 8 : 0));
        word_io('h217);
        for(i=0;i<512;i=i+1) word_io(i^'ha3);
        finish_command;
        repeat(8) @(negedge clk);
        inw('h64e,value);if(value!=16'hff58) $fatal(1,"IDE read not ready %h",value);
        for(i=0;i<256;i=i+1) begin
            inw('h640,value);
            if(value!=={8'((i*2+1)^'ha3),8'((i*2)^'ha3)}) $fatal(1,"HPS to CPU data %0d %h",i,value);
        end
        set_taskfile('h21);outw('h64e,'h30);
        for(i=0;i<256;i=i+1) outw('h640,'hc35a^i);
        check_request(2,1,'h21+(NATIVE ? 8 : 0));
        word_io('h218);
        for(i=0;i<512;i=i+1) begin
            word_io(0);
            if(response[7:0] !== (i[0] ? 8'hc3 : (8'h5a ^ (i>>1))))
                $fatal(1,"CPU to HPS data %0d %h",i,response);
        end
        finish_command;
        repeat(8) @(negedge clk);
        inw('h64e,value);if(value!=16'hff50) $fatal(1,"IDE write not complete");
        if(floppy_bytes!=512) $fatal(1,"IDE contaminated floppy buffer");
        $display("PASS real HPS/raw IDE wrapper: concurrent floppy request, 512-byte read/write, independent LBA/ACK/buffers/mount");
        $finish;
    end
    initial begin #2000000; $fatal(1,"HPS IDE watchdog");end
endmodule
