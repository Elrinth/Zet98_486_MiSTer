// SPDX-License-Identifier: GPL-3.0-or-later
// Present regular HDM/FDI as a read-only virtual D88 for both floppy slots.
// D88 uses the original read/write transport without translation. Other
// headers (including NFD) reject the mount instead of silently losing their
// meaning.
//
// One converter serves both drives: a mount header parse or a virtual sector
// transfer owns the shared datapath and 512-byte source cache until it ends.
// Each drive keeps only its published geometry. Mounting a drive aborts that
// drive's own parse/transfer; a pending job for the other drive waits.
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
    localparam IDLE=0, FETCH=1, FETCH_ACK=2, HEADER=3, GEOMETRY=4, PUBLISH=5,
        LOAD=6, START=7, LOCATE=8, BYTE=9, CACHE_WAIT=10, EMIT=11, END_ACK=12,
        REJECT=13, HCHECK=14;
    reg [3:0] state = IDLE, resume_state;
    reg owner = 0, cache_owner = 0;

    // Per-drive mount state and published geometry.
    reg [1:0] pending = 0, ready = 0, slot_direct = 0, slot_ro = 2'b11;
    reg [31:0] slot_size[2], slot_media_size[2];
    reg [1:0] slot_big = 0;
    reg [31:0] slot_base[2], slot_virtual[2];
    reg [7:0] slot_cylinders[2], slot_sectors[2], slot_media[2];
    reg [12:0] slot_sector_bytes[2];
    reg [2:0] slot_size_code[2];
    reg [23:0] slot_track_bytes[2];
    initial begin
        slot_media_size[0]=0; slot_media_size[1]=0;
    end
    assign media_size[0] = {32'b0, slot_media_size[0]};
    assign media_size[1] = {32'b0, slot_media_size[1]};

    // Shared working copy.
    reg direct = 0, cache_valid = 0, transfer_active = 0, ro = 1, big = 0;
    reg [31:0] size = 0;
    reg [31:0] header[0:7];
    // Header tests, registered one state ahead of HEADER: evaluated in one
    // cycle they failed timing on hardware (FDI rejected, HDM/D88 fine).
    reg d88_header, fdi_header, fdi_layout, fdi_length;
    reg [31:0] cache_lba = 0, base = 0, virtual_size;
    reg [7:0] cylinders, sectors, media;
    reg [12:0] sector_bytes;
    reg [2:0] size_code;
    reg [31:0] payload_bytes;
    reg [23:0] track_bytes;
    reg [8:0] byte_index;
    reg [31:0] position, remainder;
    reg [7:0] track;
    reg [5:0] sector_index;
    reg [12:0] sector_offset;
    reg [7:0] generated;
    reg [7:0] cache_q;
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] cache[0:511];

    wire [1:0] passthrough = slot_direct & ready & ~mounted;
    wire converting = state != IDLE;
    genvar i;
    generate for (i = 0; i < 2; i = i + 1) begin: port
        wire own = converting && owner == i;
        assign host_lba[i] = passthrough[i] ? disk_lba[i] : cache_lba;
        assign host_rd[i] = !mounted[i] && (passthrough[i] ? disk_rd[i] : own && state == FETCH);
        assign host_wr[i] = passthrough[i] && disk_wr[i];
        assign host_buff_din[i] = disk_buff_din[i];
        assign disk_ack[i] = !mounted[i] && (passthrough[i] ? host_ack[i] : own && transfer_active);
        assign disk_buff_wr[i] = !mounted[i] &&
            (passthrough[i] ? (host_buff_wr && host_ack[i]) : own && state == EMIT);
        assign disk_buff_addr[i] = passthrough[i] ? host_buff_addr : byte_index;
        assign disk_buff_dout[i] = passthrough[i] ? host_buff_dout : generated;
    end endgenerate

    wire owner_ack = host_ack[owner];
    // A drive may start a job once its own host and disk sides are quiet.
    wire [1:0] quiet = ~host_ack & ~disk_rd & ~disk_wr & ~mounted;
    wire [1:0] wants_read = ready & ~slot_direct & ~mounted & disk_rd;
    wire [31:0] source_address = base + ((32'(track)*sectors + sector_index) << (size_code+7)) + sector_offset - 16;
    always @(posedge clk) begin
        cache_q <= cache[source_address[8:0]];
        if ((state == FETCH || state == FETCH_ACK) && owner_ack && host_buff_wr)
            cache[host_buff_addr] <= host_buff_dout;
        if ((state == FETCH || state == FETCH_ACK) && cache_lba == 0 && resume_state == HEADER &&
            owner_ack && host_buff_wr && host_buff_addr < 32)
            header[host_buff_addr[4:2]][host_buff_addr[1:0]*8 +: 8] <= host_buff_dout;
        media_mounted <= 0;
        case(state)
            IDLE: begin
                if (pending[0] && quiet[0] || pending[1] && quiet[1]) begin
                    owner <= !(pending[0] && quiet[0]);
                    size <= pending[0] && quiet[0] ? slot_size[0] : slot_size[1];
                    big <= pending[0] && quiet[0] ? slot_big[0] : slot_big[1];
                    ro <= pending[0] && quiet[0] ? slot_ro[0] : slot_ro[1];
                    pending[!(pending[0] && quiet[0])] <= 0;
                    direct <= 0; cache_valid <= 0; cache_lba <= 0;
                    state <= FETCH; resume_state <= HEADER;
                end else if (wants_read != 0) begin
                    owner <= !wants_read[0]; state <= LOAD;
                end
            end
            FETCH: if (owner_ack) state <= FETCH_ACK;
            FETCH_ACK: if (!owner_ack) begin
                cache_valid <= 1; cache_owner <= owner;
                state <= resume_state == HEADER ? HCHECK : resume_state;
            end
            HCHECK: begin
                d88_header <= size >= 688 && header[7] == size && header[6][31:24] <= 8'h20;
                fdi_header <= header[0] == 0 && (header[2] != 0 || header[4] != 0);
                // Regular, two-sided FDI only. Other layouts are rejected.
                fdi_layout <= !(header[2] < 32 || header[4] != 512 && header[4] != 1024 ||
                        header[5] < 1 || header[5] > 26 || header[6] != 2 ||
                        !((header[7]==77 && header[5]==8 && header[4]==1024) ||
                          (header[7]==80 && header[4]==512 && (header[5]==8 || header[5]==9 || header[5]==15 || header[5]==18)) ||
                          (header[7]==40 && header[5]==8 && header[4]==512)));
                fdi_length <= {1'b0,header[2]}+{1'b0,header[3]} == {1'b0,size};
                state <= HEADER;
            end
            HEADER: begin
                base <= 0; cylinders<=77; sectors<=8; sector_bytes<=1024; size_code<=3; media<=8'h20;
                if (big) state <= REJECT;
                else if (d88_header) begin
                    direct <= 1; virtual_size <= size; state <= PUBLISH;
                end else if (fdi_header) begin
                    if (!fdi_layout || !fdi_length) state<=REJECT;
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
            GEOMETRY: begin
                payload_bytes <= 32'(cylinders)*2*sectors*sector_bytes;
                track_bytes <= 24'(sectors)*(sector_bytes+16);
                virtual_size <= 688 + 32'(cylinders)*2*sectors*(sector_bytes+16);
                state<=PUBLISH;
            end
            PUBLISH: begin
                if (!direct && base+payload_bytes != size) state<=REJECT;
                else begin
                    slot_media_size[owner]<=virtual_size; media_readonly[owner]<=direct ? ro : 1'b1;
                    media_mounted[owner]<=1; ready[owner]<=1; slot_direct[owner]<=direct;
                    slot_base[owner]<=base; slot_virtual[owner]<=virtual_size;
                    slot_cylinders[owner]<=cylinders; slot_sectors[owner]<=sectors;
                    slot_media[owner]<=media; slot_sector_bytes[owner]<=sector_bytes;
                    slot_size_code[owner]<=size_code; slot_track_bytes[owner]<=track_bytes;
                    state<=IDLE;
                end
            end
            LOAD: begin
                base<=slot_base[owner]; virtual_size<=slot_virtual[owner];
                cylinders<=slot_cylinders[owner]; sectors<=slot_sectors[owner];
                media<=slot_media[owner]; sector_bytes<=slot_sector_bytes[owner];
                size_code<=slot_size_code[owner]; track_bytes<=slot_track_bytes[owner];
                if (cache_owner != owner) cache_valid<=0;
                state<=START;
            end
            START: begin
                transfer_active<=1; position<={disk_lba[owner],9'b0}; remainder<={disk_lba[owner],9'b0}-688;
                byte_index<=0; track<=0; sector_index<=0; sector_offset<=0;
                state<=(disk_lba[owner] <= 1 || {disk_lba[owner],9'b0} >= virtual_size) ? BYTE : LOCATE;
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
            END_ACK: if(!disk_rd[owner] && !disk_wr[owner]) begin state<=IDLE; transfer_active<=0; end
            REJECT: begin
                invalid[owner]<=1; slot_media_size[owner]<=0; media_mounted[owner]<=1; state<=IDLE;
            end
            default: state<=IDLE;
        endcase
        // A new mount (or eject) of a drive discards its geometry and aborts
        // that drive's own job; it wins over the state machine above.
        for (integer s = 0; s < 2; s = s + 1) if (mounted[s]) begin
            slot_size[s] <= image_size[31:0]; slot_big[s] <= image_size[63:32] != 0;
            slot_ro[s] <= readonly; pending[s] <= image_size != 0;
            ready[s] <= 0; slot_direct[s] <= 0; invalid[s] <= 0;
            if (cache_owner == s) cache_valid <= 0;
            slot_media_size[s] <= 0; media_readonly[s] <= 1; media_mounted[s] <= 1;
            if (converting && owner == s) begin
                state <= IDLE; transfer_active <= 0; cache_valid <= 0;
            end
        end
    end
endmodule
