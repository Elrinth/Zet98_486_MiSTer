// SPDX-License-Identifier: GPL-3.0-or-later
// Present regular HDM/FDI and standard 77-cylinder NFD-R0 as a read-only
// virtual D88. D88 uses the original read/write transport without translation.
// Unsupported headers/protection records reject the mount instead of silently
// losing their meaning. The source sector cache is private to each drive.
module pc98_floppy_image (
    input wire clk,
    input wire mounted, readonly,
    input wire [63:0] image_size,
    output reg media_mounted = 0,
    output reg media_readonly = 1,
    output reg [63:0] media_size = 0,
    input wire [31:0] disk_lba,
    input wire disk_rd, disk_wr,
    input wire [7:0] disk_buff_din,
    output wire disk_ack,
    output wire disk_buff_wr,
    output wire [8:0] disk_buff_addr,
    output wire [7:0] disk_buff_dout,
    output wire [31:0] host_lba,
    output wire host_rd, host_wr,
    output wire [7:0] host_buff_din,
    input wire host_ack, host_buff_wr,
    input wire [8:0] host_buff_addr,
    input wire [7:0] host_buff_dout,
    output reg invalid = 0
);
    localparam DRAIN=0, FETCH=1, FETCH_ACK=2, HEADER=3, GEOMETRY=4,
        NFD_CHECK=5, PUBLISH=6, IDLE=7, LOCATE=8, BYTE=9, CACHE_WAIT=10,
        EMIT=11, END_ACK=12, REJECT=13;
    reg [3:0] state = DRAIN, resume_state;
    reg pending = 0, direct = 0, cache_valid = 0, transfer_active = 0;
    reg [63:0] size = 0;
    reg ro = 1;
    reg [31:0] header[0:7];
    reg [31:0] cache_lba = 0, base = 0, virtual_size;
    reg [7:0] cylinders, sectors;
    reg [12:0] sector_bytes;
    reg [2:0] size_code;
    reg [7:0] media;
    reg [31:0] payload_bytes;
    reg [23:0] track_bytes;
    reg [8:0] byte_index;
    reg [31:0] position, remainder;
    reg [7:0] track;
    reg [5:0] sector_index;
    reg [12:0] sector_offset;
    reg [7:0] generated;
    reg nfd_bad = 0;
    reg [7:0] nfd_track;
    reg [4:0] nfd_sector;
    reg [3:0] nfd_byte;
    reg [31:0] nfd_offset;
    reg [7:0] cache_q;
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] cache[0:511];
    wire passthrough = direct && state == IDLE && !mounted;
    wire virtual_ack = transfer_active;
    assign host_lba = passthrough ? disk_lba : cache_lba;
    assign host_rd = !mounted && (passthrough ? disk_rd : state == FETCH);
    assign host_wr = passthrough && disk_wr;
    assign host_buff_din = disk_buff_din;
    assign disk_ack = !mounted && (passthrough ? host_ack : virtual_ack);
    assign disk_buff_wr = !mounted && (passthrough ? (host_buff_wr && host_ack) : state == EMIT);
    assign disk_buff_addr = passthrough ? host_buff_addr : byte_index;
    assign disk_buff_dout = passthrough ? host_buff_dout : generated;
    wire [31:0] source_address = base + ((32'(track)*sectors + sector_index) << (size_code+7)) + sector_offset - 16;
    wire [8:0] cache_address = state == NFD_CHECK ? nfd_offset[8:0] : source_address[8:0];
    always @(posedge clk) begin
        cache_q <= cache[cache_address];
        if ((state == FETCH || state == FETCH_ACK) && host_ack && host_buff_wr)
            cache[host_buff_addr] <= host_buff_dout;
        if ((state == FETCH || state == FETCH_ACK) && cache_lba == 0 &&
            host_ack && host_buff_wr && host_buff_addr < 32)
            header[host_buff_addr[4:2]][host_buff_addr[1:0]*8 +: 8] <= host_buff_dout;
        // NFD metadata is checked as it arrives, before exposing any media.
        // Standard records: CHRN, MFM, no deleted/error/retry sectors, 2HD.
        if ((state == FETCH || state == FETCH_ACK) && resume_state == NFD_CHECK &&
            host_ack && host_buff_wr) begin
            if ({cache_lba,host_buff_addr} == 272 && host_buff_dout != 8'h10) nfd_bad <= 1;
            if ({cache_lba,host_buff_addr} == 273 && host_buff_dout != 8'h0a) nfd_bad <= 1;
            if ({cache_lba,host_buff_addr} == 274 && host_buff_dout != 1) nfd_bad <= 1;
            if ({cache_lba,host_buff_addr} == 275 && host_buff_dout != 0) nfd_bad <= 1;
            if ({cache_lba,host_buff_addr} == 277 && host_buff_dout != 2) nfd_bad <= 1;
            if ({cache_lba,host_buff_addr} >= 288 && {cache_lba,host_buff_addr} < 68096) begin
                if (nfd_byte == 0) begin
                    if (host_buff_dout != (nfd_track < 154 && nfd_sector < 8 ? nfd_track >> 1 : 255)) nfd_bad <= 1;
                end else if (nfd_track < 154 && nfd_sector < 8) begin
                    case(nfd_byte)
                        1: if(host_buff_dout != {7'b0,nfd_track[0]}) nfd_bad <= 1;
                        2: if(host_buff_dout != nfd_sector+1) nfd_bad <= 1;
                        3: if(host_buff_dout != 3) nfd_bad <= 1;
                        4: if(host_buff_dout != 1) nfd_bad <= 1;
                        5,6,8,9: if(host_buff_dout != 0) nfd_bad <= 1;
                        7: if((host_buff_dout & 8'hf8) != 0) nfd_bad <= 1;
                        10: if(host_buff_dout != 8'h90 && host_buff_dout != 8'h30) nfd_bad <= 1;
                        default: ;
                    endcase
                end
                nfd_byte <= nfd_byte+1'b1;
                if(nfd_byte == 15) begin
                    nfd_sector <= nfd_sector+1'b1;
                    if(nfd_sector == 25) begin nfd_sector<=0; nfd_track<=nfd_track+1'b1; end
                end
            end
        end
        media_mounted <= 0;
        if (mounted) begin
            size <= image_size; ro <= readonly; pending <= image_size != 0;
            state <= DRAIN; direct <= 0; invalid <= 0; cache_valid <= 0; transfer_active <= 0;
            media_size <= 0; media_readonly <= 1; media_mounted <= 1;
            nfd_bad <= 0; nfd_track <= 0; nfd_sector <= 0; nfd_byte <= 0;
        end else case(state)
            DRAIN: if (!host_ack && !disk_rd && !disk_wr && pending) begin
                pending <= 0; cache_lba <= 0; state <= FETCH; resume_state <= HEADER;
            end
            FETCH: if(host_ack) state <= FETCH_ACK;
            FETCH_ACK: if(!host_ack) begin cache_valid<=1; state<=resume_state; end
            HEADER: begin
                base <= 0; cylinders<=77; sectors<=8; sector_bytes<=1024; size_code<=3; media<=8'h20;
                if(size >= 688 && header[7] == size && header[6][31:24] <= 8'h20) begin
                    direct <= 1; virtual_size <= size[31:0]; state <= PUBLISH;
                end else if(header[0] == 32'h46383954 && header[1] == 32'h4d494444) begin
                    if(header[2] != 32'h2e454741 || header[3][23:0] != 24'h003052 || size != 1329680) state <= REJECT;
                    else begin
                        base<=68112; state<=FETCH; cache_lba<=0; resume_state<=NFD_CHECK;
                    end
                end else if(header[0] == 0 && (header[2] != 0 || header[4] != 0)) begin
                    // Regular, two-sided FDI only. Other layouts are rejected.
                    if(header[2] < 32 || header[4] != 512 && header[4] != 1024 ||
                        header[5] < 1 || header[5] > 26 || header[6] != 2 ||
                        !((header[7]==77 && header[5]==8 && header[4]==1024) ||
                          (header[7]==80 && header[4]==512 && (header[5]==8 || header[5]==9 || header[5]==15 || header[5]==18)) ||
                          (header[7]==40 && header[5]==8 && header[4]==512)) ||
                        {32'b0,header[2]}+{32'b0,header[3]} != size) state<=REJECT;
                    else begin
                        base<=header[2]; cylinders<=header[7][7:0]; sectors<=header[5][7:0];
                        sector_bytes<=header[4][12:0]; size_code<=header[4]==512 ? 2 : 3;
                        media<=header[3]<1000000 ? (header[7]<=42 ? 0 : 8'h10) : 8'h20;
                        state<=GEOMETRY;
                    end
                end else begin
                    state<=GEOMETRY;
                    case(size)
                        1261568: ;
                        1228800: begin cylinders<=80; sectors<=15; sector_bytes<=512; size_code<=2; end
                        1474560: begin cylinders<=80; sectors<=18; sector_bytes<=512; size_code<=2; end
                        655360: begin cylinders<=80; sectors<=8; sector_bytes<=512; size_code<=2; media<=8'h10; end
                        737280: begin cylinders<=80; sectors<=9; sector_bytes<=512; size_code<=2; media<=8'h10; end
                        327680: begin cylinders<=40; sectors<=8; sector_bytes<=512; size_code<=2; media<=0; end
                        default: state<=REJECT;
                    endcase
                end
            end
            NFD_CHECK: begin
                if(cache_lba == 133) begin
                    if(nfd_bad) state<=REJECT; else state<=GEOMETRY;
                end else begin cache_lba<=cache_lba+1'b1; state<=FETCH; end
            end
            GEOMETRY: begin
                payload_bytes <= 32'(cylinders)*2*sectors*sector_bytes;
                track_bytes <= 24'(sectors)*(sector_bytes+16);
                virtual_size <= 688 + 32'(cylinders)*2*sectors*(sector_bytes+16);
                state<=PUBLISH;
            end
            PUBLISH: begin
                if(!direct && 64'(base)+payload_bytes != size) state<=REJECT;
                else begin
                    media_size<=virtual_size; media_readonly<=direct ? ro : 1'b1;
                    media_mounted<=1; state<=IDLE;
                end
            end
            IDLE: if(!direct && disk_rd) begin
                transfer_active<=1; position<={disk_lba,9'b0}; remainder<={disk_lba,9'b0}-688;
                byte_index<=0; track<=0; sector_index<=0; sector_offset<=0;
                state<=(disk_lba <= 1 || {disk_lba,9'b0} >= virtual_size) ? BYTE : LOCATE;
            end
            LOCATE: begin
                if(remainder >= track_bytes) begin remainder<=remainder-track_bytes; track<=track+1'b1; end
                else if(remainder >= sector_bytes+16) begin remainder<=remainder-sector_bytes-16; sector_index<=sector_index+1'b1; end
                else begin sector_offset<=remainder[12:0]; state<=BYTE; end
            end
            BYTE: begin
                if(position >= virtual_size) begin generated<=0; state<=EMIT; end
                else if(position < 688) begin
                    generated<=0; state<=EMIT;
                    if(position == 26) generated<=8'h10;
                    if(position == 27) generated<=media;
                    if(position >= 28 && position < 32) generated<=virtual_size >> (position[1:0]*8);
                    if(position >= 32 && (position-32)/4 < 2*cylinders)
                        generated <= (688+((position-32)/4)*track_bytes) >> (position[1:0]*8);
                end else if(sector_offset < 16) begin
                    generated<=0; state<=EMIT;
                    case(sector_offset)
                        0: generated<=track>>1;
                        1: generated<={7'b0,track[0]};
                        2: generated<=sector_index+1'b1;
                        3: generated<={5'b0,size_code};
                        4: generated<=sectors;
                        14: generated<=sector_bytes[7:0];
                        15: generated<={3'b0,sector_bytes[12:8]};
                        default: ;
                    endcase
                end else if(!cache_valid || cache_lba != source_address[31:9]) begin
                    cache_lba<={9'b0,source_address[31:9]}; state<=FETCH; resume_state<=CACHE_WAIT;
                end else state<=CACHE_WAIT;
            end
            CACHE_WAIT: begin generated<=cache_q; state<=EMIT; end
            EMIT: begin
                position<=position+1'b1; byte_index<=byte_index+1'b1;
                if(position >= 688) begin
                    if(sector_offset == sector_bytes+15) begin
                        sector_offset<=0;
                        if(sector_index == sectors-1) begin sector_index<=0; track<=track+1'b1; end
                        else sector_index<=sector_index+1'b1;
                    end else sector_offset<=sector_offset+1'b1;
                end
                state<=byte_index==511 ? END_ACK : BYTE;
            end
            END_ACK: if(!disk_rd && !disk_wr) begin state<=IDLE; transfer_active<=0; end
            REJECT: begin invalid<=1; media_size<=0; media_mounted<=1; state<=DRAIN; end
            default: ;
        endcase
    end
endmodule
