// SPDX-License-Identifier: GPL-3.0-or-later
// Start the BIOS after a floppy finishes loading or a raw ATA image mounts.
// Once started, ejecting/changing media must never reset a running guest.
module boot_media_control #(
    parameter RAW_IDE = 0
) (
    input wire clk, reset, restart, rom_ready, start_without_disk,
    input wire [1:0] floppy_ready,
    input wire [3:0] image_mounted,
    input wire [63:0] image_size,
    output wire hold_boot,
    output reg [2:0] prompt
);
    reg started = 0;
    reg hard_disk = 0;
    reg [1:0] loading = 0;
    always @(posedge clk) begin
        if (reset) begin
            started <= 0;
            hard_disk <= 0;
            loading <= 0;
        end else begin
            // A partial last sector (raw dumps with trailing filler) is ignored,
            // matching pc98_ide; images below one sector are not a disk.
            if (image_mounted[2])
                hard_disk <= image_size >= 512;
            for (integer drive=0; drive<2; drive=drive+1) begin
                if (image_mounted[drive]) loading[drive] <= image_size != 0;
                else if (floppy_ready[drive]) loading[drive] <= 0;
            end
            if (restart || !rom_ready) started <= 0;
            else if (start_without_disk || |floppy_ready || (RAW_IDE && hard_disk)) started <= 1;
        end
    end
    assign hold_boot = !started;
    always_comb begin
        if (!rom_ready) prompt = 1;
        else if (started) prompt = 0;
        else if (|loading) prompt = 4;
        else if (RAW_IDE && hard_disk) prompt = 3;
        else prompt = 2;
    end
endmodule
