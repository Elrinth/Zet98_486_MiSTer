`timescale 1ns/1ps
module boot_media_control_tb;
    reg clk=0, reset=1, restart=0, rom_ready=0, start_without_disk=0;
    reg [1:0] floppy_ready=0;
    reg [3:0] image_mounted=0;
    reg [63:0] image_size=0;
    wire hold_boot;
    wire [2:0] prompt;
    always #5 clk=!clk;
    boot_media_control #(.RAW_IDE(1)) dut(.*);
    task tick;
        begin @(posedge clk); #1; end
    endtask
    task check(input bit hold_expected,input [2:0] message_expected);
        begin
            tick;
            if(hold_boot!==hold_expected || prompt!==message_expected)
                $fatal(1,"Boot state hold=%b prompt=%0d, expected %b/%0d",
                       hold_boot,prompt,hold_expected,message_expected);
        end
    endtask
    initial begin
        check(1,1); reset=0;
        rom_ready=1; check(1,2);
        // A valid VHD starts the native option ROM; partial sectors aren't media.
        image_mounted=4; image_size=513; check(1,2);
        image_size=1048576; check(1,3);
        image_mounted=0;
        check(0,0);
        image_mounted=4; image_size=0; check(0,0);
        image_mounted=0; restart=1; check(1,2); restart=0;
        // Mount notification is not enough: wait for the complete D88 load.
        image_mounted=1; image_size=1281968; check(1,4);
        image_mounted=0; repeat(8) check(1,4);
        floppy_ready=1; check(0,0);
        // Guest remains running through ejection, VHD removal and disk swaps.
        floppy_ready=0; image_mounted=5; image_size=0; check(0,0);
        image_mounted=0; check(0,0);
        restart=1; check(1,2); restart=0; check(1,2);
        // Either floppy can boot; reset with an existing disk needs no remount.
        floppy_ready=2; check(0,0);
        restart=1; check(1,2); restart=0; check(0,0);
        // Explicit BIOS/BASIC mode is an escape hatch, not the default.
        floppy_ready=0; restart=1; check(1,2); restart=0;
        start_without_disk=1; check(0,0);
        start_without_disk=0; check(0,0);
        rom_ready=0; check(1,1);
        $display("PASS: missing ROM, empty boot, native VHD boot, completed floppy load, eject/swap, reset and BIOS bypass");
        $finish;
    end
endmodule
