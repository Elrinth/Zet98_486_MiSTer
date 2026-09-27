// z486 shared memory-map / cache-classification package. Imported by memory.sv,
// paging_unit.sv, paging_tlb.sv, l1_cache.sv and z486.sv; all bounds are
// compile-time scalar parameters.
package z486_cache_map_pkg;

// Per-window cache class. DIRECT is an ordered uncached transaction with no
// D-line installed; NO_ALLOC also answers the I-cache fetch without a line.
typedef enum logic [1:0] {
    Z486_CACHE_CACHEABLE = 2'd0,
    Z486_CACHE_DIRECT    = 2'd1,
    Z486_CACHE_NO_ALLOC  = 2'd2
} z486_cache_class_t;

// Inclusive [base, top] membership on a 32-bit address.
function automatic logic z486_addr_in_window(input logic [31:0] addr,
                                             input logic [31:0] base,
                                             input logic [31:0] top);
    z486_addr_in_window = (addr >= base) && (addr <= top);
endfunction

// A20 view: the mask only clears bits [31:20], so a window inside one 1 MiB
// segment compares [19:0] on the raw address and the segment on the masked one.
function automatic logic z486_window_match(input logic [31:0] addr_raw,
                                           input logic [31:0] addr_post,
                                           input logic [31:0] base,
                                           input logic [31:0] top);
    if (base[31:20] == top[31:20])
        z486_window_match = (addr_raw[19:0] >= base[19:0]) &&
                            (addr_raw[19:0] <= top[19:0]) &&
                            (addr_post[31:20] == base[31:20]);
    else
        z486_window_match = z486_addr_in_window(addr_post, base, top);
endfunction

// Page-base membership for the TLB fill path (pfn<<12 inside the window).
function automatic logic z486_page_in_window(input logic [19:0] pfn,
                                             input logic [31:0] base,
                                             input logic [31:0] top);
    z486_page_in_window = z486_addr_in_window({pfn, 12'h000}, base, top);
endfunction

// Classify against the window list; a later window overrides an earlier one.
// vga_addr is raw under the pre-wrap test, else the A20-masked physical.
function automatic z486_cache_class_t z486_classify_phys(
    input logic [31:0] addr_raw,
    input logic [31:0] addr_post,
    input logic [31:0] vga_addr,
    input logic        vga_en,
    input logic [1:0]  vga_class,
    input logic [31:0] vga_base,
    input logic [31:0] vga_top,
    input logic        aperture_en,
    input logic [1:0]  aperture_class,
    input logic [31:0] aperture_base,
    input logic [31:0] aperture_top,
    input logic        alias_en,
    input logic [1:0]  alias_class,
    input logic [31:0] alias0_base,
    input logic [31:0] alias0_top,
    input logic [31:0] alias1_base,
    input logic [31:0] alias1_top,
    input logic [31:0] alias2_base,
    input logic [31:0] alias2_top,
    input logic        win0_en,
    input logic [1:0]  win0_class,
    input logic [31:0] win0_base,
    input logic [31:0] win0_top,
    input logic        no_alloc_en,
    input logic [1:0]  no_alloc_class,
    input logic [31:0] no_alloc_bound
);
    z486_cache_class_t cls;
    cls = Z486_CACHE_CACHEABLE;
    if (vga_en && z486_addr_in_window(vga_addr, vga_base, vga_top))
        cls = z486_cache_class_t'(vga_class);
    if (aperture_en && z486_window_match(addr_raw, addr_post, aperture_base, aperture_top))
        cls = z486_cache_class_t'(aperture_class);
    if (alias_en && (z486_window_match(addr_raw, addr_post, alias0_base, alias0_top) ||
                     z486_window_match(addr_raw, addr_post, alias1_base, alias1_top) ||
                     z486_window_match(addr_raw, addr_post, alias2_base, alias2_top)))
        cls = z486_cache_class_t'(alias_class);
    if (win0_en && z486_window_match(addr_raw, addr_post, win0_base, win0_top))
        cls = z486_cache_class_t'(win0_class);
    if (no_alloc_en && (addr_post >= no_alloc_bound))
        cls = z486_cache_class_t'(no_alloc_class);
    z486_classify_phys = cls;
endfunction

endpackage
