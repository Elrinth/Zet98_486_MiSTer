// SPDX-License-Identifier: GPL-3.0-or-later
// Floppy image admission for both slots: D88 only. A mount reads the image's
// first sector, checks the D88 header (disk size field equals the image size,
// media type <= 20h) and then passes every transfer through unchanged. Other
// formats (HDM, FDI, NFD, ...) reject the mount; convert raw HDM images with
// scripts/pc98_hdm_to_d88.py. The HDM/FDI-to-virtual-D88 converter was
// removed to free FPGA area (B251).
module pc98_floppy_images (
    input wire clk,
    input wire [1:0] mounted,
    input wire readonly,
    input wire [63:0] image_size,
    output reg [1:0] media_mounted = 0,
    output reg [1:0] media_readonly = 2'b11,
    output wire [63:0] media_size[2],
    input wire [31:0] disk_lba[2],
    input wire [1:0] disk_rd, disk_wr,
    input wire [7:0] disk_buff_din[2],
    output wire [1:0] disk_ack,
    output wire [1:0] disk_buff_wr,
    output wire [8:0] disk_buff_addr[2],
    output wire [7:0] disk_buff_dout[2],
    output wire [31:0] host_lba[2],
    output wire [1:0] host_rd, host_wr,
    output wire [7:0] host_buff_din[2],
    input wire [1:0] host_ack,
    input wire host_buff_wr,
    input wire [8:0] host_buff_addr,
    input wire [7:0] host_buff_dout,
    output reg [1:0] invalid = 0
);
    localparam IDLE=0, FETCH=1, FETCH_ACK=2, CHECK=3;
    reg [1:0] state = IDLE;
    reg owner = 0;
    reg [1:0] pending = 0, ready = 0, slot_ro = 2'b11, slot_big = 0;
    reg [31:0] slot_size[2], slot_media_size[2];
    initial begin
        slot_media_size[0]=0; slot_media_size[1]=0;
    end
    assign media_size[0] = {32'b0, slot_media_size[0]};
    assign media_size[1] = {32'b0, slot_media_size[1]};

    reg [7:0] media_type;                // D88 offset 1Bh
    reg [31:0] disk_size;                // D88 offset 1Ch-1Fh
    wire [1:0] passthrough = ready & ~mounted;
    wire checking = state != IDLE;
    genvar i;
    generate for (i = 0; i < 2; i = i + 1) begin: port
        wire own = checking && owner == i;
        assign host_lba[i] = passthrough[i] ? disk_lba[i] : 32'd0;
        assign host_rd[i] = !mounted[i] && (passthrough[i] ? disk_rd[i] : own && state == FETCH);
        assign host_wr[i] = passthrough[i] && disk_wr[i];
        assign host_buff_din[i] = disk_buff_din[i];
        assign disk_ack[i] = passthrough[i] && host_ack[i];
        assign disk_buff_wr[i] = passthrough[i] && host_buff_wr && host_ack[i];
        assign disk_buff_addr[i] = host_buff_addr;
        assign disk_buff_dout[i] = host_buff_dout;
    end endgenerate

    wire owner_ack = host_ack[owner];
    // A drive may start its header check once its host and disk sides are quiet.
    wire [1:0] quiet = ~host_ack & ~disk_rd & ~disk_wr & ~mounted;
    wire [31:0] size = slot_size[owner];
    always @(posedge clk) begin
        if (state != IDLE && owner_ack && host_buff_wr) begin
            if (host_buff_addr == 9'h1b) media_type <= host_buff_dout;
            if (host_buff_addr[8:2] == 7'h07) disk_size[host_buff_addr[1:0]*8 +: 8] <= host_buff_dout;
        end
        media_mounted <= 0;
        case(state)
            IDLE: if (pending[0] && quiet[0] || pending[1] && quiet[1]) begin
                owner <= !(pending[0] && quiet[0]);
                pending[!(pending[0] && quiet[0])] <= 0;
                state <= FETCH;
            end
            FETCH: if (owner_ack) state <= FETCH_ACK;
            FETCH_ACK: if (!owner_ack) state <= CHECK;
            CHECK: begin
                if (!slot_big[owner] && size >= 688 && disk_size == size && media_type <= 8'h20) begin
                    slot_media_size[owner] <= size; media_readonly[owner] <= slot_ro[owner];
                    ready[owner] <= 1;
                end else begin
                    invalid[owner] <= 1; slot_media_size[owner] <= 0;
                end
                media_mounted[owner] <= 1;
                state <= IDLE;
            end
            default: state <= IDLE;
        endcase
        // A new mount (or eject) of a drive discards its state and aborts
        // that drive's own check; it wins over the state machine above.
        for (integer s = 0; s < 2; s = s + 1) if (mounted[s]) begin
            slot_size[s] <= image_size[31:0]; slot_big[s] <= image_size[63:32] != 0;
            slot_ro[s] <= readonly; pending[s] <= image_size != 0;
            ready[s] <= 0; invalid[s] <= 0;
            slot_media_size[s] <= 0; media_readonly[s] <= 1; media_mounted[s] <= 1;
            if (checking && owner == s) state <= IDLE;
        end
    end
endmodule
