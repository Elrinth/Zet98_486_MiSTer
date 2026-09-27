// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// ATAPI CD-ROM on the PC-98 IDE secondary channel (bank 1, master), backed by
// one MiSTer image slot holding one of:
//   - ISO: 2048-byte sectors, one data track;
//   - BIN: raw 2352-byte sectors (user data at +16, +24 for MODE2), one track;
//   - PCD: scripts/pc98_cd_image.py output: a 2352-byte header with the track
//     table and ready-made TOC address fields, then raw sectors. Data and CD
//     audio tracks, so games can play their music (CD-DA).
// Behaviour follows NP2kai cbus/ideio.c and atapicmd.c (5939e0c) and what
// NEC's NECCDD.SYS + MSCDEX use; no emulator code is copied.
//   - INQUIRY answers "NEC     CD-ROM DRIVE:98 " revision "1.0 " (NECCDD
//     requires the vendor/product prefix; revision < 3 selects its BCD mode).
//   - READ(10): one 2048-byte sector per DRQ with an IRQ each, then a
//     completion IRQ. Other data-in commands send one DRQ block.
//   - MODE SENSE page 0Fh (NEC) switches MSF addresses to BCD, including
//     PLAY AUDIO MSF parameters.
//   - PLAY AUDIO(10)/MSF stream the audio sectors through a FIFO at 44.1 kHz
//     (audio_l/audio_r); READ SUB-CHANNEL reports status and position (MSF,
//     as NP2kai). READ, SEEK, START/STOP UNIT and STOP PLAY stop playback.
// The parent (pc98_ide) decodes ports and routes bank-1 accesses here.
module pc98_atapi #(parameter integer CLK_HZ = 90000000) (
    input wire clk, reset,
    // Register access for the secondary channel (already bank-decoded).
    input wire [2:0] reg_index,          // 0 data, 1 error/features ... 7 status/command
    input wire reg_write, reg_read,      // one-cycle strobes (read: after the CPU sampled)
    input wire [15:0] writedata,
    input wire word_access,              // 16-bit data port access
    input wire ctrl_write,               // 074Ch write
    input wire [7:0] ctrl_data,
    output reg [15:0] readdata,          // for reg_index / alt status (combinational)
    input wire read_alt,                 // readdata selects alternate status
    output wire irq,
    output wire present,                 // master device exists (always, once enabled)
    // CD audio, signed 16-bit, updated at 44.1 kHz
    output reg signed [15:0] audio_l = 0,
    output reg signed [15:0] audio_r = 0,
    // Image slot
    input wire image_mounted,
    input wire [63:0] image_size,
    output reg [31:0] sd_lba = 0,
    output reg sd_rd = 0,
    input wire sd_ack,
    input wire [8:0] sd_buff_addr,
    input wire [7:0] sd_buff_dout,
    input wire sd_buff_wr
);
    assign present = 1'b1;

    // ---- media ------------------------------------------------------------
    // After a mount the first four image blocks are read (probe). A PCD
    // header ("PC98CD01") supplies the track table and lead-out; otherwise a
    // raw-sector sync pattern (00 FF x10 00) selects 2352-byte sectors, else
    // 2048 (ISO). For ISO/BIN a bit-serial divider derives the sector count
    // and the lead-out M:S:F (binary and BCD). The same divider converts the
    // play position for READ SUB-CHANNEL.
    reg media = 0, raw = 0, pcd = 0, mode2 = 0, changed = 0;
    reg [19:0] total = 0;                // sectors on the disc (< 2^20)
    reg [6:0] trk_n = 1, trk_first = 1;  // tracks on the disc, first track number
    reg [7:0] lo_m, lo_s, lo_f;          // ISO/BIN lead-out minute/second/frame (binary)
    reg [7:0] lo_mb, lo_sb, lo_fb;       // the same in BCD
    reg [7:0] ab_m, ab_s, ab_f, rl_m, rl_s, rl_f;  // sub-channel absolute/relative MSF
    reg [36:0] img_bytes = 0;
    reg probe_pending = 0, probing = 0, sync_ok = 0, magic_ok = 0, probe_done = 0;
    reg [1:0] pblk = 0;                  // probe block 0..3
    reg [6:0] hdr_n, hdr_first;
    reg [31:0] hdr_leadout;
    reg hdr_mode2, bin_mode2;
    localparam [63:0] MAGIC = "PC98CD01";
    reg conv_go = 0;                     // start an LBA -> MSF conversion
    reg [31:0] conv_val;
    reg [1:0] conv_to;                   // 0 lead-out, 1 absolute, 2 relative

    // Serial divider: q = a / b, r = a % b, 32 clocks.
    reg [31:0] dv_a, dv_q;
    reg [31:0] dv_r;
    reg [15:0] dv_b;
    reg [5:0] dv_n = 0;
    wire [32:0] dv_try = {dv_r, dv_a[31]} - {17'b0, dv_b};
    wire dv_busy = dv_n != 0;
    // Conversion steps.
    localparam M_IDLE=0, M_TOTAL=1, M_MIN=2, M_SEC=3, M_MB=4, M_SB=5, M_FB=6;
    reg [2:0] mstep = M_IDLE;
    reg [1:0] conv_tgt = 0;
    reg [7:0] t_m, t_s, t_f, t_mb, t_sb;
    wire msf_busy = mstep != M_IDLE;
    reg bcd_mode = 0;
    reg clear_changed;
    task automatic divide(input [31:0] a, input [15:0] b);
        begin dv_a <= a; dv_b <= b; dv_r <= 0; dv_q <= 0; dv_n <= 32; end
    endtask
    wire [7:0] dv_bcd = {dv_q[3:0], dv_r[3:0]};
    always @(posedge clk) begin
        if (dv_busy) begin
            dv_n <= dv_n - 1'b1;
            dv_a <= {dv_a[30:0], 1'b0};
            if (!dv_try[32]) begin dv_r <= dv_try[31:0]; dv_q <= {dv_q[30:0], 1'b1}; end
            else begin dv_r <= {dv_r[30:0], dv_a[31]}; dv_q <= {dv_q[30:0], 1'b0}; end
        end
        if (image_mounted) begin
            media <= 0; changed <= 1; mstep <= M_IDLE; dv_n <= 0; pcd <= 0;
            img_bytes <= image_size[63:37] == 0 ? image_size[36:0] : 37'd0;
        end else if (probe_done) begin
            trk_n <= 1; trk_first <= 1;
            if (magic_ok && hdr_n != 0 && hdr_n < 100 && hdr_leadout[31:20] == 0 && hdr_leadout != 0) begin
                raw <= 1; pcd <= 1; mode2 <= hdr_mode2; total <= hdr_leadout[19:0];
                trk_n <= hdr_n; trk_first <= hdr_first; media <= 1;
            end else if (sync_ok && img_bytes[36:31] == 0) begin
                raw <= 1; mode2 <= bin_mode2; mstep <= M_TOTAL; divide(img_bytes[31:0], 16'd2352);
            end else if (img_bytes[10:0] == 0 && img_bytes != 0 && img_bytes[36:31] == 0) begin
                raw <= 0; mode2 <= 0; total <= img_bytes[30:11];
                conv_tgt <= 0; mstep <= M_MIN; divide({12'b0, img_bytes[30:11]} + 32'd150, 16'd4500);
            end
        end else if (conv_go) begin
            conv_tgt <= conv_to; mstep <= M_MIN; divide(conv_val, 16'd4500);
        end else if (msf_busy && !dv_busy) case (mstep)
            M_TOTAL: if (dv_q == 0) mstep <= M_IDLE;
                     else begin
                         total <= dv_q[19:0]; conv_tgt <= 0;
                         mstep <= M_MIN; divide({12'b0, dv_q[19:0]} + 32'd150, 16'd4500);
                     end
            M_MIN:   begin t_m <= dv_q[7:0]; mstep <= M_SEC; divide(dv_r, 16'd75); end
            M_SEC:   begin t_s <= dv_q[7:0]; t_f <= dv_r[7:0]; mstep <= M_MB; divide({24'b0, t_m}, 16'd10); end
            M_MB:    begin t_mb <= dv_bcd; mstep <= M_SB; divide({24'b0, t_s}, 16'd10); end
            M_SB:    begin t_sb <= dv_bcd; mstep <= M_FB; divide({24'b0, t_f}, 16'd10); end
            M_FB:    begin
                         mstep <= M_IDLE;
                         case (conv_tgt)
                             2'd0: begin
                                 {lo_m, lo_s, lo_f} <= {t_m, t_s, t_f};
                                 {lo_mb, lo_sb, lo_fb} <= {t_mb, t_sb, dv_bcd}; media <= 1;
                             end
                             2'd1: {ab_m, ab_s, ab_f} <= bcd_mode ? {t_mb, t_sb, dv_bcd} : {t_m, t_s, t_f};
                             default: {rl_m, rl_s, rl_f} <= bcd_mode ? {t_mb, t_sb, dv_bcd} : {t_m, t_s, t_f};
                         endcase
                     end
            default: mstep <= M_IDLE;
        endcase
        if (clear_changed) changed <= 0;
    end

    // ---- header / track tables ----------------------------------------------
    // hdr: the first 2048 image bytes (PCD header: track table at 16, TOC
    // address fields at 512/1024/1536). trk: the track table as words
    // {LBA[19:0], control} for the sub-channel track search.
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] hdr[0:2047];
    (* ramstyle="M10K, no_rw_check" *) reg [27:0] trk[0:127];
    reg [7:0] hdr_q;
    reg [27:0] trk_q;
    reg [10:0] hdr_raddr;
    reg [6:0] srch_i;
    reg [23:0] trk_sr;
    wire probe_byte = probing && sd_ack && sd_buff_wr;
    wire [6:0] trk_widx = sd_buff_addr[8:2] - 7'd4;
    always @(posedge clk) begin
        if (probe_byte) hdr[{pblk, sd_buff_addr}] <= sd_buff_dout;
        if (probe_byte && pblk == 0 && sd_buff_addr >= 16 && sd_buff_addr < 416 && sd_buff_addr[1:0] == 3)
            trk[trk_widx] <= {sd_buff_dout[3:0], trk_sr[23:8], trk_sr[7:0]};
        if (probe_byte) trk_sr <= {sd_buff_dout, trk_sr[23:8]};
        hdr_q <= hdr[hdr_raddr];
        trk_q <= trk[srch_i];
    end
    // ISO/BIN: the table a one-track PCD header would hold.
    function automatic [7:0] hdr_synth(input [10:0] a);
        begin
            case (a[10:9])
                2'd0: hdr_synth = 8'h14;
                2'd1: hdr_synth = !a[2] ? 8'd0 : a[1:0] == 1 ? {4'b0, total[19:16]} : a[1:0] == 2 ? total[15:8] : a[1:0] == 3 ? total[7:0] : 8'd0;
                2'd2: hdr_synth = !a[2] ? (a[1:0] == 2 ? 8'd2 : 8'd0) : a[1:0] == 1 ? lo_m : a[1:0] == 2 ? lo_s : a[1:0] == 3 ? lo_f : 8'd0;
                default: hdr_synth = !a[2] ? (a[1:0] == 2 ? 8'd2 : 8'd0) : a[1:0] == 1 ? lo_mb : a[1:0] == 2 ? lo_sb : a[1:0] == 3 ? lo_fb : 8'd0;
            endcase
        end
    endfunction
    wire [19:0] trk_lba = pcd ? trk_q[27:8] : 20'd0;
    wire [7:0] trk_ctrl = pcd ? trk_q[7:0] : 8'h14;

    // ---- task file --------------------------------------------------------
    reg [7:0] features, count, sector, cyl_lo, cyl_hi, devhead, status, error_reg, ctrl = 0;
    reg pending_irq = 0;
    wire selected = !devhead[4];
    assign irq = pending_irq && !ctrl[1];

    // ---- command / response state -------------------------------------------
    localparam IDLE=0, PACKET=1, DATA_IN=2, FETCH=3, SECTOR_IN=4, DATA_OUT=5, IDENT=6, BUILD=7,
               PLAYSET=8, SUBQ=9;
    reg [3:0] state = IDLE;
    reg [7:0] cdb[0:11];
    reg [3:0] cdb_words;
    reg [10:0] words_left;               // words in the current DRQ block
    reg [7:0] sense_key = 0, asc = 0, resp_key = 0, resp_asc = 0;
    reg [19:0] read_lba;
    reg [15:0] read_left;

    // CD audio play state (INF-8090 audio status codes).
    localparam [7:0] AS_PLAY = 8'h11, AS_PAUSE = 8'h12, AS_DONE = 8'h13, AS_NONE = 8'h15;
    reg [7:0] audio_status = AS_NONE;
    reg [19:0] play_pos = 0, play_end = 0;
    reg [6:0] sq_trk;
    reg [7:0] sq_ctrl;
    reg [19:0] sq_start;

    // Response generator: byte n of the current command's reply.
    wire [7:0] op = cdb[0];
    wire [15:0] alloc10 = {cdb[7], cdb[8]};
    wire toc_msf = cdb[1][1];
    wire [3:0] toc_fmt = cdb[9][7:6] != 0 ? {2'b0, cdb[9][7:6]} : cdb[2][3:0];
    wire toc_leadout_only = cdb[6] == 8'haa;
    wire [7:0] page = cdb[2][5:0];
    // READ TOC: descriptors for table entries toc_i0 .. trk_n (lead-out).
    wire [7:0] toc_last = trk_first + trk_n - 1'b1;
    wire toc_bad_start = !toc_leadout_only && cdb[6] > toc_last;
    wire [6:0] toc_i0 = toc_fmt == 1 ? 7'd0 : toc_leadout_only ? trk_n :
                        cdb[6] <= trk_first ? 7'd0 : cdb[6][6:0] - trk_first;
    wire [6:0] toc_entries = trk_n - toc_i0 + 1'b1;
    wire [9:0] toc_len = toc_fmt == 1 ? 10'd12 : {toc_entries, 3'b000} + 10'd4;
    reg build_ident;
    reg [9:0] build_n, build_len;
    wire [9:0] toc_off = build_n - 10'd4;
    wire [6:0] toc_desc_idx = toc_i0 + toc_off[9:3];
    wire [2:0] toc_desc_k = toc_off[2:0];
    wire [19:0] total_m1 = total - 1'b1;

    // Mode pages (01h, 0Dh, 0Eh, 0Fh, 2Ah), concatenated for 3Fh.
    function automatic [7:0] page_byte(input [5:0] pg, input [7:0] i);
        begin
            page_byte = 0;
            case (pg)
                6'h01: case (i) 0: page_byte = 8'h01; 1: page_byte = 8'h0a; default: ; endcase
                6'h0d: case (i) 0: page_byte = 8'h0d; 1: page_byte = 8'h06; 5: page_byte = 8'h3c; 7: page_byte = 8'h4b; default: ; endcase
                6'h0e: case (i) 0: page_byte = 8'h0e; 1: page_byte = 8'h0e; 2: page_byte = 8'h04; 7: page_byte = 8'h4b;
                                8: page_byte = 8'h01; 9: page_byte = 8'hff; 10: page_byte = 8'h02; 11: page_byte = 8'hff; default: ; endcase
                6'h0f: case (i) 0: page_byte = 8'h0f; 1: page_byte = 8'h0e; default: ; endcase
                6'h2a: case (i) 0: page_byte = 8'h2a; 1: page_byte = 8'h12; 2: page_byte = 8'h03; 4: page_byte = 8'h71;
                                5: page_byte = 8'h60; 6: page_byte = 8'h29; 8: page_byte = 8'h02; 9: page_byte = 8'hc2;
                                10: page_byte = 8'h01; 11: page_byte = 8'h00; 12: page_byte = 8'h02; 13: page_byte = 8'h00;
                                14: page_byte = 8'h02; 15: page_byte = 8'hc2; default: ; endcase
                default: ;
            endcase
        end
    endfunction
    function automatic [7:0] page_len(input [5:0] pg);
        case (pg)
            6'h01: page_len = 12; 6'h0d: page_len = 8; 6'h0e: page_len = 16; 6'h0f: page_len = 16;
            6'h2a: page_len = 20; 6'h3f: page_len = 72; default: page_len = 0;
        endcase
    endfunction
    function automatic [7:0] all_pages(input [7:0] i);
        if (i < 12) all_pages = page_byte(6'h01, i);
        else if (i < 20) all_pages = page_byte(6'h0d, i - 12);
        else if (i < 36) all_pages = page_byte(6'h0e, i - 20);
        else if (i < 52) all_pages = page_byte(6'h0f, i - 36);
        else all_pages = page_byte(6'h2a, i - 52);
    endfunction

    reg [9:0] resp_len;                  // bytes this command returns (before alloc clip)
    always @* begin
        case (op)
            8'h12: resp_len = 36;
            8'h03: resp_len = 18;
            8'h25: resp_len = 8;
            8'h5a: resp_len = 10'd8 + page_len(page);
            8'h42: resp_len = cdb[2][6] ? 10'd16 : 10'd4;
            8'h43: resp_len = toc_len;
            default: resp_len = 0;
        endcase
    end

    function automatic [7:0] resp_byte(input [9:0] n);
        reg [7:0] b;
        reg [9:0] len2;
        begin
            b = 0;
            len2 = resp_len - 2'd2;
            case (op)
                8'h12: begin // INQUIRY
                    case (n)
                        0: b = 8'h05; 1: b = 8'h80; 3: b = 8'h21; 4: b = 8'h1f;
                        // "NEC     CD-ROM DRIVE:98 1.0 " as a table
                        8: b = 8'h4e; 9: b = 8'h45; 10: b = 8'h43; 11: b = 8'h20; 12: b = 8'h20; 13: b = 8'h20; 14: b = 8'h20; 15: b = 8'h20; 16: b = 8'h43; 17: b = 8'h44; 18: b = 8'h2d; 19: b = 8'h52; 20: b = 8'h4f; 21: b = 8'h4d; 22: b = 8'h20; 23: b = 8'h44; 24: b = 8'h52; 25: b = 8'h49; 26: b = 8'h56; 27: b = 8'h45; 28: b = 8'h3a; 29: b = 8'h39; 30: b = 8'h38; 31: b = 8'h20; 32: b = 8'h31; 33: b = 8'h2e; 34: b = 8'h30; 35: b = 8'h20;
                        default: ;
                    endcase
                end
                8'h03: case (n) 0: b = 8'h70; 2: b = resp_key; 7: b = 8'h0a; 12: b = resp_asc; default: ; endcase
                8'h25: begin
                    case (n)
                        1: b = {4'b0, total_m1[19:16]}; 2: b = total_m1[15:8]; 3: b = total_m1[7:0];
                        6: b = 8'h08; default: ;
                    endcase
                end
                8'h5a: begin // MODE SENSE(10): 8-byte header, then page(s)
                    case (n)
                        0: b = len2[9:8]; 1: b = len2[7:0];
                        2: b = media ? 8'h01 : 8'h70;
                        default: if (n >= 8) b = page == 6'h3f ? all_pages(n - 8) : page_byte(page, n - 8);
                    endcase
                end
                8'h42: case (n) // READ SUB-CHANNEL, format 1 (current position), MSF
                    1: b = audio_status; 3: b = cdb[2][6] ? 8'h0c : 8'h00;
                    4: b = 8'h01; 5: b = sq_ctrl; 6: b = trk_first + sq_trk; 7: b = 8'h01;
                    9: b = ab_m; 10: b = ab_s; 11: b = ab_f;
                    13: b = rl_m; 14: b = rl_s; 15: b = rl_f;
                    default: ;
                endcase
                8'h43: case (n) // READ TOC header; descriptors come from hdr (below)
                    0: b = len2[9:8]; 1: b = len2[7:0];
                    2: b = toc_fmt == 1 ? 8'd1 : {1'b0, trk_first};
                    3: b = toc_fmt == 1 ? 8'd1 : toc_last;
                    default: ;
                endcase
                default: ;
            endcase
            resp_byte = b;
        end
    endfunction

    // IDENTIFY PACKET DEVICE words.
    function automatic [15:0] ident_word(input [7:0] w);
        begin
            case (w)
                0: ident_word = 16'h8580;
                23: ident_word = "1.";
                24: ident_word = "0 ";
                25, 26: ident_word = "  ";
                49: ident_word = 16'h0200;
                51: ident_word = 16'h0278;
                53: ident_word = 16'h0003;
                64: ident_word = 16'h0003;
                80: ident_word = 16'h003e;
                82: ident_word = 16'h0214;
                93: ident_word = 16'h407b;
                10, 11, 12, 13, 14, 15, 16, 17, 18, 19: ident_word = "  ";
                // "NEC CD-ROM DRIVE:98" padded to 40 characters, as a table
                27: ident_word = 16'h4e45; 28: ident_word = 16'h4320; 29: ident_word = 16'h4344; 30: ident_word = 16'h2d52; 31: ident_word = 16'h4f4d; 32: ident_word = 16'h2044; 33: ident_word = 16'h5249; 34: ident_word = 16'h5645; 35: ident_word = 16'h3a39; 36: ident_word = 16'h3820; 37: ident_word = 16'h2020; 38: ident_word = 16'h2020; 39: ident_word = 16'h2020; 40: ident_word = 16'h2020; 41: ident_word = 16'h2020; 42: ident_word = 16'h2020; 43: ident_word = 16'h2020; 44: ident_word = 16'h2020; 45: ident_word = 16'h2020; 46: ident_word = 16'h2020;
                default: ident_word = 0;
            endcase
        end
    endfunction

    // ---- sector buffer: up to 5 host blocks (raw sectors straddle blocks) ----
    (* ramstyle="M10K, no_rw_check" *) reg [7:0] buf_lo[0:2047], buf_hi[0:2047];
    reg [2:0] blk;                       // host block being fetched (0..4)
    reg [2:0] blocks;                    // blocks needed for this sector
    reg [21:0] first_block;
    reg [8:0] start_off;                 // byte offset of user data in block 0
    reg [10:0] rd_word;                  // word address of the next CPU read
    reg [7:0] buf_q_lo, buf_q_hi;
    reg host_req = 0;
    wire host_write = sd_buff_wr && sd_ack && state == FETCH && host_req;
    wire [10:0] host_waddr = {blk, sd_buff_addr[8:1]} ;
    // Reply builder: one byte (or IDENTIFY word) per clock. READ TOC
    // descriptors read hdr, so the buffer write is one clock behind.
    wire [1:0] toc_table = toc_msf ? (bcd_mode ? 2'd3 : 2'd2) : 2'd1;
    wire toc_from_hdr = op == 8'h43 && build_n >= 4 && (toc_desc_k == 1 || toc_desc_k[2]);
    always @* hdr_raddr = toc_desc_k == 1 ? {2'b0, toc_desc_idx, 2'b00} + 11'd16
                                           : {toc_table, toc_desc_idx, toc_desc_k[1:0]};
    // READ TOC descriptor byte 2: the track number (AAh for the lead-out).
    wire [7:0] build_byte = op == 8'h43 && build_n >= 4 && toc_desc_k == 2 ?
                            (toc_desc_idx == trk_n ? 8'haa : trk_first + toc_desc_idx) : resp_byte(build_n);
    wire [15:0] build_word = ident_word(build_n[7:0]);
    reg b_we = 0, b_ident, b_hdr, b_odd;
    reg [10:0] b_waddr, b_haddr;
    reg [7:0] b_byte;
    reg [15:0] b_word;
    wire [7:0] b_final = !b_hdr ? b_byte : pcd ? hdr_q : hdr_synth(b_haddr);
    always @(posedge clk) begin
        b_we <= state == BUILD;
        b_ident <= build_ident; b_odd <= build_n[0];
        b_hdr <= toc_from_hdr; b_haddr <= hdr_raddr;
        b_waddr <= build_ident ? {3'b0, build_n[7:0]} : {1'b0, build_n[9:1]};
        b_byte <= build_byte; b_word <= build_word;
        if (host_write) begin
            if (sd_buff_addr[0]) buf_hi[host_waddr] <= sd_buff_dout;
            else buf_lo[host_waddr] <= sd_buff_dout;
        end else if (b_we) begin
            if (b_ident || !b_odd) buf_lo[b_waddr] <= b_ident ? b_word[7:0] : b_final;
            if (b_ident || b_odd) buf_hi[b_waddr] <= b_ident ? b_word[15:8] : b_final;
        end
        buf_q_lo <= buf_lo[rd_word];
        buf_q_hi <= buf_hi[rd_word];
    end
    // Image byte address of sector read_lba (PCD: after the header sector)
    // and of its user data.
    wire [30:0] lba_x2352 = {read_lba, 11'b0} + {read_lba, 8'b0} + {read_lba, 5'b0} + {read_lba, 4'b0};
    wire [30:0] sector_base = !raw ? {read_lba, 11'b0} : lba_x2352 + (pcd ? 31'd2352 : 31'd0);
    wire [30:0] sector_byte = sector_base + (!raw ? 31'd0 : mode2 ? 31'd24 : 31'd16);
    wire [30:0] sector_base_m1 = sector_base - 1'b1;

    // ---- CD audio stream ----------------------------------------------------
    // Blocks from the play start onward are fetched into a 2048-sample FIFO
    // (4 bytes each: left, right, little-endian) whenever there is room, and
    // one sample leaves it every 1/44100 s while playing. 588 samples make a
    // sector; play_pos counts sectors played.
    (* ramstyle="M10K, no_rw_check" *) reg [31:0] afifo[0:2047];
    reg [31:0] afifo_q;
    reg [11:0] wp = 0, rp = 0;
    wire [11:0] level = wp - rp;
    reg a_req = 0, a_drop = 0, a_we_d = 0;
    reg [1:0] a_cnt = 0;
    reg [23:0] a_word;
    reg [8:0] a_skip;
    reg [21:0] fetch_blk, fetch_last;
    reg [9:0] samp;
    wire audio_active = audio_status == AS_PLAY || audio_status == AS_PAUSE;
    wire a_byte = a_req && !a_drop && sd_ack && sd_buff_wr && sd_buff_addr >= a_skip;
    wire a_we = a_byte && a_cnt == 3;
    always @(posedge clk) begin
        if (a_we) afifo[wp[10:0]] <= {sd_buff_dout, a_word};
        afifo_q <= afifo[rp[10:0]];
        a_we_d <= a_we;
    end
    reg [31:0] tick_acc = 0;
    wire [31:0] tick_next = tick_acc + 32'd44100;
    wire tick = tick_next >= CLK_HZ;
    // PLAY AUDIO MSF parameters -> frames (BCD in NEC mode).
    function automatic [20:0] frames(input [7:0] m, input [7:0] s, input [7:0] f, input b);
        reg [7:0] mm, ss, ff;
        begin
            mm = b ? m[7:4] * 8'd10 + m[3:0] : m;
            ss = b ? s[7:4] * 8'd10 + s[3:0] : s;
            ff = b ? f[7:4] * 8'd10 + f[3:0] : f;
            frames = mm * 21'd4500 + ss * 21'd75 + ff;
        end
    endfunction
    reg [2:0] ps;                        // PLAYSET step
    reg [20:0] p_start, p_end;
    wire [20:0] msf_frames = ps[0] ? frames(cdb[6], cdb[7], cdb[8], bcd_mode) : frames(cdb[3], cdb[4], cdb[5], bcd_mode);
    wire [20:0] msf_lba = msf_frames >= 150 ? msf_frames - 21'd150 : 21'd0;
    wire [20:0] p_end_c = p_end > {1'b0, total} ? {1'b0, total} : p_end;
    reg [2:0] sq;                        // SUBQ step

    // ---- register reads -------------------------------------------------------
    wire drq = state == DATA_IN || state == SECTOR_IN || state == PACKET || state == DATA_OUT;
    wire busy = state == FETCH || state == BUILD || state == PLAYSET || state == SUBQ ||
                (state == IDLE && cdb_words == 6) || msf_busy || probe_pending || probing;
    wire [7:0] cur_status = !selected ? 8'hff : busy ? 8'h80 : (status | (drq ? 8'h08 : 8'h00));
    reg [15:0] data_word;
    always @* begin
        data_word = {buf_q_hi, buf_q_lo};
        if (read_alt) readdata = {8'hff, cur_status};
        else case (reg_index)
            3'd0: readdata = selected ? data_word : 16'hffff;
            3'd1: readdata = {8'hff, selected ? error_reg : 8'hff};
            3'd2: readdata = {8'hff, selected ? count : 8'hff};
            3'd3: readdata = {8'hff, selected ? sector : 8'hff};
            3'd4: readdata = {8'hff, selected ? cyl_lo : 8'hff};
            3'd5: readdata = {8'hff, selected ? cyl_hi : 8'hff};
            3'd6: readdata = {8'hff, devhead};
            default: readdata = {8'hff, cur_status};
        endcase
    end

    // ---- command execution ------------------------------------------------------
    task automatic complete;          // command done: ireason CoD|IO, DRDY|DSC, IRQ
        begin state <= IDLE; count <= 8'h03; status <= 8'h50; error_reg <= 0; pending_irq <= 1; end
    endtask
    task automatic check(input [3:0] key, input [7:0] code);
        begin
            state <= IDLE; count <= 8'h03; status <= 8'h51;
            error_reg <= {key, (key == 4'h5) ? 4'h4 : 4'h0};
            sense_key <= {4'b0, key}; asc <= code; pending_irq <= 1;
        end
    endtask
    task automatic send(input [9:0] bytes);    // one data-in block
        begin
            if (bytes == 0) complete();
            else begin
                // Build the reply into the buffer first; BUILD then opens DRQ.
                state <= BUILD; build_ident <= 0; build_n <= 0; build_len <= bytes;
                words_left <= ({1'b0, bytes} + 1'b1) >> 1;
            end
        end
    endtask
    task automatic flush_audio;
        begin
            wp <= 0; rp <= 0; a_cnt <= 0; samp <= 0;
            if (a_req) a_drop <= 1;
        end
    endtask
    task automatic stop_audio;        // as NP2kai: status "completed", position 0
        begin audio_status <= AS_DONE; play_pos <= 0; flush_audio(); end
    endtask
    wire [9:0] clipped = (alloc10[15:10] != 0 || resp_len < alloc10[9:0]) ? resp_len : alloc10[9:0];
    wire [9:0] clipped6 = resp_len < {2'b0, cdb[4]} ? resp_len : {2'b0, cdb[4]};

    always @(posedge clk) begin
        clear_changed <= 0;
        probe_done <= 0;
        conv_go <= 0;
        // Media probe: read blocks 0..3; block 0 holds the PCD magic and track
        // table, or a raw sector's sync pattern.
        if (probe_byte && pblk == 0) begin
            if (sd_buff_addr < 12 && sd_buff_dout != ((sd_buff_addr == 0 || sd_buff_addr == 11) ? 8'h00 : 8'hff)) sync_ok <= 0;
            if (sd_buff_addr < 8 && sd_buff_dout != MAGIC[8 * (7 - sd_buff_addr[2:0]) +: 8]) magic_ok <= 0;
            case (sd_buff_addr)
                8: hdr_n <= sd_buff_dout[6:0];
                9: hdr_first <= sd_buff_dout[6:0];
                12: hdr_leadout[7:0] <= sd_buff_dout;
                13: hdr_leadout[15:8] <= sd_buff_dout;
                14: hdr_leadout[23:16] <= sd_buff_dout;
                15: begin hdr_leadout[31:24] <= sd_buff_dout; bin_mode2 <= sd_buff_dout == 8'd2; end
                19: hdr_mode2 <= sd_buff_dout[7];
                default: ;
            endcase
        end
        if (probe_pending && !probing && state == IDLE && !sd_rd && !sd_ack && !host_req && !a_req) begin
            probing <= 1; sync_ok <= 1; magic_ok <= 1; pblk <= 0; sd_lba <= 0; sd_rd <= 1;
        end else if (probing && sd_rd && sd_ack) sd_rd <= 0;
        else if (probing && !sd_rd && !sd_ack) begin
            if (pblk == 3) begin probing <= 0; probe_pending <= 0; probe_done <= 1; end
            else begin pblk <= pblk + 1'b1; sd_lba <= pblk + 1'b1; sd_rd <= 1; end
        end
        // ---- CD audio: fetch, FIFO, 44.1 kHz output ----------------------------
        tick_acc <= tick ? tick_next - CLK_HZ : tick_next;
        if (audio_active && !a_req && !host_req && !sd_rd && !sd_ack && !probing && !probe_pending &&
            state != FETCH && fetch_blk <= fetch_last && level < 12'd1900) begin
            sd_lba <= {10'b0, fetch_blk}; sd_rd <= 1; a_req <= 1;
        end else if (a_req && sd_rd && sd_ack) sd_rd <= 0;
        else if (a_req && !sd_rd && !sd_ack) begin
            a_req <= 0; a_drop <= 0;
            if (!a_drop) begin fetch_blk <= fetch_blk + 1'b1; a_skip <= 0; end
        end
        if (a_byte) begin
            a_cnt <= a_cnt + 1'b1; a_word <= {sd_buff_dout, a_word[23:8]};
            if (a_cnt == 3) wp <= wp + 1'b1;
        end
        if (tick) begin
            if (audio_status == AS_PLAY && level != 0 && (level > 1 || !a_we_d)) begin
                audio_l <= afifo_q[15:0]; audio_r <= afifo_q[31:16]; rp <= rp + 1'b1;
                if (samp == 587) begin
                    samp <= 0; play_pos <= play_pos + 1'b1;
                    if (play_pos + 1'b1 >= play_end) begin audio_status <= AS_DONE; flush_audio(); end
                end else samp <= samp + 1'b1;
            end else if (audio_status != AS_PLAY) begin audio_l <= 0; audio_r <= 0; end
        end
        if (reset) begin
            state <= IDLE; status <= 0; error_reg <= 1; ctrl <= 0; pending_irq <= 0;
            features <= 0; devhead <= 0; bcd_mode <= 0; sd_rd <= 0; host_req <= 0;
            probing <= 0; cdb_words <= 0;
            count <= 1; sector <= 1; cyl_lo <= 8'h14; cyl_hi <= 8'heb; sense_key <= 0; asc <= 0;
            audio_status <= AS_NONE; play_pos <= 0; flush_audio();
            if (a_req) sd_rd <= 0;
        end else begin
            // Reading status acknowledges the interrupt; alt status does not.
            if (reg_read && reg_index == 3'd7 && !read_alt) pending_irq <= 0;
            if (ctrl_write) begin
                ctrl <= ctrl_data;
                if (ctrl_data[2]) begin
                    state <= IDLE; status <= 0; error_reg <= 0; pending_irq <= 0;
                    if (host_req) begin sd_rd <= 0; host_req <= 0; end
                end else if (ctrl[2]) begin
                    count <= 1; sector <= 1; cyl_lo <= 8'h14; cyl_hi <= 8'heb; devhead <= 0;
                    status <= 8'h51; error_reg <= 8'h01;
                end
            end
            // ---- data port ------------------------------------------------
            if (selected && reg_index == 3'd0 && word_access) begin
                if (reg_write && state == PACKET) begin
                    cdb[{cdb_words, 1'b0}] <= writedata[7:0];
                    cdb[{cdb_words, 1'b1}] <= writedata[15:8];
                    cdb_words <= cdb_words + 1'b1;
                    if (cdb_words == 5) begin state <= IDLE; status <= 8'h50; end  // dispatched below
                end
                if (reg_write && state == DATA_OUT) begin
                    words_left <= words_left - 1'b1;
                    if (words_left == 1) complete();
                end
                if (reg_read && state == DATA_IN) begin
                    rd_word <= rd_word + 1'b1;
                    words_left <= words_left - 1'b1;
                    if (words_left == 1) complete();
                end
                if (reg_read && state == SECTOR_IN) begin
                    rd_word <= rd_word + 1'b1;
                    words_left <= words_left - 1'b1;
                    if (words_left == 1) begin
                        if (read_left == 0) complete();
                        else begin state <= FETCH; blk <= 0; host_req <= 0; end
                    end
                end
            end
            // ---- task file writes (not while busy) ------------------------------
            if (reg_write && !busy && reg_index != 3'd0) case (reg_index)
                3'd1: features <= writedata[7:0];
                3'd2: count <= writedata[7:0];
                3'd3: sector <= writedata[7:0];
                3'd4: cyl_lo <= writedata[7:0];
                3'd5: cyl_hi <= writedata[7:0];
                3'd6: devhead <= writedata[7:0];
                3'd7: if (selected && state == IDLE) begin
                    pending_irq <= 0; error_reg <= 0;
                    case (writedata[7:0])
                        8'ha0: begin state <= PACKET; cdb_words <= 0; count <= 8'h01; status <= 8'h58; end
                        8'ha1: begin state <= BUILD; build_ident <= 1; build_n <= 0; build_len <= 256; words_left <= 256; end
                        8'h08: begin count <= 1; sector <= 1; cyl_lo <= 8'h14; cyl_hi <= 8'heb;
                                     status <= 0; error_reg <= 8'h81; pending_irq <= 1; end
                        8'h90: begin count <= 1; sector <= 1; cyl_lo <= 8'h14; cyl_hi <= 8'heb;
                                     status <= 0; error_reg <= 8'h81; end
                        8'hde, 8'hdf, 8'he0, 8'he1, 8'he5, 8'h00: begin status <= 8'h50; pending_irq <= 1; end
                        8'hec: begin count <= 1; sector <= 1; cyl_lo <= 8'h14; cyl_hi <= 8'heb;
                                     status <= 8'h41; error_reg <= 8'h04; pending_irq <= 1; end
                        default: begin status <= 8'h41; error_reg <= 8'h04; pending_irq <= 1; end
                    endcase
                end
                default: ;
            endcase
            // ---- packet dispatch (one cycle after the 12th byte) -----------------
            if (state == IDLE && cdb_words == 6) begin
                cdb_words <= 0;
                case (op)
                    8'h00: if (!media) check(2, 8'h3a);
                           else if (changed) begin clear_changed <= 1; check(bcd_mode ? 4'h2 : 4'h6, 8'h28); end
                           else complete();
                    8'h03: begin send(clipped6); end
                    8'h12: send(clipped6);
                    8'h1b: if (cdb[4][1]) check(5, 8'h24);
                           else if (!media) check(2, 8'h3a);
                           else begin stop_audio(); complete(); end
                    8'h1e: complete();
                    8'h2b, 8'h4e: if (!media) check(2, 8'h3a); else begin stop_audio(); complete(); end
                    8'h45: if (!media) check(2, 8'h3a);
                           else begin
                               p_start <= {1'b0, cdb[3][3:0], cdb[4], cdb[5]};
                               p_end <= {1'b0, cdb[3][3:0], cdb[4], cdb[5]} + {5'b0, cdb[7], cdb[8]};
                               state <= PLAYSET; ps <= 2; if (audio_active) audio_status <= AS_DONE;
                           end
                    8'h47: if (!media) check(2, 8'h3a);
                           else begin state <= PLAYSET; ps <= 0; if (audio_active) audio_status <= AS_DONE; end
                    8'h4b: if (!media) check(2, 8'h3a);
                           else begin
                               if (cdb[8][0] && audio_status == AS_PAUSE) audio_status <= AS_PLAY;
                               if (!cdb[8][0] && audio_status == AS_PLAY) audio_status <= AS_PAUSE;
                               complete();
                           end
                    8'h25: if (!media) check(2, 8'h3a); else send(8);
                    8'h28: if (!media) check(2, 8'h3a);
                           else if ({cdb[7], cdb[8]} == 0) complete();
                           else if ({cdb[2], cdb[3][7:4]} != 0 ||
                                    {1'b0, cdb[3][3:0], cdb[4], cdb[5]} + {5'b0, cdb[7], cdb[8]} > {1'b0, total}) check(5, 8'h21);
                           else begin
                               stop_audio();
                               read_lba <= {cdb[3][3:0], cdb[4], cdb[5]};
                               read_left <= {cdb[7], cdb[8]};
                               state <= FETCH; blk <= 0; host_req <= 0;
                           end
                    8'h42: if (!media) check(2, 8'h3a);
                           else if (cdb[2][6] && cdb[3] != 1) check(5, 8'h24);
                           else begin state <= SUBQ; sq <= 0; end
                    8'h43: if (!media) check(2, 8'h3a);
                           else if (toc_fmt > 1 || (toc_fmt == 0 && toc_bad_start)) check(5, 8'h24);
                           else send(clipped);
                    8'h55: if (alloc10 == 0) complete();
                           else begin
                               state <= DATA_OUT; words_left <= (alloc10 + 1) >> 1;
                               {cyl_hi, cyl_lo} <= alloc10; count <= 8'h00; status <= 8'h58; pending_irq <= 1;
                           end
                    8'h5a: if (cdb[2][7:6] == 2'b11) check(5, 8'h39);
                           else if (page_len(page) == 0) check(5, 8'h24);
                           else begin
                               if (page == 6'h0f || page == 6'h3f) bcd_mode <= 1;
                               send(clipped);
                           end
                    default: check(5, 8'h20);
                endcase
                // REQUEST SENSE reports the latched sense, then clears it.
                if (op == 8'h03) begin resp_key <= sense_key; resp_asc <= asc; sense_key <= 0; asc <= 0; end
            end
            // ---- PLAY AUDIO setup -------------------------------------------------
            if (state == PLAYSET) case (ps)
                3'd0: begin p_start <= msf_lba; ps <= 1; end
                3'd1: begin p_end <= msf_lba; ps <= 2; end
                3'd2: if (!a_req) begin
                    flush_audio();
                    if (p_end_c <= p_start) begin audio_status <= AS_DONE; complete(); end
                    else begin p_end <= p_end_c; read_lba <= p_start[19:0]; ps <= 3; end
                end
                3'd3: begin fetch_blk <= sector_base[30:9]; a_skip <= sector_base[8:0]; read_lba <= p_end[19:0]; ps <= 4; end
                default: begin
                    fetch_last <= sector_base_m1[30:9];
                    play_pos <= p_start[19:0]; play_end <= p_end[19:0]; samp <= 0;
                    audio_status <= AS_PLAY; complete();
                end
            endcase
            // ---- READ SUB-CHANNEL: find the track, convert the position -----------
            if (state == SUBQ) case (sq)
                3'd0: begin srch_i <= 0; sq_trk <= 0; sq_ctrl <= 8'h14; sq_start <= 0; sq <= 1; end
                3'd1: sq <= 2;           // trk_q follows srch_i one clock later
                3'd2: begin
                    if (trk_lba <= play_pos) begin sq_trk <= srch_i; sq_ctrl <= trk_ctrl; sq_start <= trk_lba; end
                    if (trk_lba <= play_pos && srch_i + 1'b1 < trk_n) begin srch_i <= srch_i + 1'b1; sq <= 1; end
                    else sq <= 3;
                end
                3'd3: if (!msf_busy) begin conv_go <= 1; conv_val <= {12'b0, play_pos} + 32'd150; conv_to <= 1; sq <= 4; end
                3'd4: sq <= 5;
                3'd5: if (!msf_busy) begin conv_go <= 1; conv_val <= {12'b0, play_pos - sq_start}; conv_to <= 2; sq <= 6; end
                3'd6: sq <= 7;
                default: if (!msf_busy) send(clipped);
            endcase
            // ---- reply builder ---------------------------------------------------
            if (state == BUILD) begin
                if (build_n + 1'b1 < build_len) build_n <= build_n + 1'b1;
                else begin
                    rd_word <= 0;
                    if (build_ident) begin state <= DATA_IN; status <= 8'h58; pending_irq <= 1; end
                    else begin
                        state <= DATA_IN; {cyl_hi, cyl_lo} <= {6'b0, build_len};
                        count <= 8'h02; status <= 8'h58; pending_irq <= 1;
                    end
                end
            end
            // ---- sector fetch: host blocks -> buffer ------------------------------
            if (state == FETCH) begin
                if (blk == 0 && !host_req && !sd_rd && !sd_ack && !a_req) begin
                    first_block <= sector_byte[30:9];
                    start_off <= sector_byte[8:0];
                    blocks <= sector_byte[8:0] == 0 ? 3'd4 : 3'd5;
                    sd_lba <= {10'b0, sector_byte[30:9]};
                    sd_rd <= 1; host_req <= 1;
                end else if (host_req && sd_rd && sd_ack) sd_rd <= 0;
                else if (host_req && !sd_rd && !sd_ack) begin
                    if (blk + 1'b1 == blocks) begin
                        host_req <= 0;
                        state <= SECTOR_IN; rd_word <= {3'b0, start_off[8:1]}; words_left <= 1024;
                        read_lba <= read_lba + 1'b1; read_left <= read_left - 1'b1;
                        {cyl_hi, cyl_lo} <= 16'h0800; count <= 8'h02; status <= 8'h58; pending_irq <= 1;
                    end else begin
                        blk <= blk + 1'b1; sd_lba <= {10'b0, first_block + blk + 1'b1}; sd_rd <= 1;
                    end
                end
            end
        end
        // A mount can arrive while the IDE channel is held in reset (MGL
        // launchers mount during the boot-ROM load), so it is not gated by it.
        if (image_mounted) begin
            if (state == FETCH || state == SECTOR_IN) begin state <= IDLE; host_req <= 0; end
            probe_pending <= image_size != 0; probing <= 0; sd_rd <= 0;
            audio_status <= AS_NONE; play_pos <= 0; flush_audio();
        end
    end
endmodule
