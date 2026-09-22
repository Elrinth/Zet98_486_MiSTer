// SPDX-License-Identifier: GPL-3.0-or-later
// Coherent snapshots of slow host configuration, not a stream/FIFO. Updates
// while busy coalesce to the latest source value after the acknowledgement.
// Both domains start at FPGA configuration; stopping either clock is safe.
module video_config_snapshot #(parameter WIDTH=1) (
    input wire source_clk, video_clk,
    input wire [WIDTH-1:0] source_data,
    (* preserve *) output reg [WIDTH-1:0] video_data = 0
);
    (* preserve *) reg [WIDTH-1:0] held_data = 0;
    reg request = 0, acknowledge = 0;
    (* preserve, altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] request_sync = 0, acknowledge_sync = 0;
    wire [WIDTH-1:0] transfer_data;
    assign transfer_data = held_data;

    always @(posedge source_clk) begin
        acknowledge_sync <= {acknowledge_sync[0], acknowledge};
        if (acknowledge_sync[1] == request && source_data != held_data) begin
            held_data <= source_data;
            request <= !request;
        end
    end

    always @(posedge video_clk) begin
        request_sync <= {request_sync[0], request};
        if (request_sync[1] != acknowledge) begin
            video_data <= transfer_data;
            acknowledge <= request_sync[1];
        end
    end
endmodule
