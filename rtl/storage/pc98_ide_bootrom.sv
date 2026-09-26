// SPDX-License-Identifier: GPL-3.0-or-later
// Bus completion still uses the existing SDRAM arbitration/acknowledgement;
// its address is held long enough for this synchronous 8 KB option-ROM read.
module pc98_ide_bootrom #(
    parameter FILE="../../rtl/storage/pc98_ide_bootrom.mem"
) (
    input wire clk,
    input wire [11:0] address,
    output reg [15:0] q
);
    (* ramstyle="M10K" *) reg [15:0] rom[0:4095];
    initial $readmemh(FILE,rom);
    always @(posedge clk) q <= rom[address];
endmodule
