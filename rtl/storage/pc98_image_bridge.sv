// SPDX-License-Identifier: GPL-3.0-or-later
// Per-slot image translation (one shared floppy converter) and serialization of mount metadata for the
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
    wire [63:0] floppy_size[2];
    wire [31:0] floppy_host_lba[2];
    wire [8:0] floppy_buff_addr[2];
    wire [7:0] floppy_buff_dout[2], floppy_host_din[2];
    wire [31:0] floppy_lba[2];
    wire [7:0] floppy_din[2];
    assign floppy_lba[0]=disk_lba[0]; assign floppy_lba[1]=disk_lba[1];
    assign floppy_din[0]=disk_buff_din[0]; assign floppy_din[1]=disk_buff_din[1];
    wire [1:0] floppy_mounted, floppy_readonly, floppy_ack, floppy_buff_wr, floppy_rd, floppy_wr, floppy_invalid;
    generate if(ENABLE) begin: floppies
        // Both drives share one converter (see pc98_floppy_images).
        pc98_floppy_images images (
            .clk(clk),.mounted(image_mounted[1:0]),.readonly(image_readonly),.image_size(image_size),
            .media_mounted(floppy_mounted),.media_readonly(floppy_readonly),.media_size(floppy_size),
            .disk_lba(floppy_lba),.disk_rd(disk_rd[1:0]),.disk_wr(disk_wr[1:0]),
            .disk_buff_din(floppy_din),.disk_ack(floppy_ack),.disk_buff_wr(floppy_buff_wr),
            .disk_buff_addr(floppy_buff_addr),.disk_buff_dout(floppy_buff_dout),
            .host_lba(floppy_host_lba),.host_rd(floppy_rd),.host_wr(floppy_wr),
            .host_buff_din(floppy_host_din),.host_ack(host_ack[1:0]),
            .host_buff_wr(host_buff_wr),.host_buff_addr(host_buff_addr),.host_buff_dout(host_buff_dout),
            .invalid(floppy_invalid)
        );
    end endgenerate
    genvar i;
    generate for(i=0;i<4;i=i+1) begin: slots
        if(ENABLE && i<2) begin: floppy
            assign mounted[i]=floppy_mounted[i];
            assign readonly[i]=floppy_readonly[i];
            assign size[i]=floppy_size[i];
            assign disk_ack[i]=floppy_ack[i];
            assign disk_buff_wr[i]=floppy_buff_wr[i];
            assign disk_buff_addr[i]=floppy_buff_addr[i];
            assign disk_buff_dout[i]=floppy_buff_dout[i];
            assign host_lba[i]=floppy_host_lba[i];
            assign host_rd[i]=floppy_rd[i];
            assign host_wr[i]=floppy_wr[i];
            assign host_buff_din[i]=floppy_host_din[i];
            assign invalid[i]=floppy_invalid[i];
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
