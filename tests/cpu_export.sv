// SPDX-License-Identifier: GPL-3.0-or-later
// Optional simulation-only observer expected by upstream pipeline.v.
// It has no outputs and cannot change CPU behavior.
module cpu_export (
    input wire clk, rst_n, new_export,
    input wire [31:0] eax, ebx, ecx, edx, esp, ebp, esi, edi, eip
);
    always @(posedge clk)
        if (rst_n && new_export && $test$plusargs("trace"))
            $display("EXEC eip=%h eax=%h ebx=%h ecx=%h edx=%h esp=%h", eip, eax, ebx, ecx, edx, esp);
endmodule
