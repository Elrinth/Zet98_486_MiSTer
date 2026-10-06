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

- Integration of port 04A0hÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“04AFh writes, extended-video enable/protection and
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
at 04A0hÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“04AFh on the existing 16-bit, byte-selected bus. It stores both lanes
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
all 512 direction/source/destination settings, lengths 1ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“33 and boundaries
63/64/65, 255/256/257 and 4095/4096, two rows without register reload, interrupted
rows, ignored register bits, idle cycles with changing source data, and reset
priority. It repeats the RTL corpus with programming performed through the
actual EGC register module and its registered reload pulse. Mutations remove
residual pixels, reverse the wrong bits, omit
clipping and disable row restart. These are word-shifter tests, not proof of
the complete EGC bus or physical PC-98 edge cases.

Reference evidence:

- The original [PC-9800 hardware databook](https://vtda.org/docs/computing/NEC/PC-9800TechnicalDataBookHARDWARE%2BOCR_1993.pdf),
  printed pages 193ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“194 (PDF pages 204ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã¢â‚¬Å“205), describes four-plane operation,
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

## Write operand selection

`pc98_egc_write.sv` combines the programming fields, already-shifted source,
retained pattern and expanded colors with the raster kernel. It handles CPU
data, raster-operation and pattern-only write modes, plane/byte enables and
the intersection of pixel and shift masks. It returns the same held affine
coefficients consumed by the optional SDRAM merge. It remains outside the
active core: bus sequencing, source advancement and pattern latch updates
are still required.

When pattern loading is configured on a destination write and a color is not
selected, the pattern is the destination value immediately before the write.
The selector substitutes `P=D` into the operation table before computing its
coefficients. Therefore the memory controller's fresh RMW read supplies that
operand without an additional CPU read transaction or a stale CPU-side copy.
The caller must also retain the returned original destination in its pattern
latch on completion, including writes that mask every plane. The
`load_pattern_on_write` output identifies that obligation.

The ROP/read-load selection currently follows NP2: shifted source supplies P,
while pattern-only writes use the retained raw pattern. MAME uses raw pattern
for both, so this specific difference still needs a physical diagnostic.
Reserved write/load/color encodings report `configuration_valid=0` and return
coefficients that preserve VRAM. This is not a claim about undocumented
hardware behavior. The caller must handle invalid configurations explicitly.

`tests/run-egc-write.sh` executes the pinned NP2 `egc_opew` and operation table,
including its optimized operations, then checks the selector plus real raster
kernel against those results and an independent sum-of-products model. It
covers all 256 operations with every documented write mode, pattern load,
color choice and CPU-source bit, then all plane/byte masks with additional
shifted/clipped operands. For each case the destination is changed after
coefficient capture and compared again, testing independence from stale data.
The 17,280 cases and four mutations passed in
`build/simulation-20260922-090917-cca1f6/tests.log` (exit zero, no OOM, container
removed). Those results establish the selector's reference behavior, not
complete EGC support or game performance.

## Experimental word transaction engine

`pc98_egc_word_engine.sv` connects the register frontend, shifter and write
selector to the production SDRAMC's four-plane read and affine RMW ports.
It snapshots CPU metadata and operands once, holds memory requests through
completion, advances the source once per accepted source transfer, and waits
for the CPU strobe to be released before accepting another operation. Pattern
loading on a write retains the original destination returned by SDRAMC,
including when every destination plane is masked. CPU completion follows the
actual memory acknowledgement, not a guessed fixed latency.

This module is still outside the QSF and machine. It deliberately rejects
byte accesses and disabled/unsupported configurations with a fault response;
the machine integration must define how to expose unsupported requests.
Read selection follows NP2's native word path, while physical compare-mode
behavior and readback during a priming transfer remain unqualified. It assumes
shared global reset with SDRAMC. A separate CPU-only `soft_reset` now blocks
new requests, drains an accepted memory operation with its held operands, and
suppresses its CPU acknowledgement. Programming and retained graphics state
clear after the engine reaches idle. The machine must retain EGC ownership of
the memory port throughout this drain, even if CPU reset changes its enable or
arbitration signals. GRCG/EGC enable arbitration and the machine's CPU/DMA/drawing
routing remain unresolved integration requirements.

`tests/run-egc-engine.sh` synthesizes the actual VHDL SDRAMC with GHDL and
connects it to the SystemVerilog engine. A wiring-only Verilog adapter keeps
the bidirectional memory pins resolved correctly; GHDL 4.1 lost the external
input through a nested VHDL inout adapter. The command-level memory source
supplies distinct plane words and the checker inspects actual row/column,
bank, data and byte/plane-mask pins. This is not an SDRAM electrical model.
An independent pixel queue and Boolean raster model checks all 256 operations
and all 512 direction/source/destination alignments, two automatically
restarted rows, priming reads, masks and changing destinations. Live CPU
metadata is poisoned after acceptance and completed strobes are held to expose
replays. Existing pinned-NP2 shifter and operand tests remain separate oracles.

The final run `build/simulation-20260922-100453-fbe87e/tests.log` passed 8,676
transactions across 20/60/100 MHz and two memory phases. The full 6,976-case
matrix runs at 60 MHz; the other five combinations run 340 transactions each.
All four negative controls failed: stale retained pattern, repeated held
request, repeated source advancement, and early acknowledgement. Exit status
was zero, no OOM occurred, and the test container was removed. These simulated
clock rates do not qualify FPGA timing or establish an EGC game speedup.

The reset extension passed in
`build/simulation-20260922-103944-7a1309/tests.log`: 9,980 normal transactions
and 24 interrupted transactions across the same clock/phase matrix. The
interrupted cases cover reads and writes both before and after the physical
SDRAM read command. They check the complete pin-level transaction, suppressed
CPU completion, cleared programming/latches and a subsequent independent
request. Clearing state before the memory operation drains is rejected as a
fifth negative control. The regression also copies synthetic 640-pixel aligned
and 624-pixel shifted rows, checking forty source/destination word pairs and
automatic row restart. These are the transfer sizes observed in a local Rusty
driver; no game code or assets are included in the test.

## DSP shifter area reduction (2026-10-06)

The current machine instantiates `pc98_egc_word_engine.sv`, including this
shifter, and lists it in `Zet98/v17/release-Zet98MiSTer.qsf`. Earlier sections
record the integration state during the original bring-up.

The initial EGC-only 90 MHz candidate saved **231 ALMs and six LABs** versus B245 at the same
build profile: seed 6, PR2, IC32/DC8, 64 MB, normal register packing, raw IDE,
MIDI, PEGC and native-DDR framebuffer. Full fitting reports 41,149 ALMs and
4,185 LABs, versus 41,380 / 4,191. It uses 43,404 registers, 551 M10Ks and
66 of 112 DSP blocks. Worst slack improves from -7.354 to -6.845 ns. Ten
setup summaries remain negative; this meets the user's 12 ns allowance,
not static timing closure. Pixel-clock, HPS-peripheral and FEC route audits
pass. An earlier 100 MHz/seed 2 experiment also fit, but failed hardware boot and is
not a usable speed improvement. It occupies all 4,191 LABs with 41,116
placed ALMs (the separate "ALMs needed" estimate is 40,005), 551 M10Ks and
66 DSP blocks. Worst slack is -8.676 ns; Linux and DOS both stop at the
OpenBIOS banner. The detailed timing report shows an 18.243 ns decoder-to-
prefetch-window feedback path against a 10 ns period. This identifies a
timing bottleneck, but does not by itself prove the cause of the boot stall.
The existing NEC BIOS also fails to boot the 100 MHz RBF (blank screen),
while the identical BIOS and DOS disk reach the command prompt at 90 MHz.
A temporary diagnostic OpenBIOS reaches the disk-ROM boot-error message at
100 MHz and DOS at 90 MHz. No explicit 100 MHz limit was found in OpenBIOS;
the failure is not specific to it. The original OpenBIOS is restored after
these comparisons. No diagnostic firmware change is proposed for release.

### Arithmetic and resource tradeoff

Power-of-two multiplication implements the four planes' variable shifts in
spare DSP blocks. The source product's disjoint upper and lower halves form
a 16-bit rotation; a common 32-bit mask selects the appended source interval.
Output positioning takes the low half of another product. Two products per
plane extract residual pixels for the next transfer. The RTL adds no state
or cycles, and retains clock enables, clipping and traversal behavior.

For destination bit `j`, the original append source index is
`j - pending_count + source_skip`. Repeating the source word rotated left by
`(pending_count - source_skip) mod 16` supplies that index modulo 16. The mask
`(0x0000ffff >> source_skip) << pending_count` removes wrapped/discarded bits,
including for pending counts 16 through 31. For carry extraction, multiplying
by `2^(16-r)` exposes a word's right shift by `r` in the upper product half.
The 17-bit coefficient preserves `r=0`; the upper-word contribution is
suppressed when the full shift is 16 or more.

The `multstyle = "dsp"` attribute follows the
[Quartus inferred-multiplier documentation](https://docs.altera.com/r/docs/683283/18.1/quartus-prime-standard-edition-user-guide/multiplier-style-for-inferred-multipliers).
Synthesis reports confirm the requested mapping. Standalone Quartus 17
comparisons, all with 171 registers:

- Original shifter: 1,201 combinational ALUTs, no DSP blocks.
- Shared-mask alignment with LUT shifts: 1,075 ALUTs, no DSPs.
- DSP source rotation: 909 ALUTs, four DSPs.
- DSP rotation and output positioning: 784 ALUTs, eight DSPs.
- DSP rotation, positioning and carry extraction: 670 ALUTs, sixteen DSPs
  (531 fewer ALUTs, 44.2%).

The fitted shifter uses 436.2 ALMs versus 707.5 before. Whole-core savings are
smaller because placement and physical optimization also change other logic.
A preceding LUT-only EGC/prefetch experiment increased total fitted ALMs and
failed Linux/Doom hardware checks despite passing simulation. It was rejected;
the DSP build uses the original CPU RTL.

### Validation

`tests/egc_append_tb.sv` checks append, positioning and residual carry with
all alignment selectors, word/byte modes, both byte lanes and directions,
zero/every source basis bit, and empty/nonempty pending data: 139,264 cases
across four planes. Synthesis-excluded assertions compare the original shift
equations at each active transfer. The final DSP source passes both 732,800-
record NP2/pixel-list reference runs, 10,040 integrated SDRAM transactions
at 20/60/100 MHz and two phases, and all nine shifter/engine mutation controls.
Run `tests/run-egc-shift.sh` and `tests/run-egc-engine.sh` to reproduce them.

The DOS hardware probe `tests/hardware/egc_alignment.asm` uses `EGCVECT.BIN`
from `tests/hardware/egc_alignment_vectors.py`. Assemble it with NASM `-f bin`
as `EGCSHIFT.COM`, put both files on a disposable DOS disk, and run `EGCSHIFT`
from the text prompt. It overwrites small graphics-VRAM regions and leaves
EGC/GRCG disabled. Independent pixel FIFO lists supply the expected results.
Both B244 and the DSP candidate pass all 512 alignments/directions, two rows
without reload, varied pixel masks and 11,904 plane checks (`2E80h`).

With OpenBIOS 2026-10-06 (SHA256
`d318ff406d5ab76d306e84c415ab82971b4b83b132758e15cfa6e692dd9021ce`),
the 90 MHz candidate passes two fresh Linux boots, the stack page-fault probe
and 100 traced normal process exits per boot. DOS QUALIFY passes four division
rounds, 4,008 string cases, 531 KB conventional memory and 16 MB XMS. Two full
fresh-boot Doom demos each return to DOS with 11,520 game ticks / 1,724 real ticks,
exactly matching the repeated B244 control on the same BIOS/disk; the observer
measures 723.46 / 723.53 seconds from first game frame to completion. These
PC-98 counters establish relative performance, not absolute FPS.

The 90 MHz build is `quartus-20261006-153716-527ed6`, RBF SHA256
`3dd94342bc064a7e67a3f44d94e453ad79695cbf64b5418e74bc937a3f29fe7d`.
Detailed evidence is under `build/egc-dsp/`; component comparisons and rejected
experiments are under `build/egc-shift-area/` and `build/prefetch-area/`.

### Shared-mask follow-up and activity display

The common append mask now also uses a DSP multiplication. Both operands are
explicitly sixteen bits, avoiding an unnecessarily wide inferred multiplier.
Standalone mapping reports 631 ALUTs, 171 registers and seventeen DSP blocks:
570 fewer ALUTs (47.5%) than the original shifter, with no added cycles.

The updated shifter passes 139,264 append/position/carry cases, 131,072 clipping
masks, both 732,800-record reference modes, 10,040 integrated SDRAM transactions
at **20/60/90 MHz**, and all nine mutation controls. No further 100 MHz work is
planned. The simulation evidence is `simulation-20261006-182858-4c602c`.

The combined core also restores the compact disk activity display. Its full
resource totals and hardware qualification are tracked in
[`../STORAGE_ACTIVITY.md`](../STORAGE_ACTIVITY.md); the earlier 231-ALM/six-LAB
saving above describes the sixteen-DSP core without that display, not the
combined candidate.
