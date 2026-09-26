// TLB (Translation Lookaside Buffer) for 80386 Paging Unit 32-entry 4-way set-associative cache with PLRU replacement per set 8 sets × 4...
// Details: doc/z486/implementation_notes.md#src-24-z486-paging-tlb-sv-1
`timescale 1ns/1ns
`include "z486_platform.svh"

module paging_tlb
    import z486_pkg::*;
(
    input               clk,
    input               reset_n,

    // Registered lookup interface (combinational output)
    input        [31:0] linear_addr,
    output reg          hit,
    output reg   [31:0] physical_addr,
    output reg          writable,       // Combined PDE & PTE R/W
    output reg          user,           // Combined PDE & PTE U/S
    output reg          dirty,          // D bit from PTE
    output              is_vga_mem,     // Physical address is in A0000-BFFFF

    // Live demand lookup interface. This keeps the idle demand fast path off
    // the registered-address mux used by prefetch/walker lookups.
    input        [31:0] linear_addr_live,
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

// 8 sets × 4 ways
tlb_entry_t tlb [7:0][3:0];
reg vga_mem [7:0][3:0];

// PLRU bits per set: 3 bits each for 4-way replacement [B0] B0: 0=left subtree, 1=right subtree / \ [B1] [B2] B1: 0=way0, 1=way1 / \ / \...
// Details: doc/z486/implementation_notes.md#src-24-z486-paging-tlb-sv-50
reg [2:0] plru [7:0];

localparam bit TRACE_PAGING_EN = 1'b0;

// Registered lookup address decomposition
wire [19:0] lookup_vpn = linear_addr[31:12];
wire [2:0]  lookup_set = lookup_vpn[2:0];       // Set index: VPN[2:0]
wire [16:0] lookup_tag = lookup_vpn[19:3];       // Tag: VPN[19:3]

// Hit detection - combinational, parallel comparison within selected set
wire hit0 = tlb[lookup_set][0].valid && (tlb[lookup_set][0].tag == lookup_tag);
wire hit1 = tlb[lookup_set][1].valid && (tlb[lookup_set][1].tag == lookup_tag);
wire hit2 = tlb[lookup_set][2].valid && (tlb[lookup_set][2].tag == lookup_tag);
wire hit3 = tlb[lookup_set][3].valid && (tlb[lookup_set][3].tag == lookup_tag);

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

wire live_hit0 = tlb[live_set0][0].valid && (tlb[live_set0][0].tag == live_tag0);
wire live_hit1 = tlb[live_set1][1].valid && (tlb[live_set1][1].tag == live_tag1);
wire live_hit2 = tlb[live_set2][2].valid && (tlb[live_set2][2].tag == live_tag2);
wire live_hit3 = tlb[live_set3][3].valid && (tlb[live_set3][3].tag == live_tag3);

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
                                      update_pfn[19:5] == 15'h5};
    else if (vipt_refill_write)
        vipt_tlb[vipt_refill_index] <= {vipt_refill_linear[31:17],
                                        vipt_refill_pfn,
                                        vipt_refill_writable,
                                        vipt_refill_user,
                                        vipt_refill_dirty,
                                        vipt_refill_pfn[19:5] == 15'h5};
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
    case (hit_way)
        2'd0: begin
            physical_addr = {tlb[lookup_set][0].pfn, linear_addr[11:0]};
            writable = tlb[lookup_set][0].writable;
            user = tlb[lookup_set][0].user;
            dirty = tlb[lookup_set][0].dirty;
        end
        2'd1: begin
            physical_addr = {tlb[lookup_set][1].pfn, linear_addr[11:0]};
            writable = tlb[lookup_set][1].writable;
            user = tlb[lookup_set][1].user;
            dirty = tlb[lookup_set][1].dirty;
        end
        2'd2: begin
            physical_addr = {tlb[lookup_set][2].pfn, linear_addr[11:0]};
            writable = tlb[lookup_set][2].writable;
            user = tlb[lookup_set][2].user;
            dirty = tlb[lookup_set][2].dirty;
        end
        2'd3: begin
            physical_addr = {tlb[lookup_set][3].pfn, linear_addr[11:0]};
            writable = tlb[lookup_set][3].writable;
            user = tlb[lookup_set][3].user;
            dirty = tlb[lookup_set][3].dirty;
        end
    endcase

    // If no hit, output linear address (will be overridden by page walker result)
    if (!hit) begin
        physical_addr = linear_addr;
        writable = 1'b1;
        user = 1'b0;
        dirty = 1'b0;
    end
end

always_comb begin
    live_hit = live_hit0 | live_hit1 | live_hit2 | live_hit3;
    // Matching translations are unique.  Select each field directly from the
    // one-hot hit vector instead of priority-encoding a way and then muxing;
    // this shortens the live address -> paging/cache finalize cone.
    live_physical_addr = {
        ({20{live_hit0}} & tlb[live_set0][0].pfn) |
        ({20{live_hit1}} & tlb[live_set1][1].pfn) |
        ({20{live_hit2}} & tlb[live_set2][2].pfn) |
        ({20{live_hit3}} & tlb[live_set3][3].pfn),
        linear_addr_live[11:0]
    };
    live_writable = !live_hit |
                    (live_hit0 & tlb[live_set0][0].writable) |
                    (live_hit1 & tlb[live_set1][1].writable) |
                    (live_hit2 & tlb[live_set2][2].writable) |
                    (live_hit3 & tlb[live_set3][3].writable);
    live_user = (live_hit0 & tlb[live_set0][0].user) |
                (live_hit1 & tlb[live_set1][1].user) |
                (live_hit2 & tlb[live_set2][2].user) |
                (live_hit3 & tlb[live_set3][3].user);
    live_dirty = (live_hit0 & tlb[live_set0][0].dirty) |
                 (live_hit1 & tlb[live_set1][1].dirty) |
                 (live_hit2 & tlb[live_set2][2].dirty) |
                 (live_hit3 & tlb[live_set3][3].dirty);
end

// Update address decomposition
wire [2:0]  update_set = update_vpn[2:0];
wire [2:0]  update_plru = plru[update_set];

// If the VPN is already present in the set, update that way in place. Blind PLRU allocation creates duplicate entries, and the hit...
// Details: doc/z486/implementation_notes.md#src-24-z486-paging-tlb-sv-187
wire [16:0] update_tag = update_vpn[19:3];
wire match0 = tlb[update_set][0].valid && (tlb[update_set][0].tag == update_tag);
wire match1 = tlb[update_set][1].valid && (tlb[update_set][1].tag == update_tag);
wire match2 = tlb[update_set][2].valid && (tlb[update_set][2].tag == update_tag);
wire match3 = tlb[update_set][3].valid && (tlb[update_set][3].tag == update_tag);

wire [2:0] invalidate_set = invalidate_vpn[2:0];
wire [16:0] invalidate_tag = invalidate_vpn[19:3];

// PLRU victim selection for the update set (existing entry wins)
wire [1:0] victim_way = match0 ? 2'd0 :
                        match1 ? 2'd1 :
                        match2 ? 2'd2 :
                        match3 ? 2'd3 :
                        update_plru[0] ? (update_plru[2] ? 2'd3 : 2'd2) :
                                          (update_plru[1] ? 2'd1 : 2'd0);

// TLB update and PLRU management
integer s;
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        // Invalidate all entries on reset
        for (s = 0; s < 8; s = s + 1) begin
            tlb[s][0].valid <= 1'b0;
            tlb[s][1].valid <= 1'b0;
            tlb[s][2].valid <= 1'b0;
            tlb[s][3].valid <= 1'b0;
            plru[s] <= 3'b000;
        end
    end else if (invalidate_all) begin
        // CR3 write - flush entire TLB
        for (s = 0; s < 8; s = s + 1) begin
            tlb[s][0].valid <= 1'b0;
            tlb[s][1].valid <= 1'b0;
            tlb[s][2].valid <= 1'b0;
            tlb[s][3].valid <= 1'b0;
            plru[s] <= 3'b000;
        end
    end else if (invalidate_page) begin
        // Multiple matching ways are not expected, but clear every match so
        // INVLPG also repairs any duplicate left by an earlier implementation.
        if (tlb[invalidate_set][0].valid &&
            tlb[invalidate_set][0].tag == invalidate_tag)
            tlb[invalidate_set][0].valid <= 1'b0;
        if (tlb[invalidate_set][1].valid &&
            tlb[invalidate_set][1].tag == invalidate_tag)
            tlb[invalidate_set][1].valid <= 1'b0;
        if (tlb[invalidate_set][2].valid &&
            tlb[invalidate_set][2].tag == invalidate_tag)
            tlb[invalidate_set][2].valid <= 1'b0;
        if (tlb[invalidate_set][3].valid &&
            tlb[invalidate_set][3].tag == invalidate_tag)
            tlb[invalidate_set][3].valid <= 1'b0;
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
            case (victim_way)
                2'd0: begin
                    tlb[update_set][0].valid <= 1'b1;
                    tlb[update_set][0].tag <= update_tag;
                    tlb[update_set][0].pfn <= update_pfn;
                    tlb[update_set][0].writable <= update_writable;
                    tlb[update_set][0].user <= update_user;
                    tlb[update_set][0].dirty <= update_dirty;
                    vga_mem[update_set][0] <= (update_pfn[19:5] == 15'h5);
                    plru[update_set][0] <= 1'b1; plru[update_set][1] <= 1'b1;
                end
                2'd1: begin
                    tlb[update_set][1].valid <= 1'b1;
                    tlb[update_set][1].tag <= update_tag;
                    tlb[update_set][1].pfn <= update_pfn;
                    tlb[update_set][1].writable <= update_writable;
                    tlb[update_set][1].user <= update_user;
                    tlb[update_set][1].dirty <= update_dirty;
                    vga_mem[update_set][1] <= (update_pfn[19:5] == 15'h5);
                    plru[update_set][0] <= 1'b1; plru[update_set][1] <= 1'b0;
                end
                2'd2: begin
                    tlb[update_set][2].valid <= 1'b1;
                    tlb[update_set][2].tag <= update_tag;
                    tlb[update_set][2].pfn <= update_pfn;
                    tlb[update_set][2].writable <= update_writable;
                    tlb[update_set][2].user <= update_user;
                    tlb[update_set][2].dirty <= update_dirty;
                    vga_mem[update_set][2] <= (update_pfn[19:5] == 15'h5);
                    plru[update_set][0] <= 1'b0; plru[update_set][2] <= 1'b1;
                end
                2'd3: begin
                    tlb[update_set][3].valid <= 1'b1;
                    tlb[update_set][3].tag <= update_tag;
                    tlb[update_set][3].pfn <= update_pfn;
                    tlb[update_set][3].writable <= update_writable;
                    tlb[update_set][3].user <= update_user;
                    tlb[update_set][3].dirty <= update_dirty;
                    vga_mem[update_set][3] <= (update_pfn[19:5] == 15'h5);
                    plru[update_set][0] <= 1'b0; plru[update_set][2] <= 1'b0;
                end
            endcase

            // synthesis translate_off
            if (TRACE_PAGING_EN)
                $display("TLB UPDATE: vpn=%05x pfn=%05x writable=%b user=%b set=%0d victim_way=%0d",
                         update_vpn, update_pfn, update_writable, update_user, update_set, victim_way);
            // synthesis translate_on
        end
    end
end

endmodule
