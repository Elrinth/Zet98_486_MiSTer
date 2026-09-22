# EGC implementation work

`pc98_egc_rop.sv` is the boolean raster-operation kernel for a future EGC bus
implementation. It is not in the Quartus source list, is not connected to the
machine, and does not establish working EGC support or a game speedup.

Four native 16-bit VRAM words are ordered B, R, G, E. Operation bit selection
uses `{source, destination, pattern}`. This matches the eight minterms in
[NP2kai memegc.c](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/mem/memegc.c)
and MAME's `egc_do_partial_op` in
[pc9801_v.cpp](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc9801_v.cpp).

The kernel produces `base XOR (destination AND xor_mask)`. For fixed source
and pattern, those coefficients represent every operation on one destination
bit. Disabled planes, bytes and clipped pixels preserve the old destination.
This permits a later memory-domain merge without returning destination data
through the CPU clock domain. The existing GRCG set/preserve interface uses OR
and a shared 16-bit mask; it cannot express general EGC destination inversion.
Do not connect these coefficients to that interface without changing its
semantics and validating the held data transfer.

`tests/run-egc-rop.sh` checks all operation tables and truth-table inputs,
all plane and byte-enable combinations, then all 16-bit clipping masks with
changing operands. It rejects an OR merge, source/pattern swaps and unmasked
writes. These are arithmetic tests, not EGC register/bus tests.

Still required:

- Port 04A0h–04AFh byte/word writes, extended-video enable/protection and GRCG
  enable interaction.
- Source/pattern latches, shifts across successive byte and word accesses,
  direction, bit count, first/last clipping and read comparisons.
- CPU and drawing-port arbitration, SDRAM transactions, clock-crossing and
  timing validation, and actual PC-98 driver/game tests.

Reference discrepancies must be resolved with diagnostic captures before
assuming behavior. NP2kai resets alignment on shift/length writes; MAME also
resets it on operation writes. Pattern selection 6000h and several source-load
paths differ. MAME stores VRAM with each byte's bits reversed, whereas this
core's CPU-facing memory words use native byte order. A shifter copied without
accounting for that representation would reverse alignment/clipping.

The current Rusty test image uses the GDC driver, not a working EGC driver.

