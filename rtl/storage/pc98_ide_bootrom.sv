// SPDX-License-Identifier: GPL-3.0-or-later
// Bus completion still uses the existing SDRAM arbitration/acknowledgement;
// its address is held long enough for this synchronous 8 KB option-ROM read.
module pc98_ide_bootrom #(
    parameter FILE="../../rtl/storage/pc98_ide_bootrom.mem"
) (
    input wire clk,
    input wire [11:0] address,
    input wire [1:0] ram_size,          // OSD RAM size: 0 32 MB, 1 64 MB, 2 16 MB
    output reg [15:0] q
);
    (* ramstyle="M10K" *) reg [15:0] rom[0:4095];
    initial $readmemh(FILE,rom);
    // The last ROM word (byte 1FFEh) reports the OSD RAM size to the ROM's
    // memory initializer, which publishes no more than that to the BIOS.
    reg [1:0] ram_size_r;
    reg last_word;
    reg [15:0] rom_q;
    always @(posedge clk) begin
        rom_q <= rom[address];
        last_word <= &address;
        ram_size_r <= ram_size;
    end
    always @* q = last_word ? {14'b0, ram_size_r} : rom_q;
endmodule
