// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// 256 independent RGB888 entries. Two synchronous RAM ports: CPU read/write,
// pixel read. Keep this in RAM (three byte-wide banks), not a 6144-bit register
// snapshot/mux. The video address and RGB result belong to video_clk only.
// Mixed-port read/write of the SAME entry has device-defined old/new data;
// software palette animation may tear at that pixel. A completed write must
// be visible on later reads. Different entries are independent.
// FPGA configuration initializes black; a guest soft reset preserves palette
// RAM, while the control block disables 256-color display.
module pc98_pegc_palette (
    input wire cpu_clk,
    input wire [7:0] cpu_index,
    input wire cpu_write,
    input wire [1:0] cpu_component, // 1=green, 2=red, 3=blue
    input wire [7:0] cpu_data,
    output reg [23:0] cpu_rgb,
    input wire video_clk,
    input wire [7:0] video_index,
    output reg [23:0] video_rgb
);
    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] red [0:255];
    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] green [0:255];
    (* ramstyle = "M10K, no_rw_check" *) reg [7:0] blue [0:255];
    integer i;
    initial begin
        for (i=0;i<256;i=i+1) begin
            red[i]=0; green[i]=0; blue[i]=0;
        end
    end
    always @(posedge cpu_clk) begin
        if (cpu_write) begin
            case (cpu_component)
                1: green[cpu_index] <= cpu_data;
                2: red[cpu_index] <= cpu_data;
                3: blue[cpu_index] <= cpu_data;
                default: ;
            endcase
        end
        cpu_rgb <= {red[cpu_index],green[cpu_index],blue[cpu_index]};
    end
    always @(posedge video_clk)
        video_rgb <= {red[video_index],green[video_index],blue[video_index]};
endmodule
