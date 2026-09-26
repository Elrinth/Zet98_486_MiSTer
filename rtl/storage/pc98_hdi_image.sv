// SPDX-License-Identifier: GPL-3.0-or-later
// Mount-time HDI header validation and sector-offset translation. Raw images
// pass through. Mount/eject first withdraws the old media; an accepted host
// transfer is drained before probing the replacement. No image bytes are changed.
module pc98_hdi_image (
    input wire clk,
    input wire mounted, readonly,
    input wire [63:0] image_size,
    output reg media_mounted = 0,
    output reg media_readonly = 1,
    output reg [63:0] media_size = 0,
    input wire [31:0] disk_lba,
    input wire disk_rd, disk_wr,
    output wire disk_ack,
    output wire disk_buff_wr,
    output wire [31:0] host_lba,
    output wire host_rd, host_wr,
    input wire host_ack, host_buff_wr,
    input wire [8:0] host_buff_addr,
    input wire [7:0] host_buff_dout,
    output reg invalid = 0
);
    localparam DRAIN=0, PROBE=1, ACK=2, CHECK=3, GEOMETRY=4, READY=5;
    reg [2:0] state = DRAIN;
    reg pending = 0;
    reg [63:0] size = 0;
    reg ro = 1;
    reg [31:0] header[0:7];
    reg [31:0] base = 0;
    reg [31:0] geometry;
    wire passthrough = state == READY && !mounted;
    assign host_lba = passthrough ? disk_lba + base : 0;
    assign host_rd = passthrough ? disk_rd : state == PROBE && !mounted;
    assign host_wr = passthrough && disk_wr;
    assign disk_ack = passthrough && host_ack;
    assign disk_buff_wr = passthrough && host_buff_wr && host_ack;
    always @(posedge clk) begin
        media_mounted <= 0;
        if (mounted) begin
            size <= image_size; ro <= readonly; pending <= image_size != 0;
            state <= DRAIN; base <= 0; invalid <= 0;
            media_size <= 0; media_readonly <= 1; media_mounted <= 1;
        end else case(state)
            DRAIN: if (!host_ack && !disk_rd && !disk_wr && pending) begin
                pending <= 0; state <= PROBE;
            end
            PROBE: if (host_ack) state <= ACK;
            ACK: if (!host_ack) state <= CHECK;
            CHECK: begin
                // HDI has no magic. A zero reserved word and plausible header
                // length/sector width identify the container; then validate all
                // fields, including overflow and exact file length, before use.
                geometry <= 32'(header[5][7:0]) * header[6][7:0] * header[7][15:0];
                state <= GEOMETRY;
            end
            GEOMETRY: begin
                state <= READY; media_mounted <= 1; media_readonly <= ro;
                if (header[0] == 0 && (header[2] != 0 || header[4] != 0)) begin
                    if (header[2] >= 32 && header[2][8:0] == 0 &&
                        header[4] == 512 && header[5] >= 1 && header[5] <= 255 &&
                        header[6] >= 1 && header[6] <= 255 &&
                        header[7] >= 1 && header[7] <= 65535 &&
                        {geometry,9'b0} == {9'b0,header[3]} &&
                        {32'b0,header[2]} + {32'b0,header[3]} == size) begin
                        base <= header[2] >> 9;
                        media_size <= {32'b0,header[3]};
                    end else begin
                        invalid <= 1; media_size <= 0;
                    end
                end else begin
                    media_size <= size;
                end
            end
            default: ;
        endcase
        if ((state == PROBE || state == ACK) && host_ack && host_buff_wr && host_buff_addr < 32)
            header[host_buff_addr[4:2]][host_buff_addr[1:0]*8 +: 8] <= host_buff_dout;
    end
endmodule
