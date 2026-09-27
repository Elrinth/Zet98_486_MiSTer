// z486 cache and external-memory fabric.
// Owns both L1 caches, A20 masking, refill arbitration, and response tracking.
`include "z486_platform.svh"
module memory
    import z486_cache_map_pkg::*;
#(
    parameter PC98_MODE = 0,
    parameter PC98_EXT_RAM_MB = 0,
    parameter PROTECT_UMA_ROM = 0,
    parameter DCACHE_SET_BITS = 7,
    parameter ICACHE_SET_BITS = 7,
    parameter ENABLE_X87 = 0,
    parameter ENABLE_DEVICE_MMIO = 0,
    parameter [31:0] DEVICE_MMIO_MASK = 32'hff00_0000,

    // A20 gate masks, applied closed / open. Default = PC/AT bit-20 clear / unmasked.
    parameter [31:0] A20_MASK_OFF = 32'hffef_ffff,
    parameter [31:0] A20_MASK_ON  = 32'hffff_ffff,

    // VGA/device A0000-BFFFF template window (VGA_ENABLE gates only this copy).
    // VGA_PRE_WRAP: 1 = raw, 0 = A20-masked.
    parameter        VGA_ENABLE = 0,
    parameter        VGA_PRE_WRAP = 1,
    parameter [1:0]  VGA_CLASS = Z486_CACHE_DIRECT,
    parameter [31:0] VGA_BASE = 32'h000a_0000,
    parameter [31:0] VGA_TOP  = 32'h000b_ffff,

    // Device aperture (PC-98: A0000-FFFFF). Disabled by default.
    parameter        APERTURE_ENABLE = 0,
    parameter [1:0]  APERTURE_CLASS = Z486_CACHE_DIRECT,
    parameter [31:0] APERTURE_BASE = 32'h000a_0000,
    parameter [31:0] APERTURE_TOP  = 32'h000f_ffff,

    // Device-memory aliases (PC-98 mirror/PEGC/fw_high). Disabled by default.
    parameter        ALIAS_ENABLE = 0,
    parameter [1:0]  ALIAS_CLASS = Z486_CACHE_DIRECT,
    parameter [31:0] ALIAS0_BASE = 32'h00f0_0000,
    parameter [31:0] ALIAS0_TOP  = 32'h00ff_ffff,
    parameter [31:0] ALIAS1_BASE = 32'hfff0_0000,
    parameter [31:0] ALIAS1_TOP  = 32'hfff7_ffff,
    parameter [31:0] ALIAS2_BASE = 32'hffff_8000,
    parameter [31:0] ALIAS2_TOP  = 32'hffff_ffff,

    // Window-0 overlay range (PC-98 0x80000-0x9FFFF), enabled only when win0_unmapped.
    parameter        WIN0_ENABLE = 0,
    parameter [1:0]  WIN0_CLASS = Z486_CACHE_NO_ALLOC,
    parameter [31:0] WIN0_BASE = 32'h0008_0000,
    parameter [31:0] WIN0_TOP  = 32'h0009_ffff,

    // No-allocate bound: addresses at or above it never install a line.
    parameter        NO_ALLOC_ENABLE = 0,
    parameter [1:0]  NO_ALLOC_CLASS = Z486_CACHE_NO_ALLOC,
    parameter [31:0] NO_ALLOC_BOUND = 32'h0800_0000
) (
    input              clk,
    input              reset_n,
    input              cache_invalidate,
    input              cache_upper_ram,
    input              a20_enable,
    input              device_mmio_enable,
    input      [31:0]  device_mmio_base,
    // Idle in the default map; the template's WIN0 window uses it.
    /* verilator lint_off UNUSEDSIGNAL */
    input              win0_unmapped,        // 0x80000-0x9FFFF target is not RAM
    /* verilator lint_on UNUSEDSIGNAL */

    // Paging-unit demand request
    input              dcache_req_valid,
    input      [31:0]  dcache_req_phys_addr_raw,
    input      [11:0]  dcache_req_preread_offset,
    input              dcache_req_preread_priority,
    input              dcache_req_write,
    input       [3:0]  dcache_req_be,
    input      [31:0]  dcache_req_wdata,
    input      [31:0]  dcache_direct_wdata,
    input              dcache_req_is_io,
    input              dcache_req_is_inta,
    input              dcache_req_is_x87,
    input              dcache_req_is_vga_mem,
    output             dcache_req_accepted, // Request ownership transferred
    output             dcache_req_complete, // Read or write operation completed
    output             dcache_read_complete, // Read data is valid this cycle
    output     [31:0]  dcache_rdata,

    // Retained, already-qualified physical store from a microcode fast path.
    // Acceptance transfers irrevocable ownership to the ordinary cache/store
    // queue; the cache may perform its internal enqueue on the following edge.
    input              fast_store_valid,
    input      [31:0]  fast_store_phys_addr_raw,
    input       [3:0]  fast_store_be,
    input      [31:0]  fast_store_wdata,
    output             fast_store_accepted,

    // Non-owning hardwired-load preread. A miss is retried through the demand
    // request interface above; this port never starts a fill by itself.
    input              dcache_vipt_probe_valid,
    input      [11:0]  dcache_vipt_probe_offset,
    output             dcache_vipt_probe_ready,
    output             dcache_vipt_probe_accepted,
    output             dcache_vipt_probe_direct_accepted,
    input              dcache_vipt_resolve_valid,
    input      [31:0]  dcache_vipt_resolve_phys_addr_raw,
    output             dcache_vipt_resolve_hit,
    output     [31:0]  dcache_vipt_resolve_data,

    // x87 data-port response
    output             x87_req_selected,    // Route demand request to x87 port space
    input              x87_req_accepted,
    input              x87_req_complete,
    input              x87_read_complete,
    input      [31:0]  x87_rdata,

    // Paging-unit instruction request
    input              icache_req_valid,
    input      [31:0]  icache_req_phys_addr_raw,
    output             icache_req_accepted, // Prefetch request ownership transferred
    output             icache_req_complete, // Full instruction line is valid
    output     [127:0] icache_rdata,

    // External memory writers invalidate both caches.
    input      [31:0]  snoop_addr,
    input              snoop_valid,          // External writer invalidates this line

    // External memory bus
    output     [31:2]  addr,
    output      [3:0]  be,
    output      [7:0]  burstcount,
    output             line_read,             // Request is one complete cache line
    input      [31:0]  din,
    input      [127:0] line_din,
    output     [31:0]  dout,
    output             valid,                // External request is present
    input              ready,                // External request was accepted
    output             write,
    output             io,
    input              resp_valid,           // External read beat returned
    input              line_resp_valid,      // Complete aligned line returned
    output             inta
);

// z486_window_match assumes the A20 mask only clears bits [31:20]; assert it once.
// synthesis translate_off
initial begin
    if (A20_MASK_OFF[19:0] !== 20'hfffff)
        $fatal(1, "z486 A20MASK: A20_MASK_OFF[19:0] must be all ones (%h); z486_window_match assumes the mask only clears bits [31:20]",
               A20_MASK_OFF);
    if (A20_MASK_ON[19:0] !== 20'hfffff)
        $fatal(1, "z486 A20MASK: A20_MASK_ON[19:0] must be all ones (%h)",
               A20_MASK_ON);
    // A line at or above the L1 tag reach would alias a lower address.
    if (NO_ALLOC_ENABLE &&
        ({1'b0, NO_ALLOC_BOUND} > (33'd1 << `Z486_L1_PHYS_ADDR_BITS)))
        $fatal(1, "z486 NO_ALLOC_BOUND %h exceeds the L1 tag reach %0h (Z486_L1_PHYS_ADDR_BITS=%0d)",
               NO_ALLOC_BOUND, 33'd1 << `Z486_L1_PHYS_ADDR_BITS,
               `Z486_L1_PHYS_ADDR_BITS);
    // paging_tlb classifies this window per 4 KB page, the unpaged path per byte.
    if (VGA_BASE[11:0] !== 12'h000)
        $fatal(1, "z486 VGA_BASE %h is not page-aligned (VGA_BASE[11:0] must be 0)",
               VGA_BASE);
    if (VGA_TOP[11:0] !== 12'hfff)
        $fatal(1, "z486 VGA_TOP %h must end on a page boundary (VGA_TOP[11:0] must be fff)",
               VGA_TOP);
end
// synthesis translate_on

// A20 masking; the default masks reproduce upstream exactly.
wire [31:0] dcache_req_a20_mask = (a20_enable || dcache_req_is_io)
                                ? A20_MASK_ON : A20_MASK_OFF;
wire [31:0] dcache_req_phys_addr = dcache_req_phys_addr_raw & dcache_req_a20_mask;
wire [31:0] dcache_vipt_resolve_phys_addr = dcache_vipt_resolve_phys_addr_raw &
                                            (a20_enable ? A20_MASK_ON : A20_MASK_OFF);
wire [31:0] fast_store_phys_addr = fast_store_phys_addr_raw &
                                   (a20_enable ? A20_MASK_ON : A20_MASK_OFF);
wire [31:0] icache_req_phys_addr = icache_req_phys_addr_raw &
                                   (a20_enable ? A20_MASK_ON : A20_MASK_OFF);
// PC-98 banks, VRAM, ROM and unmapped space must never acquire RAM tags.
// Low fixed RAM and the extended RAM aperture are the only cacheable regions.
function automatic pc98_cacheable(input [31:0] a);
    pc98_cacheable = (a < 32'h0008_0000) ||
                    (a >= 32'h0010_0000 && a < PC98_EXT_RAM_MB * 32'h0010_0000 &&
                     !(a >= 32'h00f0_0000 && a < 32'h0100_0000));
endfunction
wire dcache_req_is_device_mmio = (PC98_MODE && !pc98_cacheable(dcache_req_phys_addr)) || ENABLE_DEVICE_MMIO &&
                                  device_mmio_enable &&
                                  ((dcache_req_phys_addr & DEVICE_MMIO_MASK) ==
                                   (device_mmio_base & DEVICE_MMIO_MASK));
wire dcache_vipt_is_device_mmio = (PC98_MODE && !pc98_cacheable(dcache_vipt_resolve_phys_addr)) || ENABLE_DEVICE_MMIO &&
                                   device_mmio_enable &&
                                   ((dcache_vipt_resolve_phys_addr &
                                     DEVICE_MMIO_MASK) ==
                                    (device_mmio_base & DEVICE_MMIO_MASK));

// Memory-map classification: the paging unit's VGA verdict is a floor; template
// windows only add uncached classes (a constant with none enabled).
localparam bit Z486_TEMPLATE_WINDOWS = VGA_ENABLE | APERTURE_ENABLE |
                                       ALIAS_ENABLE | WIN0_ENABLE |
                                       NO_ALLOC_ENABLE;

// Quartus 17 rejects a user-enum-typed net; carry the class as a plain 2-bit vector.
wire dcache_req_is_uncached;
wire [1:0] dcache_vipt_class;
wire icache_req_is_no_alloc;

generate
if (Z486_TEMPLATE_WINDOWS) begin : g_memmap_windows
    wire [1:0] dcache_req_class;   // template-window path only
    wire [31:0] dcache_vga_addr = VGA_PRE_WRAP ? dcache_req_phys_addr_raw
                                               : dcache_req_phys_addr;
    assign dcache_req_class = z486_classify_phys(
        dcache_req_phys_addr_raw, dcache_req_phys_addr, dcache_vga_addr,
        VGA_ENABLE, VGA_CLASS, VGA_BASE, VGA_TOP,
        APERTURE_ENABLE, APERTURE_CLASS, APERTURE_BASE, APERTURE_TOP,
        ALIAS_ENABLE, ALIAS_CLASS,
        ALIAS0_BASE, ALIAS0_TOP, ALIAS1_BASE, ALIAS1_TOP, ALIAS2_BASE, ALIAS2_TOP,
        WIN0_ENABLE && win0_unmapped, WIN0_CLASS, WIN0_BASE, WIN0_TOP,
        NO_ALLOC_ENABLE, NO_ALLOC_CLASS, NO_ALLOC_BOUND);
    assign dcache_vipt_class = z486_classify_phys(
        dcache_vipt_resolve_phys_addr_raw, dcache_vipt_resolve_phys_addr,
        dcache_vipt_resolve_phys_addr,
        VGA_ENABLE, VGA_CLASS, VGA_BASE, VGA_TOP,
        APERTURE_ENABLE, APERTURE_CLASS, APERTURE_BASE, APERTURE_TOP,
        ALIAS_ENABLE, ALIAS_CLASS,
        ALIAS0_BASE, ALIAS0_TOP, ALIAS1_BASE, ALIAS1_TOP, ALIAS2_BASE, ALIAS2_TOP,
        WIN0_ENABLE && win0_unmapped, WIN0_CLASS, WIN0_BASE, WIN0_TOP,
        NO_ALLOC_ENABLE, NO_ALLOC_CLASS, NO_ALLOC_BOUND);
    assign dcache_req_is_uncached = dcache_req_is_vga_mem ||
                                    (dcache_req_class != Z486_CACHE_CACHEABLE);
    assign icache_req_is_no_alloc = (z486_classify_phys(
        icache_req_phys_addr_raw, icache_req_phys_addr, icache_req_phys_addr,
        VGA_ENABLE, VGA_CLASS, VGA_BASE, VGA_TOP,
        APERTURE_ENABLE, APERTURE_CLASS, APERTURE_BASE, APERTURE_TOP,
        ALIAS_ENABLE, ALIAS_CLASS,
        ALIAS0_BASE, ALIAS0_TOP, ALIAS1_BASE, ALIAS1_TOP, ALIAS2_BASE, ALIAS2_TOP,
        WIN0_ENABLE && win0_unmapped, WIN0_CLASS, WIN0_BASE, WIN0_TOP,
        NO_ALLOC_ENABLE, NO_ALLOC_CLASS, NO_ALLOC_BOUND) == Z486_CACHE_NO_ALLOC);
end else begin : g_memmap_inert
    // Structural no-op: upstream VGA-only demand verdict.
    assign dcache_vipt_class = Z486_CACHE_CACHEABLE;
    assign dcache_req_is_uncached = dcache_req_is_vga_mem;
    assign icache_req_is_no_alloc = 1'b0;
end
endgenerate

// synthesis translate_off
// DEFAULT-EQUIVALENCE FUSES: the default parameter set must reproduce upstream.
always @* begin : memmap_equiv_fuse
    logic [31:0] ref_d, ref_v, ref_f, ref_i;
    logic ref_uncached;
    ref_uncached = 1'b0;
    if (A20_MASK_OFF == ~32'h0010_0000 && A20_MASK_ON == 32'hffff_ffff) begin
        ref_d = (!a20_enable && !dcache_req_is_io)
              ? (dcache_req_phys_addr_raw & ~32'h0010_0000)
              : dcache_req_phys_addr_raw;
        ref_v = !a20_enable
              ? (dcache_vipt_resolve_phys_addr_raw & ~32'h0010_0000)
              : dcache_vipt_resolve_phys_addr_raw;
        ref_f = !a20_enable
              ? (fast_store_phys_addr_raw & ~32'h0010_0000)
              : fast_store_phys_addr_raw;
        ref_i = !a20_enable
              ? (icache_req_phys_addr_raw & ~32'h0010_0000)
              : icache_req_phys_addr_raw;
        if ((dcache_req_phys_addr !== ref_d) ||
            (dcache_vipt_resolve_phys_addr !== ref_v) ||
            (fast_store_phys_addr !== ref_f) || (icache_req_phys_addr !== ref_i))
            $fatal(1, "A20MUX FUSE MISMATCH");
    end
    if (!Z486_TEMPLATE_WINDOWS && VGA_BASE == 32'h000a_0000 &&
        VGA_TOP == 32'h000b_ffff && dcache_req_valid) begin
        ref_uncached = z486_addr_in_window(dcache_req_phys_addr_raw,
                                           32'h000a_0000, 32'h000b_ffff);
        if (ref_uncached !== dcache_req_is_uncached)
            $fatal(1, "MEMMAP UNCACHED FUSE MISMATCH raw=%h got=%b ref=%b",
                   dcache_req_phys_addr_raw, dcache_req_is_uncached, ref_uncached);
    end
    if (VGA_ENABLE && VGA_PRE_WRAP && VGA_CLASS == Z486_CACHE_DIRECT &&
        dcache_req_valid) begin
        ref_uncached = z486_addr_in_window(dcache_req_phys_addr_raw, VGA_BASE, VGA_TOP);
        if (ref_uncached !== dcache_req_is_vga_mem)
            $fatal(1, "MEMMAP VGA FUSE MISMATCH raw=%h window=%b input=%b",
                   dcache_req_phys_addr_raw, ref_uncached, dcache_req_is_vga_mem);
    end
end
// synthesis translate_on

wire [31:0] dcache_cpu_dout;
wire        dcache_vipt_resolve_hit_cache;
wire        dcache_cpu_ready;
wire        dcache_cpu_resp_valid;
wire        dcache_stores_drained;
wire [31:0] dcache_store_patch_addr;
wire [31:0] dcache_store_patch_data;
wire  [3:0] dcache_store_patch_be;
wire        dcache_store_patch_valid;
wire [31:0] dcache_mem_addr;
wire [31:0] dcache_mem_din;
wire  [3:0] dcache_mem_be;
wire  [7:0] dcache_mem_burstcount;
wire        dcache_mem_valid;
wire        dcache_mem_write;
wire        dcache_mem_ready;
wire        dcache_mem_resp_valid;
wire        dcache_mem_line_resp_valid;

wire [127:0] icache_cpu_line;
wire         icache_cpu_ready;
wire         icache_cpu_resp_valid;
wire [31:0]  icache_mem_addr;
wire  [3:0]  icache_mem_be;
wire  [7:0]  icache_mem_burstcount;
wire         icache_mem_valid;
wire         icache_mem_ready;
wire         icache_mem_resp_valid;
wire         icache_mem_line_resp_valid;

assign dcache_vipt_resolve_hit = dcache_vipt_resolve_hit_cache &&
                                  !dcache_vipt_is_device_mmio &&
                                  (dcache_vipt_class == Z486_CACHE_CACHEABLE);

logic [7:0] dcache_rd_pending;
logic [7:0] icache_rd_pending;
logic       dcache_cpu_rd_pending;
logic       icache_cpu_rd_pending;
logic       direct_rd_pending;

assign x87_req_selected = ENABLE_X87 && dcache_req_valid && dcache_req_is_x87;

// VGA aperture accesses are device transactions. Bypass the posted L1 store
// queue so an ET4000 bank-register write cannot overtake framebuffer writes.
wire normal_cache_req = dcache_req_valid && !dcache_req_is_io &&
                        !dcache_req_is_inta && !dcache_req_is_uncached &&
                        !dcache_req_is_device_mmio &&
                        !x87_req_selected;
wire dcache_cpu_req = fast_store_valid || normal_cache_req;
wire [31:0] dcache_cpu_addr = fast_store_valid ? fast_store_phys_addr
                                              : dcache_req_phys_addr;
wire [31:0] dcache_cpu_wdata = fast_store_valid ? fast_store_wdata
                                               : dcache_req_wdata;
wire [3:0] dcache_cpu_be = fast_store_valid ? fast_store_be : dcache_req_be;
wire dcache_cpu_write = fast_store_valid || dcache_req_write;
// WR_FAST already owns a translated physical address.  Its request must also
// own the synchronous RAM preread; leaving the normal paging preread here
// makes the following S_LOOKUP compare against an unrelated set.
wire [11:0] dcache_cpu_preread_offset = fast_store_valid
                                      ? fast_store_phys_addr[11:0]
                                      : dcache_req_preread_offset;
wire dcache_cpu_preread_priority = fast_store_valid ||
                                   dcache_req_preread_priority;
wire dcache_direct_req = dcache_req_valid && !x87_req_selected &&
                         (dcache_req_is_io || dcache_req_is_inta ||
                          dcache_req_is_uncached ||
                          dcache_req_is_device_mmio);
wire dcache_read_pending = (dcache_rd_pending != 8'd0);
wire icache_read_pending = (icache_rd_pending != 8'd0);
wire dcache_read_accept = normal_cache_req && !dcache_req_write && dcache_cpu_ready;
wire icache_read_accept = icache_req_valid && icache_cpu_ready;
wire dcache_read_done = dcache_cpu_resp_valid &&
                        (dcache_cpu_rd_pending || dcache_read_accept);
wire icache_read_done = icache_cpu_resp_valid &&
                        (icache_cpu_rd_pending || icache_read_accept);
// I/O and INTA transactions must not overtake older posted stores.  This is
// what makes a CPU-filled Sound Blaster buffer visible before the following
// DSP command lets DMA consume it.  VGA memory already bypasses the posted
// queue, so direct VGA accesses remain mutually ordered without draining
// unrelated normal-RAM stores first.
// Only VGA writes may bypass the posted store queue (upstream); PC-98 mode
// always drains (every non-RAM window is device space).
wire direct_req_ordered = (!PC98_MODE && dcache_req_is_vga_mem) || dcache_stores_drained;
wire ext_direct_req = dcache_direct_req && direct_req_ordered &&
                      !direct_rd_pending &&
                      !dcache_read_pending && !icache_read_pending;
wire ext_dcache_req = dcache_mem_valid && !ext_direct_req &&
                      !direct_rd_pending && !icache_read_pending;
wire ext_icache_req = icache_mem_valid && !ext_direct_req && !ext_dcache_req &&
                      !direct_rd_pending && !dcache_read_pending;

localparam [1:0] EXT_SRC_NONE   = 2'd0;
localparam [1:0] EXT_SRC_DIRECT = 2'd1;
localparam [1:0] EXT_SRC_DCACHE = 2'd2;
localparam [1:0] EXT_SRC_ICACHE = 2'd3;

logic        ext_valid_r;
logic [1:0]  ext_src_r;
logic [31:2] ext_addr_r;
logic [3:0]  ext_be_r;
logic [7:0]  ext_burstcount_r;
logic [31:0] ext_direct_dout_r;
logic [31:0] ext_dcache_dout_r;
logic        ext_write_r;
logic        ext_io_r;
logic        ext_inta_r;

wire ext_direct_accept = ext_valid_r && ready && (ext_src_r == EXT_SRC_DIRECT);
wire ext_dcache_accept = ext_valid_r && ready && (ext_src_r == EXT_SRC_DCACHE);
wire ext_icache_accept = ext_valid_r && ready && (ext_src_r == EXT_SRC_ICACHE);
wire direct_rd_resp_now = resp_valid &&
                          (direct_rd_pending || (ext_direct_accept && !ext_write_r));
logic       icache_write_snoop_pending;
logic [31:0] icache_write_snoop_addr_r;
logic [31:0] icache_write_snoop_data_r;
logic  [3:0] icache_write_snoop_be_r;
// Normally the I-cache consumes the D-cache's registered S_LOOKUP store
// directly.  The one-entry pending slot only resolves an external invalidate
// collision (or holds the following store while an older pending patch is
// consumed), preserving invalidate priority without returning to live paging
// request signals.
// Upper conventional RAM remains uncached for data. Its stores therefore
// bypass the D-cache patch path: invalidate their instruction line only after
// the external write completes. Bank aliases/DMA use the policy's full flush.
wire pc98_upper_write = PC98_MODE && ext_direct_accept && ext_write_r &&
                        !ext_io_r && !ext_inta_r &&
                        {ext_addr_r,2'b00} >= 32'h0008_0000 &&
                        {ext_addr_r,2'b00} < 32'h000a_0000;
wire [31:0] instruction_invalidate_addr = snoop_valid ? snoop_addr : {ext_addr_r,2'b00};
wire instruction_invalidate = snoop_valid || pc98_upper_write;
wire icache_write_patch_valid = !instruction_invalidate &&
                                (icache_write_snoop_pending ||
                                 dcache_store_patch_valid);
wire [31:0] icache_write_patch_addr = icache_write_snoop_pending
                                    ? icache_write_snoop_addr_r
                                    : dcache_store_patch_addr;
wire [31:0] icache_write_patch_data = icache_write_snoop_pending
                                    ? icache_write_snoop_data_r
                                    : dcache_store_patch_data;
wire [3:0] icache_write_patch_be = icache_write_snoop_pending
                                 ? icache_write_snoop_be_r
                                 : dcache_store_patch_be;

wire normal_req_accepted = normal_cache_req ? (dcache_cpu_ready && !fast_store_valid)
                                            : ext_direct_accept;
wire normal_req_complete = dcache_cpu_resp_valid ||
                           (normal_cache_req && dcache_req_write &&
                            dcache_cpu_ready && !fast_store_valid) ||
                           direct_rd_resp_now ||
                           (ext_direct_accept && ext_write_r);
wire normal_read_complete = dcache_cpu_resp_valid || direct_rd_resp_now;
wire [31:0] normal_rdata = dcache_cpu_resp_valid ? dcache_cpu_dout : din;

assign dcache_req_accepted = x87_req_selected ? x87_req_accepted : normal_req_accepted;
assign fast_store_accepted = fast_store_valid && dcache_cpu_ready;
assign dcache_req_complete = normal_req_complete || x87_req_complete;
assign dcache_read_complete = normal_read_complete || x87_read_complete;
assign dcache_rdata = x87_read_complete ? x87_rdata : normal_rdata;
assign icache_req_accepted = icache_cpu_ready;
assign icache_req_complete = icache_cpu_resp_valid;
assign icache_rdata = icache_cpu_line;

assign addr       = ext_addr_r;
assign be         = ext_be_r;
assign burstcount = ext_burstcount_r;
assign line_read  = ext_valid_r && !ext_write_r &&
                    (ext_burstcount_r == 8'd4) &&
                    ((ext_src_r == EXT_SRC_DCACHE) ||
                     (ext_src_r == EXT_SRC_ICACHE));
assign dout       = (ext_src_r == EXT_SRC_DIRECT) ? ext_direct_dout_r :
                    (ext_src_r == EXT_SRC_DCACHE) ? ext_dcache_dout_r : 32'd0;
assign valid      = ext_valid_r;
assign write      = ext_valid_r && ext_write_r;
assign io         = ext_valid_r && ext_io_r;
assign inta       = ext_valid_r && ext_inta_r;

assign dcache_mem_ready = ext_dcache_accept;
assign icache_mem_ready = ext_icache_accept;
assign dcache_mem_resp_valid = dcache_read_pending && resp_valid;
assign icache_mem_resp_valid = icache_read_pending && resp_valid;
assign dcache_mem_line_resp_valid = dcache_read_pending && line_resp_valid;
assign icache_mem_line_resp_valid = icache_read_pending && line_resp_valid;

always_ff @(posedge clk) begin
    if (!reset_n) begin
        ext_valid_r <= 1'b0;
        ext_src_r <= EXT_SRC_NONE;
        ext_addr_r <= 30'h0;
        ext_be_r <= 4'h0;
        ext_burstcount_r <= 8'h0;
        ext_direct_dout_r <= 32'h0;
        ext_dcache_dout_r <= 32'h0;
        ext_write_r <= 1'b0;
        ext_io_r <= 1'b0;
        ext_inta_r <= 1'b0;
        dcache_rd_pending <= 8'd0;
        icache_rd_pending <= 8'd0;
        dcache_cpu_rd_pending <= 1'b0;
        icache_cpu_rd_pending <= 1'b0;
        direct_rd_pending <= 1'b0;
        icache_write_snoop_pending <= 1'b0;
        icache_write_snoop_addr_r <= 32'h0;
        icache_write_snoop_data_r <= 32'h0;
        icache_write_snoop_be_r <= 4'h0;
    end else begin
        // Data is speculative until ext_src_r selects its registered owner.
        // Capturing both sources unconditionally prevents request arbitration
        // and live translation from becoming clock-enable muxes on dout.
        ext_direct_dout_r <= dcache_direct_wdata;
        ext_dcache_dout_r <= dcache_mem_din;

        if (dcache_store_patch_valid &&
            (instruction_invalidate || icache_write_snoop_pending)) begin
            // The pending patch, when present, is consumed on this edge. Keep
            // the newly accepted store for the following cycle.
            icache_write_snoop_pending <= 1'b1;
            icache_write_snoop_addr_r <= dcache_store_patch_addr;
            icache_write_snoop_data_r <= dcache_store_patch_data;
            icache_write_snoop_be_r <= dcache_store_patch_be;
        end else if (icache_write_snoop_pending && !instruction_invalidate) begin
            icache_write_snoop_pending <= 1'b0;
        end

        if (ext_valid_r) begin
            if (ready) begin
                ext_valid_r <= 1'b0;
                ext_src_r <= EXT_SRC_NONE;
            end
        end else if (ext_direct_req) begin
            ext_valid_r <= 1'b1;
            ext_src_r <= EXT_SRC_DIRECT;
            ext_addr_r <= dcache_req_phys_addr[31:2];
            ext_be_r <= dcache_req_be;
            ext_burstcount_r <= 8'd1;
            ext_write_r <= dcache_req_write;
            ext_io_r <= dcache_req_is_io;
            ext_inta_r <= dcache_req_is_inta;
        end else if (ext_dcache_req) begin
            ext_valid_r <= 1'b1;
            ext_src_r <= EXT_SRC_DCACHE;
            ext_addr_r <= dcache_mem_addr[31:2];
            ext_be_r <= dcache_mem_be;
            ext_burstcount_r <= dcache_mem_burstcount;
            ext_write_r <= dcache_mem_write;
            ext_io_r <= 1'b0;
            ext_inta_r <= 1'b0;
        end else if (ext_icache_req) begin
            ext_valid_r <= 1'b1;
            ext_src_r <= EXT_SRC_ICACHE;
            ext_addr_r <= icache_mem_addr[31:2];
            ext_be_r <= icache_mem_be;
            ext_burstcount_r <= icache_mem_burstcount;
            ext_write_r <= 1'b0;
            ext_io_r <= 1'b0;
            ext_inta_r <= 1'b0;
        end

        if (ext_dcache_accept && !dcache_mem_write)
            dcache_rd_pending <= dcache_mem_burstcount;
        else if (dcache_read_pending && line_resp_valid)
            dcache_rd_pending <= 8'd0;
        else if (dcache_read_pending && resp_valid)
            dcache_rd_pending <= dcache_rd_pending - 8'd1;

        if (ext_icache_accept)
            icache_rd_pending <= icache_mem_burstcount;
        else if (icache_read_pending && line_resp_valid)
            icache_rd_pending <= 8'd0;
        else if (icache_read_pending && resp_valid)
            icache_rd_pending <= icache_rd_pending - 8'd1;

        if (dcache_read_accept && !dcache_read_done)
            dcache_cpu_rd_pending <= 1'b1;
        else if (dcache_read_done)
            dcache_cpu_rd_pending <= 1'b0;

        if (icache_read_accept && !icache_read_done)
            icache_cpu_rd_pending <= 1'b1;
        else if (icache_read_done)
            icache_cpu_rd_pending <= 1'b0;

        if (ext_direct_accept && !ext_write_r && !resp_valid)
            direct_rd_pending <= 1'b1;
        else if (direct_rd_pending && resp_valid)
            direct_rd_pending <= 1'b0;
    end
end

l1_cache #(
    .PROTECT_UMA_ROM(PROTECT_UMA_ROM),
    .SET_BITS(DCACHE_SET_BITS),
    .VGA_BASE(VGA_BASE),
    .VGA_TOP(VGA_TOP)
) dcache_inst (
    .clk(clk),
    .reset(!reset_n),
    .cpu_addr(dcache_cpu_addr),
    .cpu_preread_offset(dcache_cpu_preread_offset),
    .cpu_preread_priority(dcache_cpu_preread_priority),
    .cpu_din(dcache_cpu_wdata),
    .cpu_dout(dcache_cpu_dout),
    .cpu_be(dcache_cpu_be),
    .cpu_valid(dcache_cpu_req),
    .cpu_write(dcache_cpu_write),
    // I/O, INTA, x87, and VGA/device transactions are routed around this
    // cache above, so accepted D-cache requests need no physical-address
    // aperture decode on their register inputs.
    .cpu_uncacheable(PC98_MODE && !pc98_cacheable(dcache_cpu_addr)),
    .cpu_ready(dcache_cpu_ready),
    .cpu_resp_valid(dcache_cpu_resp_valid),
    .stores_drained(dcache_stores_drained),
    .store_patch_addr(dcache_store_patch_addr),
    .store_patch_data(dcache_store_patch_data),
    .store_patch_be(dcache_store_patch_be),
    .store_patch_valid(dcache_store_patch_valid),
    .vipt_probe_offset(dcache_vipt_probe_offset),
    .vipt_probe_valid(dcache_vipt_probe_valid),
    .vipt_probe_ready(dcache_vipt_probe_ready),
    .vipt_probe_accepted(dcache_vipt_probe_accepted),
    .vipt_probe_direct_accepted(dcache_vipt_probe_direct_accepted),
    .vipt_resolve_phys_addr(dcache_vipt_resolve_phys_addr),
    .vipt_resolve_valid(dcache_vipt_resolve_valid),
    .vipt_resolve_data(dcache_vipt_resolve_data),
    .vipt_resolve_hit(dcache_vipt_resolve_hit_cache),
    .mem_addr(dcache_mem_addr),
    .mem_din(dcache_mem_din),
    .mem_dout(din),
    .mem_line_dout(line_din),
    .mem_be(dcache_mem_be),
    .mem_burstcount(dcache_mem_burstcount),
    .mem_busy(ext_valid_r || direct_rd_pending || icache_read_pending),
    .mem_valid(dcache_mem_valid),
    .mem_write(dcache_mem_write),
    .mem_ready(dcache_mem_ready),
    .mem_resp_valid(dcache_mem_resp_valid),
    .mem_line_resp_valid(dcache_mem_line_resp_valid),
    .snoop_addr(snoop_addr),
    .snoop_valid(snoop_valid),
    .invalidate_all(PC98_MODE && cache_invalidate),
    .cache_enable(1'b1)
);

l1_icache #(
    .SET_BITS(ICACHE_SET_BITS)
) icache_inst (
    .clk(clk),
    .reset(!reset_n),
    .cpu_addr(icache_req_phys_addr),
    .cpu_line(icache_cpu_line),
    .cpu_valid(icache_req_valid),
    .cpu_no_alloc(icache_req_is_no_alloc),
    .cpu_ready(icache_cpu_ready),
    .cpu_resp_valid(icache_cpu_resp_valid),
    .mem_addr(icache_mem_addr),
    .mem_dout(din),
    .mem_line_dout(line_din),
    .mem_be(icache_mem_be),
    .mem_burstcount(icache_mem_burstcount),
    .mem_busy(ext_valid_r || direct_rd_pending || dcache_read_pending ||
              dcache_mem_valid),
    .mem_valid(icache_mem_valid),
    .mem_ready(icache_mem_ready),
    .mem_resp_valid(icache_mem_resp_valid),
    .mem_line_resp_valid(icache_mem_line_resp_valid),
    .patch_addr(icache_write_patch_addr),
    .patch_data(icache_write_patch_data),
    .patch_be(icache_write_patch_be),
    .patch_valid(icache_write_patch_valid),
    .invalidate_addr(instruction_invalidate_addr),
    .invalidate_valid(instruction_invalidate),
    .invalidate_all(PC98_MODE && cache_invalidate),
    // The existing PC-98 policy asserts this only for the native RAM bank;
    // remaps, alias writes and DMA invalidate all outstanding cache state.
    .cache_enable(!PC98_MODE || pc98_cacheable(icache_req_phys_addr) ||
                  (cache_upper_ram && icache_req_phys_addr >= 32'h0008_0000 &&
                   icache_req_phys_addr < 32'h000a_0000))
);

endmodule
