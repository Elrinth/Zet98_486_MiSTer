// SPDX-License-Identifier: GPL-3.0-or-later
// Per-slot image translation and serialization of mount metadata for the
// legacy disk engine's shared size/read-only bus.
module pc98_image_bridge #(parameter ENABLE=1, RAW_IDE=1) (
    input wire clk,
    input wire [3:0] image_mounted,
    input wire image_readonly,
    input wire [63:0] image_size,
    output wire [3:0] core_mounted,
    output wire core_readonly,
    output wire [63:0] core_size,
    input wire [31:0] disk_lba[4],
    input wire [3:0] disk_rd,disk_wr,
    input wire [7:0] disk_buff_din[4],
    output wire [3:0] disk_ack,disk_buff_wr,
    output wire [8:0] disk_buff_addr[4],
    output wire [7:0] disk_buff_dout[4],
    output wire [31:0] host_lba[4],
    output wire [3:0] host_rd,host_wr,
    output wire [7:0] host_buff_din[4],
    input wire [3:0] host_ack,
    input wire host_buff_wr,
    input wire [8:0] host_buff_addr,
    input wire [7:0] host_buff_dout,
    output wire [2:0] invalid
);
    wire [3:0] mounted,readonly;
    wire [63:0] size[4];
    genvar i;
    generate for(i=0;i<4;i=i+1) begin: slots
        if(ENABLE && i<2) begin: floppy
            pc98_floppy_image image (
                .clk(clk),.mounted(image_mounted[i]),.readonly(image_readonly),.image_size(image_size),
                .media_mounted(mounted[i]),.media_readonly(readonly[i]),.media_size(size[i]),
                .disk_lba(disk_lba[i]),.disk_rd(disk_rd[i]),.disk_wr(disk_wr[i]),
                .disk_buff_din(disk_buff_din[i]),.disk_ack(disk_ack[i]),.disk_buff_wr(disk_buff_wr[i]),
                .disk_buff_addr(disk_buff_addr[i]),.disk_buff_dout(disk_buff_dout[i]),
                .host_lba(host_lba[i]),.host_rd(host_rd[i]),.host_wr(host_wr[i]),
                .host_buff_din(host_buff_din[i]),.host_ack(host_ack[i]),
                .host_buff_wr(host_buff_wr),.host_buff_addr(host_buff_addr),.host_buff_dout(host_buff_dout),
                .invalid(invalid[i])
            );
        end else if(ENABLE && RAW_IDE && i==2) begin: hdi
            pc98_hdi_image image (
                .clk(clk),.mounted(image_mounted[i]),.readonly(image_readonly),.image_size(image_size),
                .media_mounted(mounted[i]),.media_readonly(readonly[i]),.media_size(size[i]),
                .disk_lba(disk_lba[i]),.disk_rd(disk_rd[i]),.disk_wr(disk_wr[i]),
                .disk_ack(disk_ack[i]),.disk_buff_wr(disk_buff_wr[i]),
                .host_lba(host_lba[i]),.host_rd(host_rd[i]),.host_wr(host_wr[i]),
                .host_ack(host_ack[i]),.host_buff_wr(host_buff_wr),
                .host_buff_addr(host_buff_addr),.host_buff_dout(host_buff_dout),.invalid(invalid[i])
            );
            assign host_buff_din[i]=disk_buff_din[i];
            assign disk_buff_addr[i]=host_buff_addr;
            assign disk_buff_dout[i]=host_buff_dout;
        end else begin: direct
            assign mounted[i]=image_mounted[i];
            assign readonly[i]=image_readonly;
            assign size[i]=image_size;
            assign host_lba[i]=disk_lba[i];
            assign host_rd[i]=disk_rd[i];
            assign host_wr[i]=disk_wr[i];
            assign host_buff_din[i]=disk_buff_din[i];
            assign disk_ack[i]=host_ack[i];
            assign disk_buff_wr[i]=host_buff_wr && host_ack[i];
            assign disk_buff_addr[i]=host_buff_addr;
            assign disk_buff_dout[i]=host_buff_dout;
            if(i<3) assign invalid[i]=0;
        end
    end
    endgenerate
    generate if(ENABLE) begin: events
        reg [3:0] pending=0, pulse=0;
        reg [63:0] saved_size[4];
        reg [3:0] saved_ro;
        reg ro=1;
        reg [63:0] bytes=0;
        assign core_mounted=pulse;
        assign core_readonly=ro;
        assign core_size=bytes;
        integer selected, j;
        always @(posedge clk) begin
            pulse<=0;
            selected=-1;
            for(j=3;j>=0;j=j-1) if(pending[j]) selected=j;
            if(selected>=0) begin
                pending[selected]<=0; pulse[selected]<=1;
                bytes<=saved_size[selected];ro<=saved_ro[selected];
            end
            for(j=0;j<4;j=j+1) if(mounted[j]) begin
                pending[j]<=1;saved_size[j]<=size[j];saved_ro[j]<=readonly[j];
            end
        end
    end else begin
        assign core_mounted=image_mounted;
        assign core_readonly=image_readonly;
        assign core_size=image_size;
    end endgenerate
endmodule
