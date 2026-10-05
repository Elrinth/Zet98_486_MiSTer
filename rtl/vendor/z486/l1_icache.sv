// Read-only physically indexed, physically tagged L1 instruction cache. CPU-side contract: * cpu_addr is a physical byte address. * A...
// Details: doc/z486/implementation_notes.md#src-24-z486-l1-icache-sv-1
`include "z486_platform.svh"
module l1_icache #(
    // 8KB icache (128 sets x 4 ways x 16 B); use 8 for 16KB or 9 for 32KB.
    parameter integer SET_BITS = 7
) (
    input         clk,
    input         reset,
    input         invalidate_all,

    // CPU side — physical read request/response.
    input  [31:0] cpu_addr,
    output [127:0] cpu_line,
    input         cpu_valid,
    // NO_ALLOC line fill: the fetch is answered but no line is installed, so an
    // address aliasing RAM under a 27-bit tag cannot occupy a line. 0 = cached.
    input         cpu_no_alloc,
    output        cpu_ready,
    output        cpu_resp_valid,

    // Memory side.
    output [31:0] mem_addr,
    input  [31:0] mem_dout,
    input [127:0] mem_line_dout,
    output  [3:0] mem_be,
    output  [7:0] mem_burstcount,
    input         mem_busy,
    output        mem_valid,
    input         mem_ready,
    input         mem_resp_valid,
    input         mem_line_resp_valid,

    // CPU stores patch matching cached words; external DMA writes only
    // invalidate. Separate addresses keep DMA out of the hit-response cone.
    input  [31:0] patch_addr,
    input  [31:0] patch_data,
    input   [3:0] patch_be,
    input         patch_valid,
    input  [31:0] invalidate_addr,
    input         invalidate_valid,

    input         cache_enable
);

localparam integer WORD_OFFSET_BITS = 2;
localparam integer BYTE_OFFSET_BITS = 2;
localparam integer LINE_OFFSET_BITS = WORD_OFFSET_BITS + BYTE_OFFSET_BITS;
localparam integer NUM_SETS = 1 << SET_BITS;
localparam integer PHYS_ADDR_BITS = `Z486_L1_PHYS_ADDR_BITS; // 27: maximum supported RAM is 128MB
localparam integer TAG_BITS = PHYS_ADDR_BITS - LINE_OFFSET_BITS - SET_BITS;
localparam integer SET_LSB = LINE_OFFSET_BITS;
localparam integer SET_MSB = SET_LSB + SET_BITS - 1;
localparam integer TAG_LSB = SET_MSB + 1;
localparam integer TAG_MSB = PHYS_ADDR_BITS - 1;
localparam integer TAG_RAM_BITS = (TAG_BITS < 16) ? 16 : (TAG_BITS + 1);
localparam integer TAG_VALID_BIT = TAG_BITS;
localparam [SET_BITS-1:0] LAST_SET = SET_BITS'(NUM_SETS - 1);
localparam integer PATCHQ_DEPTH = 3;
localparam integer PATCHQ_IDX_BITS = 2;
localparam [PATCHQ_IDX_BITS-1:0] PATCHQ_LAST_IDX = 2'd2;
localparam integer SET_DW_LSB = SET_LSB - BYTE_OFFSET_BITS;
localparam integer SET_DW_MSB = SET_MSB - BYTE_OFFSET_BITS;
localparam integer TAG_DW_LSB = TAG_LSB - BYTE_OFFSET_BITS;
localparam integer TAG_DW_MSB = TAG_MSB - BYTE_OFFSET_BITS;

wire [TAG_BITS-1:0] cpu_tag = cpu_addr[TAG_MSB:TAG_LSB];
wire [SET_BITS-1:0] cpu_set = cpu_addr[SET_MSB:SET_LSB];
wire [TAG_BITS-1:0] patch_tag = patch_addr[TAG_MSB:TAG_LSB];
wire [SET_BITS-1:0] patch_set = patch_addr[SET_MSB:SET_LSB];
wire [WORD_OFFSET_BITS-1:0] patch_word = patch_addr[LINE_OFFSET_BITS-1:BYTE_OFFSET_BITS];
// The prefetcher consumes whole 16-byte lines.  Unlike demand data accesses,
// an instruction fetch cannot be satisfied by a single uncacheable DWORD
// bypass without corrupting branch targets in the middle of the line.
wire cpu_uncacheable = !cache_enable;

`Z486_BLOCK_RAM reg [TAG_RAM_BITS-1:0] tag_way0 [0:NUM_SETS-1];
`Z486_BLOCK_RAM reg [TAG_RAM_BITS-1:0] tag_way1 [0:NUM_SETS-1];
`Z486_BLOCK_RAM reg [TAG_RAM_BITS-1:0] tag_way2 [0:NUM_SETS-1];
`Z486_BLOCK_RAM reg [TAG_RAM_BITS-1:0] tag_way3 [0:NUM_SETS-1];
`Z486_PLRU_RAM reg [2:0] plru_set [0:NUM_SETS-1];

`Z486_BLOCK_RAM reg [127:0] data_way0 [0:NUM_SETS-1];
`Z486_BLOCK_RAM reg [127:0] data_way1 [0:NUM_SETS-1];
`Z486_BLOCK_RAM reg [127:0] data_way2 [0:NUM_SETS-1];
`Z486_BLOCK_RAM reg [127:0] data_way3 [0:NUM_SETS-1];

// Register each complete tag word as one RAM read.  Keeping the valid bit in
// the otherwise unused tag-RAM bit removes four 256-bit register arrays while
// preserving the existing synchronous CPU lookup boundary.
reg [TAG_RAM_BITS-1:0] rd_tag_entry0_r, rd_tag_entry1_r;
reg [TAG_RAM_BITS-1:0] rd_tag_entry2_r, rd_tag_entry3_r;
reg [TAG_RAM_BITS-1:0] snoop_tag_entry0_r, snoop_tag_entry1_r;
reg [TAG_RAM_BITS-1:0] snoop_tag_entry2_r, snoop_tag_entry3_r;
wire [TAG_BITS-1:0] rd_tag0_r = rd_tag_entry0_r[TAG_BITS-1:0];
wire [TAG_BITS-1:0] rd_tag1_r = rd_tag_entry1_r[TAG_BITS-1:0];
wire [TAG_BITS-1:0] rd_tag2_r = rd_tag_entry2_r[TAG_BITS-1:0];
wire [TAG_BITS-1:0] rd_tag3_r = rd_tag_entry3_r[TAG_BITS-1:0];
wire rd_valid0_r = rd_tag_entry0_r[TAG_VALID_BIT];
wire rd_valid1_r = rd_tag_entry1_r[TAG_VALID_BIT];
wire rd_valid2_r = rd_tag_entry2_r[TAG_VALID_BIT];
wire rd_valid3_r = rd_tag_entry3_r[TAG_VALID_BIT];
reg [127:0] rd_line0_r, rd_line1_r, rd_line2_r, rd_line3_r;
reg [2:0] rd_plru_r;
reg [3:0] rd_invalidated_r;

reg        req_valid_r;
reg [31:0] req_addr_r;
reg        req_no_alloc_r;
reg        req_uncacheable_r;
reg [TAG_BITS-1:0] req_tag_r;
reg [SET_BITS-1:0] req_set_r;

reg        mem_valid_r;
reg [31:0] mem_addr_r;
reg  [7:0] mem_burstcount_r;

assign mem_valid = mem_valid_r;
assign mem_addr = mem_addr_r;
assign mem_be = 4'hF;
assign mem_burstcount = mem_burstcount_r;

localparam [2:0] S_RESET_INIT  = 3'd0;
localparam [2:0] S_IDLE        = 3'd1;
localparam [2:0] S_LOOKUP      = 3'd2;
localparam [2:0] S_FILL        = 3'd3;
localparam [2:0] S_BYPASS_WAIT = 3'd4;

reg [2:0] state;
reg [SET_BITS-1:0] init_set;
reg [TAG_BITS-1:0] snoop_tag_r;
reg [SET_BITS-1:0] snoop_set_r;
reg [WORD_OFFSET_BITS-1:0] snoop_word_r;
reg [29:0] snoop_addr_dw_r;
reg [31:0] snoop_data_r;
reg [3:0] snoop_be_r;
reg snoop_patch_r;
reg snoop_valid_r;
reg [29:0] patchq_addr [0:PATCHQ_DEPTH-1];
reg [31:0] patchq_data [0:PATCHQ_DEPTH-1];
reg  [3:0] patchq_be   [0:PATCHQ_DEPTH-1];
reg        patchq_valid[0:PATCHQ_DEPTH-1];
reg [PATCHQ_IDX_BITS-1:0] patchq_head;
reg [WORD_OFFSET_BITS-1:0] fill_count;
reg [SET_BITS-1:0] fill_set;
reg [TAG_BITS-1:0] fill_tag;
reg [1:0] fill_way;
reg [127:0] fill_line;
reg [2:0] fill_plru_r;
reg fill_requested;

reg [127:0] line_r;
reg resp_valid_r;
reg ready_r;
reg flush_pending;
wire flush_block = invalidate_all || flush_pending;

assign cpu_ready = ready_r && !flush_block;

function automatic [1:0] way_encode(input [3:0] hit_vec);
begin
    way_encode = hit_vec[0] ? 2'd0 :
                 hit_vec[1] ? 2'd1 :
                 hit_vec[2] ? 2'd2 : 2'd3;
end
endfunction

function automatic [127:0] way_line_mux(
    input [1:0] way,
    input [127:0] data0,
    input [127:0] data1,
    input [127:0] data2,
    input [127:0] data3
);
begin
    case (way)
        2'd0: way_line_mux = data0;
        2'd1: way_line_mux = data1;
        2'd2: way_line_mux = data2;
        default: way_line_mux = data3;
    endcase
end
endfunction

// select_word removed: the single-word read path is dead (superseded by the
// 128-bit cpu_line output).

function automatic [127:0] patch_line_word(input [127:0] line, input [1:0] word, input [31:0] data);
begin
    patch_line_word = line;
    patch_line_word[{word, 5'b0} +: 32] = data;
end
endfunction

function automatic [31:0] be_mask(input [3:0] be);
begin
    be_mask = {{8{be[3]}}, {8{be[2]}}, {8{be[1]}}, {8{be[0]}}};
end
endfunction

function automatic [31:0] merge32(input [31:0] old_data, input [31:0] new_data, input [3:0] be);
    automatic reg [31:0] mask;
begin
    mask = be_mask(be);
    merge32 = (old_data & ~mask) | (new_data & mask);
end
endfunction

function automatic [127:0] patch_line_word_be(
    input [127:0] line,
    input [1:0] word,
    input [31:0] data,
    input [3:0] be
);
begin
    patch_line_word_be = line;
    patch_line_word_be[{word, 5'b0} +: 32] =
        merge32(line[{word, 5'b0} +: 32], data, be);
end
endfunction

function automatic [PATCHQ_IDX_BITS-1:0] patchq_next_idx(input [PATCHQ_IDX_BITS-1:0] idx);
begin
    patchq_next_idx = (idx == PATCHQ_LAST_IDX) ? {PATCHQ_IDX_BITS{1'b0}} : (idx + 1'b1);
end
endfunction

function automatic logic line_match_dw(
    input [29:0] addr_dw,
    input [TAG_BITS-1:0] tag,
    input [SET_BITS-1:0] set
);
begin
    line_match_dw = (addr_dw[TAG_DW_MSB:TAG_DW_LSB] == tag) &&
                    (addr_dw[SET_DW_MSB:SET_DW_LSB] == set);
end
endfunction

function automatic logic word_match_dw(
    input [29:0] addr_dw,
    input [TAG_BITS-1:0] tag,
    input [SET_BITS-1:0] set,
    input [WORD_OFFSET_BITS-1:0] word
);
begin
    word_match_dw = line_match_dw(addr_dw, tag, set) &&
                    (addr_dw[WORD_OFFSET_BITS-1:0] == word);
end
endfunction

function automatic [2:0] plru_update(input [2:0] plru, input [1:0] way);
begin
    case (way)
        2'd0: plru_update = {plru[2], 1'b1, 1'b1};
        2'd1: plru_update = {plru[2], 1'b0, 1'b1};
        2'd2: plru_update = {1'b1, plru[1], 1'b0};
        default: plru_update = {1'b0, plru[1], 1'b0};
    endcase
end
endfunction

function automatic [1:0] plru_victim(input [2:0] plru);
begin
    if (!plru[0])
        plru_victim = plru[1] ? 2'd1 : 2'd0;
    else
        plru_victim = plru[2] ? 2'd3 : 2'd2;
end
endfunction

wire [3:0] lookup_hit_vec = {
    rd_valid3_r && !rd_invalidated_r[3] && (rd_tag3_r == req_tag_r),
    rd_valid2_r && !rd_invalidated_r[2] && (rd_tag2_r == req_tag_r),
    rd_valid1_r && !rd_invalidated_r[1] && (rd_tag1_r == req_tag_r),
    rd_valid0_r && !rd_invalidated_r[0] && (rd_tag0_r == req_tag_r)
};
wire lookup_hit = |lookup_hit_vec;
wire [1:0] lookup_way = way_encode(lookup_hit_vec);
wire [127:0] lookup_way_line = way_line_mux(lookup_way, rd_line0_r, rd_line1_r, rd_line2_r, rd_line3_r);
// A CPU store can arrive after the synchronous RAM lookup captured a valid
// line, so reject that live collision. External DMA invalidation is held and
// reaches the registered snoop before the pending DMA write can commit; keeping
// it out of this hit cone avoids a system-to-prefetch timing path.
wire lookup_snoop_conflict =
    (snoop_valid_r && (snoop_tag_r == req_tag_r) && (snoop_set_r == req_set_r)) ||
    (patch_valid && (patch_tag == req_tag_r) && (patch_set == req_set_r));
wire lookup_hit_usable = lookup_hit && !lookup_snoop_conflict && !flush_block;
wire can_accept_cpu = (state == S_IDLE) && !reset && !flush_block;
wire accept_cpu = cpu_valid && ready_r && can_accept_cpu;
wire lookup_read_hit_now = (state == S_LOOKUP) && req_valid_r &&
                           !req_uncacheable_r && !req_no_alloc_r && lookup_hit_usable;
logic [PATCHQ_DEPTH-1:0] patchq_snoop_match;
logic patchq_snoop_hit;
logic [PATCHQ_DEPTH-1:0] patchq_line_match;
logic snoop_patch_line_match;
logic live_patch_line_match;
logic [31:0] fill_word_next;
logic [127:0] fill_line_base;
logic [127:0] fill_line_next;
logic [127:0] wide_line_next;

always_comb begin
    patchq_snoop_match = {PATCHQ_DEPTH{1'b0}};
    for (int p = 0; p < PATCHQ_DEPTH; p++)
        patchq_snoop_match[p] = patchq_valid[p] && patchq_addr[p] == snoop_addr_dw_r;
    patchq_snoop_hit = |patchq_snoop_match;
end

// Each patch's line (tag/set) compare is resolved once and shared by the
// per-word and whole-line merges; the word offset is compared separately.
always_comb begin
    for (int p = 0; p < PATCHQ_DEPTH; p++)
        patchq_line_match[p] = patchq_valid[p] &&
            line_match_dw(patchq_addr[p], fill_tag, fill_set);
    snoop_patch_line_match = snoop_valid_r && snoop_patch_r &&
        line_match_dw(snoop_addr_dw_r, fill_tag, fill_set);
    live_patch_line_match = patch_valid &&
        line_match_dw(patch_addr[31:2], fill_tag, fill_set);
end

always_comb begin
    fill_word_next = mem_dout;
    for (int p = 0; p < PATCHQ_DEPTH; p++) begin
        if (patchq_line_match[p] &&
            (patchq_addr[p][WORD_OFFSET_BITS-1:0] == fill_count))
            fill_word_next = merge32(fill_word_next, patchq_data[p], patchq_be[p]);
    end
    if (snoop_patch_line_match && (snoop_word_r == fill_count))
        fill_word_next = merge32(fill_word_next, snoop_data_r, snoop_be_r);
    if (live_patch_line_match && (patch_word == fill_count))
        fill_word_next = merge32(fill_word_next, patch_data, patch_be);

    fill_line_base = fill_line;
    if (snoop_patch_line_match)
        fill_line_base = patch_line_word_be(fill_line_base, snoop_word_r, snoop_data_r, snoop_be_r);
    if (live_patch_line_match)
        fill_line_base = patch_line_word_be(fill_line_base, patch_word, patch_data, patch_be);
    fill_line_next = patch_line_word(fill_line_base, fill_count, fill_word_next);

    // A native DDR backend returns the complete line in one cycle. Apply the
    // same pending self-modifying-code patches that the legacy DWORD path
    // applies one beat at a time.
    wide_line_next = mem_line_dout;
    for (int p = 0; p < PATCHQ_DEPTH; p++) begin
        if (patchq_line_match[p])
            wide_line_next = patch_line_word_be(wide_line_next,
                patchq_addr[p][WORD_OFFSET_BITS-1:0], patchq_data[p], patchq_be[p]);
    end
    if (snoop_patch_line_match)
        wide_line_next = patch_line_word_be(wide_line_next, snoop_word_r,
                                             snoop_data_r, snoop_be_r);
    if (live_patch_line_match)
        wide_line_next = patch_line_word_be(wide_line_next, patch_word,
                                             patch_data, patch_be);
end

// synthesis translate_off
// Simulation-only guard: the shared patch match must match the per-call model.
always_comb begin
    automatic logic [31:0] ref_word = mem_dout;
    automatic logic [127:0] ref_base = fill_line;
    automatic logic [127:0] ref_word_line;
    automatic logic [127:0] ref_wide = mem_line_dout;
    for (int p = 0; p < PATCHQ_DEPTH; p++) begin
        if (patchq_valid[p] && word_match_dw(patchq_addr[p], fill_tag, fill_set, fill_count))
            ref_word = merge32(ref_word, patchq_data[p], patchq_be[p]);
    end
    if (snoop_valid_r && snoop_patch_r && word_match_dw(snoop_addr_dw_r, fill_tag, fill_set, fill_count))
        ref_word = merge32(ref_word, snoop_data_r, snoop_be_r);
    if (patch_valid && word_match_dw(patch_addr[31:2], fill_tag, fill_set, fill_count))
        ref_word = merge32(ref_word, patch_data, patch_be);

    if (snoop_valid_r && snoop_patch_r && line_match_dw(snoop_addr_dw_r, fill_tag, fill_set))
        ref_base = patch_line_word_be(ref_base, snoop_word_r, snoop_data_r, snoop_be_r);
    if (patch_valid && line_match_dw(patch_addr[31:2], fill_tag, fill_set))
        ref_base = patch_line_word_be(ref_base, patch_word, patch_data, patch_be);
    ref_word_line = patch_line_word(ref_base, fill_count, ref_word);

    for (int p = 0; p < PATCHQ_DEPTH; p++) begin
        if (patchq_valid[p] && line_match_dw(patchq_addr[p], fill_tag, fill_set))
            ref_wide = patch_line_word_be(ref_wide,
                patchq_addr[p][WORD_OFFSET_BITS-1:0], patchq_data[p], patchq_be[p]);
    end
    if (snoop_valid_r && snoop_patch_r &&
        line_match_dw(snoop_addr_dw_r, fill_tag, fill_set))
        ref_wide = patch_line_word_be(ref_wide, snoop_word_r, snoop_data_r, snoop_be_r);
    if (patch_valid && line_match_dw(patch_addr[31:2], fill_tag, fill_set))
        ref_wide = patch_line_word_be(ref_wide, patch_word, patch_data, patch_be);

    if (fill_word_next !== ref_word) $fatal(1, "icache fill word forward mismatch");
    if (fill_line_next !== ref_word_line) $fatal(1, "icache fill line forward mismatch");
    if (wide_line_next !== ref_wide) $fatal(1, "icache wide line forward mismatch");
end
// synthesis translate_on

assign cpu_line = lookup_read_hit_now ? lookup_way_line : line_r;
assign cpu_resp_valid = lookup_read_hit_now || resp_valid_r;

wire tag_reset_write = (state == S_RESET_INIT);
wire tag_fill_write = (state == S_FILL) &&
                      (mem_line_resp_valid ||
                       (mem_resp_valid &&
                        fill_count == {WORD_OFFSET_BITS{1'b1}}));
wire [TAG_RAM_BITS-1:0] tag_fill_entry =
    {{(TAG_RAM_BITS-TAG_BITS-1){1'b0}}, 1'b1, fill_tag};
wire snoop_capture = invalidate_valid || patch_valid;
wire [SET_BITS-1:0] snoop_capture_set = invalidate_valid ?
                                              invalidate_addr[SET_MSB:SET_LSB] :
                                              patch_set;
wire [TAG_BITS-1:0] snoop_capture_tag = invalidate_valid ?
                                              invalidate_addr[TAG_MSB:TAG_LSB] :
                                              patch_tag;
wire live_snoop_fill_conflict = snoop_capture &&
                                (snoop_capture_set == fill_set) &&
                                (snoop_capture_tag == fill_tag);
wire tag_snoop_match0 = snoop_valid_r && snoop_tag_entry0_r[TAG_VALID_BIT] &&
                        (snoop_tag_entry0_r[TAG_BITS-1:0] == snoop_tag_r);
wire tag_snoop_match1 = snoop_valid_r && snoop_tag_entry1_r[TAG_VALID_BIT] &&
                        (snoop_tag_entry1_r[TAG_BITS-1:0] == snoop_tag_r);
wire tag_snoop_match2 = snoop_valid_r && snoop_tag_entry2_r[TAG_VALID_BIT] &&
                        (snoop_tag_entry2_r[TAG_BITS-1:0] == snoop_tag_r);
wire tag_snoop_match3 = snoop_valid_r && snoop_tag_entry3_r[TAG_VALID_BIT] &&
                        (snoop_tag_entry3_r[TAG_BITS-1:0] == snoop_tag_r);
wire registered_snoop_fill_conflict = snoop_valid_r &&
                                      (snoop_set_r == fill_set) &&
                                      (snoop_tag_r == fill_tag);
// Each way has one tag write port. A fill in another set does not replace
// the snooped tag, even when both choose the same way. Give that invalidation
// priority and return the fetched line without installing either tag or data.
// Otherwise a following snoop can overwrite the pending address and leave
// modified code cached under a stale valid tag. Different ways may still
// install a fill and invalidate a line simultaneously.
wire [3:0] tag_snoop_matches = {tag_snoop_match3, tag_snoop_match2,
                              tag_snoop_match1, tag_snoop_match0};
wire fill_snoop_write_conflict = tag_snoop_matches[fill_way];
wire fill_install_allowed = !req_uncacheable_r && !req_no_alloc_r && !flush_block && !live_snoop_fill_conflict &&
                            !registered_snoop_fill_conflict && !fill_snoop_write_conflict;
wire data_fill_write = tag_fill_write && fill_install_allowed;

always_ff @(posedge clk) begin
    if (accept_cpu) begin
        rd_tag_entry0_r <= tag_way0[cpu_set];
        rd_tag_entry1_r <= tag_way1[cpu_set];
        rd_tag_entry2_r <= tag_way2[cpu_set];
        rd_tag_entry3_r <= tag_way3[cpu_set];
        rd_line0_r <= data_way0[cpu_set];
        rd_line1_r <= data_way1[cpu_set];
        rd_line2_r <= data_way2[cpu_set];
        rd_line3_r <= data_way3[cpu_set];
        rd_plru_r <= plru_set[cpu_set];
        // A synchronous tag read may return its old valid bit on the same
        // edge that a snoop clears it. Carry that write collision into LOOKUP;
        // snoop_valid_r may already be clear or describe the next snoop then.
        // Mask only the written ways, preserving hits in independent ways.
        rd_invalidated_r <= (cpu_set == snoop_set_r) ? tag_snoop_matches : 4'b0;
    end

    // Keep each data RAM's synchronous read and write in the same process.
    // Vivado otherwise implements the 4 x 256 x 128-bit instruction cache as
    // flip-flops instead of inferring simple dual-port block RAMs.
    if (data_fill_write) begin
        case (fill_way)
            2'd0: data_way0[fill_set] <= mem_line_resp_valid ?
                                              wide_line_next : fill_line_next;
            2'd1: data_way1[fill_set] <= mem_line_resp_valid ?
                                              wide_line_next : fill_line_next;
            2'd2: data_way2[fill_set] <= mem_line_resp_valid ?
                                              wide_line_next : fill_line_next;
            default: data_way3[fill_set] <= mem_line_resp_valid ?
                                              wide_line_next : fill_line_next;
        endcase
    end

    // The second synchronous tag read is launched from the live snoop input
    // while its address and payload are registered.  Its result is therefore
    // aligned with snoop_valid_r on the following lookup cycle, when the
    // existing conflict mask already prevents a stale CPU hit.
    if (snoop_capture) begin
        snoop_tag_entry0_r <= tag_way0[snoop_capture_set];
        snoop_tag_entry1_r <= tag_way1[snoop_capture_set];
        snoop_tag_entry2_r <= tag_way2[snoop_capture_set];
        snoop_tag_entry3_r <= tag_way3[snoop_capture_set];
    end

    // Keep each tag array in one write process so Quartus can retain the tag
    // memories as M10Ks. An unrelated snoop and fill can update different
    // way RAMs together; a same-way conflict suppresses fill installation.
    if (tag_reset_write) begin
        tag_way0[init_set] <= '0;
        tag_way1[init_set] <= '0;
        tag_way2[init_set] <= '0;
        tag_way3[init_set] <= '0;
    end else begin
        if (tag_fill_write && fill_install_allowed && (fill_way == 2'd0))
            tag_way0[fill_set] <= tag_fill_entry;
        else if (tag_snoop_match0)
            tag_way0[snoop_set_r] <= '0;
        if (tag_fill_write && fill_install_allowed && (fill_way == 2'd1))
            tag_way1[fill_set] <= tag_fill_entry;
        else if (tag_snoop_match1)
            tag_way1[snoop_set_r] <= '0;
        if (tag_fill_write && fill_install_allowed && (fill_way == 2'd2))
            tag_way2[fill_set] <= tag_fill_entry;
        else if (tag_snoop_match2)
            tag_way2[snoop_set_r] <= '0;
        if (tag_fill_write && fill_install_allowed && (fill_way == 2'd3))
            tag_way3[fill_set] <= tag_fill_entry;
        else if (tag_snoop_match3)
            tag_way3[snoop_set_r] <= '0;
    end
end

always_ff @(posedge clk) begin
    if (reset) begin
        state <= S_RESET_INIT;
        init_set <= {SET_BITS{1'b0}};
        req_valid_r <= 1'b0;
        flush_pending <= 1'b0;
        ready_r <= 1'b0;
        resp_valid_r <= 1'b0;
        line_r <= 128'h0;
        mem_valid_r <= 1'b0;
        mem_addr_r <= 32'h0;
        mem_burstcount_r <= 8'h0;
        fill_line <= 128'h0;
        fill_requested <= 1'b0;
        snoop_tag_r <= {TAG_BITS{1'b0}};
        snoop_set_r <= {SET_BITS{1'b0}};
        snoop_word_r <= {WORD_OFFSET_BITS{1'b0}};
        snoop_addr_dw_r <= 30'h0;
        snoop_data_r <= 32'h0;
        snoop_be_r <= 4'h0;
        snoop_patch_r <= 1'b0;
        snoop_valid_r <= 1'b0;
        patchq_head <= {PATCHQ_IDX_BITS{1'b0}};
        for (integer p = 0; p < PATCHQ_DEPTH; p = p + 1)
            patchq_valid[p] <= 1'b0;
    end else begin
        ready_r <= (state == S_IDLE);
        resp_valid_r <= 1'b0;
        snoop_valid_r <= invalidate_valid || patch_valid;
        if (invalidate_valid) begin
            snoop_tag_r <= invalidate_addr[TAG_MSB:TAG_LSB];
            snoop_set_r <= invalidate_addr[SET_MSB:SET_LSB];
            snoop_word_r <= invalidate_addr[LINE_OFFSET_BITS-1:BYTE_OFFSET_BITS];
            snoop_addr_dw_r <= invalidate_addr[31:2];
            snoop_data_r <= 32'h0;
            snoop_be_r <= 4'h0;
            snoop_patch_r <= 1'b0;
        end else if (patch_valid) begin
            snoop_tag_r <= patch_tag;
            snoop_set_r <= patch_set;
            snoop_word_r <= patch_word;
            snoop_addr_dw_r <= patch_addr[31:2];
            snoop_data_r <= patch_data;
            snoop_be_r <= patch_be;
            snoop_patch_r <= 1'b1;
        end

        if (mem_valid_r && mem_ready)
            mem_valid_r <= 1'b0;

        if (snoop_valid_r) begin
            // CPU stores can race ahead of an instruction-cache line fill.
            // Keep the recent data-bearing snoops so a later fill of the same
            // physical line returns self-modified code after a branch flush.
            if (snoop_patch_r) begin
                for (int p = 0; p < PATCHQ_DEPTH; p++) begin
                    if (patchq_snoop_match[p]) begin
                        patchq_data[p] <= merge32(patchq_data[p], snoop_data_r, snoop_be_r);
                        patchq_be[p] <= patchq_be[p] | snoop_be_r;
                    end
                end
                if (!patchq_snoop_hit) begin
                    patchq_valid[patchq_head] <= 1'b1;
                    patchq_addr[patchq_head] <= snoop_addr_dw_r;
                    patchq_data[patchq_head] <= snoop_data_r;
                    patchq_be[patchq_head] <= snoop_be_r;
                    patchq_head <= patchq_next_idx(patchq_head);
                end
            end else begin
                for (int p = 0; p < PATCHQ_DEPTH; p++) begin
                    if (patchq_valid[p] && line_match_dw(patchq_addr[p], snoop_tag_r, snoop_set_r))
                        patchq_valid[p] <= 1'b0;
                end
            end

        end

        if (invalidate_all) flush_pending <= 1'b1;
        case (state)
            S_RESET_INIT: begin
                plru_set[init_set] <= 3'b000;
                if (init_set == LAST_SET && invalidate_all) begin
                    init_set <= 0;
                end else if (init_set == LAST_SET) begin
                    flush_pending <= 1'b0;
                    state <= S_IDLE;
                    ready_r <= 1'b1;
                end else begin
                    init_set <= init_set + 1'b1;
                end
            end

            S_IDLE: begin
                if (flush_pending && !mem_valid_r) begin
                    state <= S_RESET_INIT;
                    init_set <= 0;
                    ready_r <= 0;
                    for (int p = 0; p < PATCHQ_DEPTH; p++) patchq_valid[p] <= 0;
                end
                if (accept_cpu) begin
                    ready_r <= 1'b0;
                    req_valid_r <= 1'b1;
                    req_addr_r <= cpu_addr;
                    req_uncacheable_r <= cpu_uncacheable;
                    req_no_alloc_r <= cpu_no_alloc;
                    req_tag_r <= cpu_tag;
                    req_set_r <= cpu_set;
                    state <= S_LOOKUP;
                end
            end

            S_LOOKUP: begin
                req_valid_r <= 1'b0;

                // Prefetch consumes a whole aligned line even for uncached ROM and
                // no-allocate windows: the fill path returns all four DWORDs but
                // does not install tags (fill_install_allowed).
                if (!req_uncacheable_r && !req_no_alloc_r && lookup_hit_usable) begin
                    plru_set[req_set_r] <= plru_update(rd_plru_r, lookup_way);
                    state <= S_IDLE;
                    ready_r <= 1'b1;
                end else begin
                    fill_set <= req_set_r;
                    fill_tag <= req_tag_r;
                    fill_way <= plru_victim(rd_plru_r);
                    fill_plru_r <= rd_plru_r;
                    fill_count <= {WORD_OFFSET_BITS{1'b0}};
                    fill_line <= 128'h0;
                    fill_requested <= 1'b0;
                    state <= S_FILL;
                end
            end

            S_FILL: begin
                if (!fill_requested && !mem_valid_r && !mem_busy) begin
                    mem_valid_r <= 1'b1;
                    mem_addr_r <= {req_addr_r[31:4], 4'b0000};
                    mem_burstcount_r <= 8'd4;
                    fill_requested <= 1'b1;
                end

                if (mem_line_resp_valid) begin
                    fill_line <= wide_line_next;
                    line_r <= wide_line_next;
                    resp_valid_r <= 1'b1;
                    // No line installed: leave the replacement bits alone.
                    if (fill_install_allowed)
                        plru_set[fill_set] <= plru_update(fill_plru_r, fill_way);
                    state <= S_IDLE;
                    ready_r <= 1'b1;
                end else if (mem_resp_valid) begin
                    fill_line <= fill_line_next;

                    if (fill_count == {WORD_OFFSET_BITS{1'b1}}) begin
                        line_r <= fill_line_next;
                        resp_valid_r <= 1'b1;
                        // Only the tag-RAM fill write sets valid for fill_way.
                        // Do not restore any other way from the fill-start
                        // snapshot: a snoop during this fill must survive.
                        // Details: doc/z486/implementation_notes.md#src-24-z486-l1-icache-sv-491
                        if (fill_install_allowed)
                            plru_set[fill_set] <= plru_update(fill_plru_r, fill_way);
                        state <= S_IDLE;
                        ready_r <= 1'b1;
                    end
                    fill_count <= fill_count + 1'b1;
                end
            end

            S_BYPASS_WAIT: begin
                if (mem_resp_valid) begin
                    line_r <= {4{mem_dout}};
                    resp_valid_r <= 1'b1;
                    state <= S_IDLE;
                    ready_r <= 1'b1;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
