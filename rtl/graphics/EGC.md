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

- Integration of port 04A0h–04AFh writes, extended-video enable/protection and
  GRCG enable interaction with the machine.
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

`pc98_egc_registers.sv` implements the eight write-only programming registers
at 04A0h–04AFh on the existing 16-bit, byte-selected bus. It stores both lanes
independently, decodes the complete port address and commits once per held bus
cycle. Foreground/background expansion uses the low four color bits. Pixel
mask writes are ignored while color-select bits 14:13 are nonzero, matching
both reference implementations. Reset values follow NP2kai's `io/egc.c`.

Its `egc_enable` input follows NP2kai's register-write gating. Integration must
feed the existing TXTGDC protected EGC-enable latch; GRCG's enable controls VRAM
operation separately. MAME currently does not gate these register writes, so
disabled-write behavior still needs a physical PC-98 comparison. Likewise,
operation writes have a separate event output: a future datapath can resolve
the operation-write alignment-reset discrepancy without changing byte-lane
handling. Shift and length writes produce one reload pulse after updating the
registers, even when the I/O acknowledgement takes several cycles.

`tests/run-egc-registers.sh` connects the actual ao486 I/O bridge to this block.
It covers every port address for decoding, byte/word/DWORD writes including
odd addresses and both register-range boundaries, reads, held cycles, disabled
writes, mask protection, color expansion and reset. Negative controls target
upper-byte routing, strobe replay, enable/mask gating and address aliasing.
This block also remains outside the QSF and is not connected to the core.

The optional `CPU_AFFINE_RMW` generic in SDRAMC adds the memory-side operation
needed by the kernel. Its default is false. When enabled, a CPU four-plane RMW
can carry a 64-bit XOR coefficient mask and a mode bit alongside its existing
four base words. All 65 additional bits travel in the same held request bundle,
with the same source capture and memory admission as the address and byte/plane
enables. The merge is `base XOR (fresh_destination AND xor_mask)` per plane.
It uses the existing read/write burst and completion states. Other commands,
the drawing port and the ordinary GRCG OR merge retain their prior behavior.

`tests/run-egc-memory.sh` extends the actual SDRAM command-pin test with all
256 operations, sixteen plane masks and four byte masks, plus compatibility
requests while the generic is enabled. It changes live coefficients and mode
after source acceptance, injects the existing 15 ns payload transport bound,
checks fresh readback at ACK, and rejects OR merging, live-input bypasses and
an 80 ns late bundle. A command-level SDRAM source is used; physical timing
and end-to-end EGC graphics are still separate requirements. The normal core
does not enable this generic or connect the new programming registers yet.

The register, kernel and SDRAM tests passed on 2026-09-22. Register coverage
was 32,768 decoded addresses and 2,173 CPU I/O requests; all five negative
controls failed as intended. The memory test completed 30,848 requests across
20/50/60/90/100 MHz simulated CPU clocks and two clock phases, including the
full 16,384 operation/plane/byte combinations at 60 MHz. All four memory
negative controls were rejected. Existing CPU/drawing/floppy request-bundle,
readback, control-crossing, GRCG and actual top-level data-bus regressions also
passed. The log is `build/simulation-20260922-074716-2578fb/tests.log`.
These simulated clock rates do not establish FPGA operating frequencies.

## Word shifter

`pc98_egc_shift.sv` advances on one accepted 16-bit source transfer, after the
caller has selected either four VRAM words or replicated CPU write data. It
stores residual pixels for all four planes, skips the initial source offset,
inserts the destination offset and returns a native-order clipping mask.
When a full destination word cannot yet be formed, it preserves the pixels
and returns a zero write mask. The next source transfer supplies the missing
pixels. Length is the low twelve register bits plus one, including 4096.
Completing a row reinitializes input alignment but leaves its last result
latched for the destination write. Explicit reload discards an unfinished row.

Forward traversal is low-byte MSB to LSB, then high-byte MSB to LSB. Reverse
traversal is high-byte LSB to MSB, then low-byte LSB to MSB. This is the native
CPU representation, not MAME's internally bit-reversed VRAM representation.
The module requires aligned word source transfers. The bus integration must
explicitly handle byte/odd accesses; silently advancing an entire word for
every byte completion would be incorrect. Register selection, pattern latches,
read comparison and the memory handshake remain separate integration work.
This module is not yet in the QSF or active core.

`tests/run-egc-shift.sh` builds the extracted, unmodified NP2kai shift functions
under `tests/reference`, validates their outputs using an independent Python
pixel-list FIFO model, then feeds those same transactions to the RTL. It tests
all 512 direction/source/destination settings, lengths 1–33 and boundaries
63/64/65, 255/256/257 and 4095/4096, two rows without register reload, interrupted
rows, ignored register bits, idle cycles with changing source data, and reset
priority. It repeats the RTL corpus with programming performed through the
actual EGC register module and its registered reload pulse. Mutations remove
residual pixels, reverse the wrong bits, omit
clipping and disable row restart. These are word-shifter tests, not proof of
the complete EGC bus or physical PC-98 edge cases.

Reference evidence:

- The original [PC-9800 hardware databook](https://vtda.org/docs/computing/NEC/PC-9800TechnicalDataBookHARDWARE%2BOCR_1993.pdf),
  printed pages 193–194 (PDF pages 204–205), describes four-plane operation,
  source/destination read-modify-write, bit shifting and the protected extended
  mode switch. It does not specify the detailed shift/count register behavior.
- [ReC98's EGC copy research](https://rec98.nmlgc.net/blog/2023-03-05)
  describes the required extra source read when source offset exceeds
  destination offset and row-state restart. Its tests distinguish a real
  hardware-compatible implementation from T98-Next's differing behavior.
- The [register notes linked by ReC98](https://www.webtech.co.jp/company/doc/undocumented_mem/io_egc.txt)
  specify word accesses and shift/count fields. Some compare/mask statements
  conflict with both reference implementations and common driver setup; they
  are not treated as sole authority for those disputed fields.

The word-shifter regression passed on 2026-09-22 in
`build/simulation-20260922-084425-5d99d3/tests.log`: 685,216 source-word transfers
agreed between NP2 and the pixel-list model; 706,208 RTL records passed with
direct programming and again through the register frontend, with 21,840
idle/poison cycles in each run. All four mutations failed as intended.
That combined job subsequently stopped at an unrelated HDMI test expectation;
the corrected HDMI/memory tests passed in the separate `084726-ce7f8f` run.
