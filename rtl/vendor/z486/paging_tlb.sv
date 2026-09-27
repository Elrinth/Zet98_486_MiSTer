// TLB (Translation Lookaside Buffer) for 80386 Paging Unit 32-entry 4-way set-associative cache with PLRU replacement per set 8 sets × 4...
// Details: doc/z486/implementation_notes.md#src-24-z486-paging-tlb-sv-1
`timescale 1ns/1ns
`include "z486_platform.svh"

module paging_tlb
    import z486_pkg::*, z486_cache_map_pkg::*;
#(
    // VGA/device page window stored in each entry (upstream: A0000-BFFFF).
    parameter [31:0] VGA_BASE = 32'h000a_0000,
    parameter [31:0] VGA_TOP  = 32'h000b_ffff
)(
    input               clk,
    input               reset_n,

    // Registered lookup interface (combinational output)
    // Refused for one cycle after a writer touches the set it reads (reg_rd_stale).
    input        [31:0] linear_addr,
    // linear_addr's value on the next edge; the array read is clocked one cycle early.
    input        [31:0] lookup_addr_next,
    output reg          hit,
    output reg   [31:0] physical_addr,
    output reg          writable,       // Combined PDE & PTE R/W
    output reg          user,           // Combined PDE & PTE U/S
    output reg          dirty,          // D bit from PTE
    output              is_vga_mem,     // Physical address is in A0000-BFFFF

    // Live demand lookup interface. This keeps the idle demand fast path off
    // the registered-address mux used by prefetch/walker lookups.
    input        [31:0] linear_addr_live,
    // linear_addr_live's value on the next edge; the live token refuses it on a miss.
    input        [31:0] live_preread_addr,
    output reg          live_hit,
    output reg   [31:0] live_physical_addr,
    output reg          live_writable,
    output reg          live_user,
    output reg          live_dirty,
    output              live_is_vga_mem,

    // Side-effect-free D2 preread for hardwired loads. The direct-mapped
    // sidecar is a second TLB lookup port; an EX miss simply falls back to the
    // authoritative four-way TLB and page walker.
    input               vipt_preread,
    input        [31:0] vipt_linear_addr,
    output reg          vipt_hit,
    output reg   [31:0] vipt_physical_addr,
    output reg          vipt_writable,
    output reg          vipt_user,
    output reg          vipt_dirty,
    output              vipt_is_vga_mem,

    // Refill the direct sidecar after a registered demand falls back to an
    // authoritative four-way TLB hit.  This path is intentionally separate
    // from the D2 preread: it cannot feed translation back into D2.
    input               vipt_refill_valid,
    input        [31:0] vipt_refill_linear,
    input        [19:0] vipt_refill_pfn,
    input               vipt_refill_writable,
    input               vipt_refill_user,
    input               vipt_refill_dirty,

    // Update interface (from page walker)
    input               update_valid,
    input        [19:0] update_vpn,     // Virtual page number
    input        [19:0] update_pfn,     // Physical frame number
    input               update_writable,
    input               update_user,
    input               update_dirty,

    // Invalidate all entries (on CR3 write)
    input               invalidate_all,

    // Invalidate every cached translation for one linear page (INVLPG).
    input               invalidate_page,
    input        [19:0] invalidate_vpn
);

// 8 sets × 4 ways; each way is a 40-bit {tag, pfn, writable, user, dirty} word.
// Per-way arrays let an insert write only its victim way, so no read-modify-
// write of the set word is needed.
`Z486_BLOCK_RAM reg [39:0] tlb_way0      [7:0];
`Z486_BLOCK_RAM reg [39:0] tlb_way1      [7:0];
`Z486_BLOCK_RAM reg [39:0] tlb_way2      [7:0];
`Z486_BLOCK_RAM reg [39:0] tlb_way3      [7:0];
`Z486_BLOCK_RAM reg [39:0] tlb_way_live0 [7:0];
`Z486_BLOCK_RAM reg [39:0] tlb_way_live1 [7:0];
`Z486_BLOCK_RAM reg [39:0] tlb_way_live2 [7:0];
`Z486_BLOCK_RAM reg [39:0] tlb_way_live3 [7:0];
reg [39:0] tlb_way_q0, tlb_way_q1, tlb_way_q2, tlb_way_q3;
reg [39:0] tlb_way_live_q0, tlb_way_live_q1, tlb_way_live_q2, tlb_way_live_q3;
// Rebuild the old 160-bit set word for the consumers below.
wire [159:0] tlb_word_q      = {tlb_way_q3, tlb_way_q2, tlb_way_q1, tlb_way_q0};
wire [159:0] tlb_word_live_q = {tlb_way_live_q3, tlb_way_live_q2,
                                tlb_way_live_q1, tlb_way_live_q0};
reg [3:0]   tlb_valid [7:0];
wire [2:0]  tlb_rd_set      = lookup_addr_next[14:12];
wire [2:0]  tlb_rd_set_live = live_preread_addr[14:12];
reg  [19:0] live_preread_vpn_r;
reg         live_hazard_r;
// A clocked read cannot answer in the cycle its address appears, so the live port
// answers only when the preread predicted this address and no write intervened.
wire        live_preread_ok = (live_preread_vpn_r == linear_addr_live[31:12]) &&
                              !live_hazard_r;

// The registered port is refused for one cycle after a writer touched the set it
// read, where the stale word would combine with the post-insert valid bit.
reg  [2:0]  tlb_rd_set_d;
reg  [2:0]  update_set_d;
reg         update_valid_d;
wire        reg_rd_stale = update_valid_d && (update_set_d == tlb_rd_set_d);
reg vga_mem [7:0][3:0];

// Way fields of the two clocked read words.
wire [16:0] wq0_tag = tlb_word_q[39:23];
wire [16:0] wq1_tag = tlb_word_q[79:63];
wire [16:0] wq2_tag = tlb_word_q[119:103];
wire [16:0] wq3_tag = tlb_word_q[159:143];
wire [19:0] wq0_pfn = tlb_word_q[22:3];
wire [19:0] wq1_pfn = tlb_word_q[62:43];
wire [19:0] wq2_pfn = tlb_word_q[102:83];
wire [19:0] wq3_pfn = tlb_word_q[142:123];
wire [16:0] lw0_tag = tlb_word_live_q[39:23];
wire [16:0] lw1_tag = tlb_word_live_q[79:63];
wire [16:0] lw2_tag = tlb_word_live_q[119:103];
wire [16:0] lw3_tag = tlb_word_live_q[159:143];
wire [19:0] lw0_pfn = tlb_word_live_q[22:3];
wire [19:0] lw1_pfn = tlb_word_live_q[62:43];
wire [19:0] lw2_pfn = tlb_word_live_q[102:83];
wire [19:0] lw3_pfn = tlb_word_live_q[142:123];

always_ff @(posedge clk) begin
    tlb_way_q0 <= tlb_way0[tlb_rd_set];
    tlb_way_q1 <= tlb_way1[tlb_rd_set];
    tlb_way_q2 <= tlb_way2[tlb_rd_set];
    tlb_way_q3 <= tlb_way3[tlb_rd_set];
    tlb_way_live_q0 <= tlb_way_live0[tlb_rd_set_live];
    tlb_way_live_q1 <= tlb_way_live1[tlb_rd_set_live];
    tlb_way_live_q2 <= tlb_way_live2[tlb_rd_set_live];
    tlb_way_live_q3 <= tlb_way_live3[tlb_rd_set_live];
    live_preread_vpn_r <= live_preread_addr[31:12];
    tlb_rd_set_d    <= tlb_rd_set;
    update_set_d    <= update_vpn[2:0];
    update_valid_d  <= update_valid;
end

// The inferred memory reads OLD_DATA on a same-set write, and so does a reg
// array read in an always_ff: any writer active this cycle makes the live
// preread stale, so the token refuses it. The writers are this array's own
// three (a walker insert, CR3, INVLPG) -- the sidecar's vipt_hazard_r idiom.
always_ff @(posedge clk)
    live_hazard_r <= invalidate_all || invalidate_page || update_valid;

// PLRU bits per set: 3 bits each for 4-way replacement [B0] B0: 0=left subtree, 1=right subtree / \ [B1] [B2] B1: 0=way0, 1=way1 / \ / \...
// Details: doc/z486/implementation_notes.md#src-24-z486-paging-tlb-sv-50
reg [2:0] plru [7:0];

localparam bit TRACE_PAGING_EN = 1'b0;

// Registered lookup address decomposition
wire [19:0] lookup_vpn = linear_addr[31:12];
wire [2:0]  lookup_set = lookup_vpn[2:0];       // Set index: VPN[2:0]
wire [16:0] lookup_tag = lookup_vpn[19:3];       // Tag: VPN[19:3]

// Hit detection - combinational, parallel comparison within selected set
wire hit0 = !reg_rd_stale && tlb_valid[lookup_set][0] && (wq0_tag == lookup_tag);
wire hit1 = !reg_rd_stale && tlb_valid[lookup_set][1] && (wq1_tag == lookup_tag);
wire hit2 = !reg_rd_stale && tlb_valid[lookup_set][2] && (wq2_tag == lookup_tag);
wire hit3 = !reg_rd_stale && tlb_valid[lookup_set][3] && (wq3_tag == lookup_tag);

// Compute device classification per way, in parallel with hit detection. This
// avoids putting the selected-PFN mux on cache request routing controls.
assign is_vga_mem = (hit0 && vga_mem[lookup_set][0]) ||
                    (hit1 && vga_mem[lookup_set][1]) ||
                    (hit2 && vga_mem[lookup_set][2]) ||
                    (hit3 && vga_mem[lookup_set][3]);

// Encode hit into 2-bit way index
wire [1:0] hit_way = hit0 ? 2'd0 :
                     hit1 ? 2'd1 :
                     hit2 ? 2'd2 :
                     hit3 ? 2'd3 : 2'd0;

// One-hot, priority-exact way selects (equivalent to the old hit_way case mux).
wire sel0 = hit0;
wire sel1 = hit1 & ~hit0;
wire sel2 = hit2 & ~(hit0 | hit1);
wire sel3 = hit3 & ~(hit0 | hit1 | hit2);

// Live demand lookup address decomposition. linear_addr_live (z486 paging_live_linear) is a very high-fanout net: its set bits drive the...
// Details: doc/z486/implementation_notes.md#src-24-z486-paging-tlb-sv-77
`Z486_KEEP wire [31:0] lal_w0 = linear_addr_live;
`Z486_KEEP wire [31:0] lal_w1 = linear_addr_live;
`Z486_KEEP wire [31:0] lal_w2 = linear_addr_live;
`Z486_KEEP wire [31:0] lal_w3 = linear_addr_live;

wire [2:0] live_set0 = lal_w0[14:12];  wire [16:0] live_tag0 = lal_w0[31:15];
wire [2:0] live_set1 = lal_w1[14:12];  wire [16:0] live_tag1 = lal_w1[31:15];
wire [2:0] live_set2 = lal_w2[14:12];  wire [16:0] live_tag2 = lal_w2[31:15];
wire [2:0] live_set3 = lal_w3[14:12];  wire [16:0] live_tag3 = lal_w3[31:15];

wire live_hit0 = live_preread_ok && tlb_valid[live_set0][0] &&
                 (lw0_tag == live_tag0);
wire live_hit1 = live_preread_ok && tlb_valid[live_set1][1] &&
                 (lw1_tag == live_tag1);
wire live_hit2 = live_preread_ok && tlb_valid[live_set2][2] &&
                 (lw2_tag == live_tag2);
wire live_hit3 = live_preread_ok && tlb_valid[live_set3][3] &&
                 (lw3_tag == live_tag3);

assign live_is_vga_mem =
    (live_hit0 && vga_mem[live_set0][0]) ||
    (live_hit1 && vga_mem[live_set1][1]) ||
    (live_hit2 && vga_mem[live_set2][2]) ||
    (live_hit3 && vga_mem[live_set3][3]);

// The D2 port uses one synchronous RAM read followed by an EX tag compare.
// It is maintained as an independent TLB: retaining a translation after the
// four-way TLB replaces it is valid until software executes INVLPG or reloads
// CR3, just as retaining it in any other TLB entry would be.
localparam integer VIPT_TLB_INDEX_BITS = 5;
localparam integer VIPT_TLB_ENTRIES = 1 << VIPT_TLB_INDEX_BITS;
wire [VIPT_TLB_INDEX_BITS-1:0] vipt_preread_index =
    vipt_linear_addr[16:12];
wire [VIPT_TLB_INDEX_BITS-1:0] vipt_refill_index =
    vipt_refill_linear[16:12];
wire vipt_refill_write = vipt_refill_valid && !update_valid;
reg [31:0] vipt_linear_r;
reg        vipt_hazard_r;
reg [VIPT_TLB_ENTRIES-1:0] vipt_valid;
// {VPN tag[19:5], PFN[19:0], writable, user, dirty, VGA}
`Z486_BLOCK_RAM_NO_RW_CHECK reg [38:0] vipt_tlb [0:VIPT_TLB_ENTRIES-1];
reg [38:0] vipt_tlb_q;

always_ff @(posedge clk) begin
    if (vipt_preread) begin
        vipt_linear_r <= vipt_linear_addr;
        // Any simultaneous mutation conservatively poisons this preread. TLB
        // mutations are rare, and a false collision only takes the normal
        // authoritative lookup; avoiding the live index compares keeps D2 EA
        // formation out of this register input.
        vipt_hazard_r <= invalidate_all || invalidate_page || update_valid ||
                         vipt_refill_write;
        vipt_tlb_q <= vipt_tlb[vipt_preread_index];
    end
end

wire vipt_match = vipt_valid[vipt_linear_r[16:12]] && !vipt_hazard_r &&
                  (vipt_tlb_q[38:24] == vipt_linear_r[31:17]);
assign vipt_is_vga_mem = vipt_match && vipt_tlb_q[0];

always_comb begin
    vipt_hit = vipt_match;
    vipt_physical_addr = {vipt_tlb_q[23:4], vipt_linear_r[11:0]};
    vipt_writable = vipt_tlb_q[3];
    vipt_user = vipt_tlb_q[2];
    vipt_dirty = vipt_tlb_q[1];
    if (!vipt_match) begin
        vipt_physical_addr = vipt_linear_r;
        vipt_writable = 1'b0;
        vipt_user = 1'b0;
        vipt_dirty = 1'b0;
    end
end

always_ff @(posedge clk) begin
    if (update_valid)
        vipt_tlb[update_vpn[4:0]] <= {update_vpn[19:5], update_pfn,
                                      update_writable, update_user,
                                      update_dirty,
                                      z486_page_in_window(update_pfn, VGA_BASE, VGA_TOP)};
    else if (vipt_refill_write)
        vipt_tlb[vipt_refill_index] <= {vipt_refill_linear[31:17],
                                        vipt_refill_pfn,
                                        vipt_refill_writable,
                                        vipt_refill_user,
                                        vipt_refill_dirty,
                                        z486_page_in_window(vipt_refill_pfn, VGA_BASE, VGA_TOP)};
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n)
        vipt_valid <= '0;
    else if (invalidate_all)
        vipt_valid <= '0;
    else if (invalidate_page)
        vipt_valid[invalidate_vpn[4:0]] <= 1'b0;
    else if (update_valid)
        vipt_valid[update_vpn[4:0]] <= 1'b1;
    else if (vipt_refill_write)
        vipt_valid[vipt_refill_index] <= 1'b1;
end

// Output signals - combinational
always_comb begin
    hit = hit0 | hit1 | hit2 | hit3;

    // Select physical address from matching entry
    physical_addr = {
        ({20{sel0}} & wq0_pfn) |
        ({20{sel1}} & wq1_pfn) |
        ({20{sel2}} & wq2_pfn) |
        ({20{sel3}} & wq3_pfn),
        linear_addr[11:0]
    };
    writable = (sel0 & tlb_word_q[2]) |
               (sel1 & tlb_word_q[42]) |
               (sel2 & tlb_word_q[82]) |
               (sel3 & tlb_word_q[122]);
    user = (sel0 & tlb_word_q[1]) |
           (sel1 & tlb_word_q[41]) |
           (sel2 & tlb_word_q[81]) |
           (sel3 & tlb_word_q[121]);
    dirty = (sel0 & tlb_word_q[0]) |
            (sel1 & tlb_word_q[40]) |
            (sel2 & tlb_word_q[80]) |
            (sel3 & tlb_word_q[120]);

    // If no hit, output linear address (will be overridden by page walker result)
    if (!hit) begin
        physical_addr = linear_addr;
        writable = 1'b1;
        user = 1'b0;
        dirty = 1'b0;
    end
end

// synthesis translate_off
// Shadow of the old flop array, so the fuse can compute the OLD combinational read.
tlb_entry_t tlb_ref [7:0][3:0];
reg         write_en_d;            // an array write committed on the last edge
reg  [31:0] lookup_addr_next_d;
reg         rst_n_d;
always_ff @(posedge clk) begin
    write_en_d <= invalidate_all || invalidate_page || update_valid;
    lookup_addr_next_d <= lookup_addr_next;
    rst_n_d <= reset_n;
end

// Fuses: the clocked port must equal the OLD combinational read (RD_ALIGN,
// RD_STORE outside the read-during-write window, LIVE_ALIGN when the token holds).
always @* begin : align_fuse
    logic [31:0] ref_phys, ref_live_phys;
    logic        ref_wr, ref_us, ref_di;
    logic        ref_live_wr, ref_live_us, ref_live_di;
    logic        ref_hit, ref_live_hit;
    logic        ref_vga, ref_live_vga;
    logic [1:0]  ref_hit_way;
    logic        r_h0, r_h1, r_h2, r_h3;
    logic        rl_h0, rl_h1, rl_h2, rl_h3;
    r_h0 = {tlb_ref[lookup_set][0].valid, tlb_ref[lookup_set][0].tag} ==
           {1'b1, lookup_tag};
    r_h1 = {tlb_ref[lookup_set][1].valid, tlb_ref[lookup_set][1].tag} ==
           {1'b1, lookup_tag};
    r_h2 = {tlb_ref[lookup_set][2].valid, tlb_ref[lookup_set][2].tag} ==
           {1'b1, lookup_tag};
    r_h3 = {tlb_ref[lookup_set][3].valid, tlb_ref[lookup_set][3].tag} ==
           {1'b1, lookup_tag};
    ref_hit = r_h0 | r_h1 | r_h2 | r_h3;
    ref_hit_way = r_h0 ? 2'd0 : r_h1 ? 2'd1 : r_h2 ? 2'd2 : 2'd3;
    case (ref_hit_way)
        2'd0: begin
            ref_phys = {tlb_ref[lookup_set][0].pfn, linear_addr[11:0]};
            ref_wr = tlb_ref[lookup_set][0].writable;
            ref_us = tlb_ref[lookup_set][0].user;
            ref_di = tlb_ref[lookup_set][0].dirty;
        end
        2'd1: begin
            ref_phys = {tlb_ref[lookup_set][1].pfn, linear_addr[11:0]};
            ref_wr = tlb_ref[lookup_set][1].writable;
            ref_us = tlb_ref[lookup_set][1].user;
            ref_di = tlb_ref[lookup_set][1].dirty;
        end
        2'd2: begin
            ref_phys = {tlb_ref[lookup_set][2].pfn, linear_addr[11:0]};
            ref_wr = tlb_ref[lookup_set][2].writable;
            ref_us = tlb_ref[lookup_set][2].user;
            ref_di = tlb_ref[lookup_set][2].dirty;
        end
        default: begin
            ref_phys = {tlb_ref[lookup_set][3].pfn, linear_addr[11:0]};
            ref_wr = tlb_ref[lookup_set][3].writable;
            ref_us = tlb_ref[lookup_set][3].user;
            ref_di = tlb_ref[lookup_set][3].dirty;
        end
    endcase
    if (!ref_hit) begin
        ref_phys = linear_addr;
        ref_wr = 1'b1;
        ref_us = 1'b0;
        ref_di = 1'b0;
    end
    // is_vga_mem keeps its own raw-hit OR form (not the priority selects).
    ref_vga = (r_h0 && vga_mem[lookup_set][0]) ||
              (r_h1 && vga_mem[lookup_set][1]) ||
              (r_h2 && vga_mem[lookup_set][2]) ||
              (r_h3 && vga_mem[lookup_set][3]);

    rl_h0 = tlb_ref[live_set0][0].valid &&
            (tlb_ref[live_set0][0].tag == live_tag0);
    rl_h1 = tlb_ref[live_set1][1].valid &&
            (tlb_ref[live_set1][1].tag == live_tag1);
    rl_h2 = tlb_ref[live_set2][2].valid &&
            (tlb_ref[live_set2][2].tag == live_tag2);
    rl_h3 = tlb_ref[live_set3][3].valid &&
            (tlb_ref[live_set3][3].tag == live_tag3);
    ref_live_hit = rl_h0 | rl_h1 | rl_h2 | rl_h3;
    ref_live_phys = {
        ({20{rl_h0}} & tlb_ref[live_set0][0].pfn) |
        ({20{rl_h1}} & tlb_ref[live_set1][1].pfn) |
        ({20{rl_h2}} & tlb_ref[live_set2][2].pfn) |
        ({20{rl_h3}} & tlb_ref[live_set3][3].pfn),
        linear_addr_live[11:0]
    };
    ref_live_wr = !ref_live_hit |
                  (rl_h0 & tlb_ref[live_set0][0].writable) |
                  (rl_h1 & tlb_ref[live_set1][1].writable) |
                  (rl_h2 & tlb_ref[live_set2][2].writable) |
                  (rl_h3 & tlb_ref[live_set3][3].writable);
    ref_live_us = (rl_h0 & tlb_ref[live_set0][0].user) |
                  (rl_h1 & tlb_ref[live_set1][1].user) |
                  (rl_h2 & tlb_ref[live_set2][2].user) |
                  (rl_h3 & tlb_ref[live_set3][3].user);
    ref_live_di = (rl_h0 & tlb_ref[live_set0][0].dirty) |
                  (rl_h1 & tlb_ref[live_set1][1].dirty) |
                  (rl_h2 & tlb_ref[live_set2][2].dirty) |
                  (rl_h3 & tlb_ref[live_set3][3].dirty);
    ref_live_vga = (rl_h0 && vga_mem[live_set0][0]) ||
                   (rl_h1 && vga_mem[live_set1][1]) ||
                   (rl_h2 && vga_mem[live_set2][2]) ||
                   (rl_h3 && vga_mem[live_set3][3]);

    if (reset_n && rst_n_d) begin
        if (lookup_addr_next_d !== linear_addr)
            $fatal(1, "RD_ALIGN FUSE MISMATCH: next_d=%08x reg=%08x",
                   lookup_addr_next_d, linear_addr);
        if (!write_en_d &&
            ((hit !== ref_hit) || (physical_addr !== ref_phys) ||
             (writable !== ref_wr) || (user !== ref_us) ||
             (dirty !== ref_di) || (is_vga_mem !== ref_vga)))
            $fatal(1, "RD_STORE FUSE MISMATCH: la=%08x", linear_addr);
        if (live_preread_ok &&
            ((live_hit !== ref_live_hit) ||
             (live_physical_addr !== ref_live_phys) ||
             (live_writable !== ref_live_wr) ||
             (live_user !== ref_live_us) ||
             (live_dirty !== ref_live_di) ||
             (live_is_vga_mem !== ref_live_vga)))
            $fatal(1, "LIVE_ALIGN FUSE MISMATCH: live=%08x pre=%08x",
                   linear_addr_live, live_preread_addr);
    end
end

// PER_WAY FUSE: every real per-way word must match the tlb_ref shadow, which
// models a victim-way-only write. Catches any cross-way/set corruption.
integer fset, fway;
always @* begin : per_way_fuse
    logic [39:0] ref_word, reg_word, live_word;
    for (fset = 0; fset < 8; fset = fset + 1) begin
        for (fway = 0; fway < 4; fway = fway + 1) begin
            ref_word = {tlb_ref[fset][fway].tag, tlb_ref[fset][fway].pfn,
                        tlb_ref[fset][fway].writable, tlb_ref[fset][fway].user,
                        tlb_ref[fset][fway].dirty};
            case (fway[1:0])
                2'd0: begin reg_word = tlb_way0[fset]; live_word = tlb_way_live0[fset]; end
                2'd1: begin reg_word = tlb_way1[fset]; live_word = tlb_way_live1[fset]; end
                2'd2: begin reg_word = tlb_way2[fset]; live_word = tlb_way_live2[fset]; end
                default: begin reg_word = tlb_way3[fset]; live_word = tlb_way_live3[fset]; end
            endcase
            if (reset_n && rst_n_d) begin
                if (reg_word !== ref_word)
                    $fatal(1, "PER_WAY REG FUSE MISMATCH: set=%0d way=%0d real=%010x ref=%010x",
                           fset, fway, reg_word, ref_word);
                if (live_word !== ref_word)
                    $fatal(1, "PER_WAY LIVE FUSE MISMATCH: set=%0d way=%0d real=%010x ref=%010x",
                           fset, fway, live_word, ref_word);
            end
        end
    end
end
// synthesis translate_on

always_comb begin
    live_hit = live_hit0 | live_hit1 | live_hit2 | live_hit3;
    // Matching translations are unique.  Select each field directly from the
    // one-hot hit vector instead of priority-encoding a way and then muxing;
    // this shortens the live address -> paging/cache finalize cone.
    live_physical_addr = {
        ({20{live_hit0}} & lw0_pfn) |
        ({20{live_hit1}} & lw1_pfn) |
        ({20{live_hit2}} & lw2_pfn) |
        ({20{live_hit3}} & lw3_pfn),
        linear_addr_live[11:0]
    };
    live_writable = !live_hit |
                    (live_hit0 & tlb_word_live_q[2]) |
                    (live_hit1 & tlb_word_live_q[42]) |
                    (live_hit2 & tlb_word_live_q[82]) |
                    (live_hit3 & tlb_word_live_q[122]);
    live_user = (live_hit0 & tlb_word_live_q[1]) |
                (live_hit1 & tlb_word_live_q[41]) |
                (live_hit2 & tlb_word_live_q[81]) |
                (live_hit3 & tlb_word_live_q[121]);
    live_dirty = (live_hit0 & tlb_word_live_q[0]) |
                 (live_hit1 & tlb_word_live_q[40]) |
                 (live_hit2 & tlb_word_live_q[80]) |
                 (live_hit3 & tlb_word_live_q[120]);
end

// Update address decomposition
wire [2:0]  update_set = update_vpn[2:0];
wire [2:0]  update_plru = plru[update_set];

// If the VPN is already present in the set, update that way in place. Blind PLRU allocation creates duplicate entries, and the hit...
// Details: doc/z486/implementation_notes.md#src-24-z486-paging-tlb-sv-187
wire [16:0] update_tag = update_vpn[19:3];
wire [39:0] update_word = {update_tag, update_pfn, update_writable,
                           update_user, update_dirty};
// The registered word is current only when its read was for this set and no
// writer touched it; otherwise skip duplicate detection and let the PLRU pick.
wire update_word_current = (tlb_rd_set_d == update_set) && !reg_rd_stale;
wire match0 = update_word_current && tlb_valid[update_set][0] && (wq0_tag == update_tag);
wire match1 = update_word_current && tlb_valid[update_set][1] && (wq1_tag == update_tag);
wire match2 = update_word_current && tlb_valid[update_set][2] && (wq2_tag == update_tag);
wire match3 = update_word_current && tlb_valid[update_set][3] && (wq3_tag == update_tag);

wire [2:0] invalidate_set = invalidate_vpn[2:0];

// PLRU victim selection for the update set (existing entry wins)
wire [1:0] victim_way = match0 ? 2'd0 :
                        match1 ? 2'd1 :
                        match2 ? 2'd2 :
                        match3 ? 2'd3 :
                        update_plru[0] ? (update_plru[2] ? 2'd3 : 2'd2) :
                                          (update_plru[1] ? 2'd1 : 2'd0);

// TLB update and PLRU management
integer s;
integer w;
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // Invalidate all entries on reset
        for (s = 0; s < 8; s = s + 1) begin
            tlb_valid[s] <= 4'b0;
            plru[s] <= 3'b000;
            // synthesis translate_off
            for (w = 0; w < 4; w = w + 1)
                tlb_ref[s][w].valid <= 1'b0;
            // synthesis translate_on
        end
    end else if (invalidate_all) begin
        // CR3 write - flush entire TLB
        for (s = 0; s < 8; s = s + 1) begin
            tlb_valid[s] <= 4'b0;
            plru[s] <= 3'b000;
            // synthesis translate_off
            for (w = 0; w < 4; w = w + 1)
                tlb_ref[s][w].valid <= 1'b0;
            // synthesis translate_on
        end
    end else if (invalidate_page) begin
        // INVLPG clears the whole set: its tags need the clocked read. Over-
        // invalidation is architecturally transparent - the next access walks.
        tlb_valid[invalidate_set] <= 4'b0;
        // synthesis translate_off
        for (w = 0; w < 4; w = w + 1)
            tlb_ref[invalidate_set][w].valid <= 1'b0;
        // synthesis translate_on
    end else begin
        // Update PLRU on hit (point away from accessed way in the hit set)
        if (hit) begin
            case (hit_way)
                2'd0: begin plru[lookup_set][0] <= 1'b1; plru[lookup_set][1] <= 1'b1; end
                2'd1: begin plru[lookup_set][0] <= 1'b1; plru[lookup_set][1] <= 1'b0; end
                2'd2: begin plru[lookup_set][0] <= 1'b0; plru[lookup_set][2] <= 1'b1; end
                2'd3: begin plru[lookup_set][0] <= 1'b0; plru[lookup_set][2] <= 1'b0; end
            endcase
        end

        // Insert new entry from page walker
        if (update_valid) begin
            // Write only the victim way.
            case (victim_way)
                2'd0: begin
                    tlb_way0[update_set] <= update_word;
                    tlb_way_live0[update_set] <= update_word;
                    tlb_valid[update_set][0] <= 1'b1;
                    vga_mem[update_set][0] <= z486_page_in_window(update_pfn, VGA_BASE, VGA_TOP);
                    plru[update_set][0] <= 1'b1; plru[update_set][1] <= 1'b1;
                end
                2'd1: begin
                    tlb_way1[update_set] <= update_word;
                    tlb_way_live1[update_set] <= update_word;
                    tlb_valid[update_set][1] <= 1'b1;
                    vga_mem[update_set][1] <= z486_page_in_window(update_pfn, VGA_BASE, VGA_TOP);
                    plru[update_set][0] <= 1'b1; plru[update_set][1] <= 1'b0;
                end
                2'd2: begin
                    tlb_way2[update_set] <= update_word;
                    tlb_way_live2[update_set] <= update_word;
                    tlb_valid[update_set][2] <= 1'b1;
                    vga_mem[update_set][2] <= z486_page_in_window(update_pfn, VGA_BASE, VGA_TOP);
                    plru[update_set][0] <= 1'b0; plru[update_set][2] <= 1'b1;
                end
                2'd3: begin
                    tlb_way3[update_set] <= update_word;
                    tlb_way_live3[update_set] <= update_word;
                    tlb_valid[update_set][3] <= 1'b1;
                    vga_mem[update_set][3] <= z486_page_in_window(update_pfn, VGA_BASE, VGA_TOP);
                    plru[update_set][0] <= 1'b0; plru[update_set][2] <= 1'b0;
                end
            endcase

            // synthesis translate_off
            tlb_ref[update_set][victim_way].valid <= 1'b1;
            tlb_ref[update_set][victim_way].tag <= update_tag;
            tlb_ref[update_set][victim_way].pfn <= update_pfn;
            tlb_ref[update_set][victim_way].writable <= update_writable;
            tlb_ref[update_set][victim_way].user <= update_user;
            tlb_ref[update_set][victim_way].dirty <= update_dirty;
            // synthesis translate_on

            // synthesis translate_off
            if (TRACE_PAGING_EN)
                $display("TLB UPDATE: vpn=%05x pfn=%05x writable=%b user=%b set=%0d victim_way=%0d",
                         update_vpn, update_pfn, update_writable, update_user, update_set, victim_way);
            // synthesis translate_on
        end
    end
end

endmodule
