# Optional larger L1 caches

`scripts/build.ps1 -Cpu z486 -Z486ICacheKB 16` selects 256 sets instead of
128 in the existing four-way, 16-byte-line instruction cache. The default
remains 8 KB. `-Z486DCacheKB 16` independently doubles the data cache. Its
default also remains 8 KB. The memory map, replacement policy and cache
coherence protocol are unchanged. No executable or game is identified.

The 8 KB fitted instruction cache stores each 128-bit-wide data way in four M10K blocks,
with only 128 entries. Fitting confirms that a 256-entry way uses those
same four blocks, doubling useful storage without another M10K.
The existing physical-address tag and index calculations already support
this size; all index bits remain below the 4 KB page boundary.

The data cache uses 32-bit-wide ways at a depth of 512 DWORDs. Doubling
that depth is expected to require eight additional M10K blocks across the
four ways. The combined-cache build must confirm that resource estimate.

`tests/run-z486-icache-capacity.sh` compares both sizes using the actual CPU
and PC-98 bridges. Its generated 12 KB instruction working set is warmed,
executed 32 times, then modified at two addresses and checked again. One
modification exercises the extra cache index bit. It also runs the existing
native execution/SMC, RAM/framebuffer, graphics and stack-allocation probes,
plus cache mapping and invalidation during outstanding fills. The cache
test explicitly checks invalidation in the upper half and final set.

`tests/run-z486-dcache-capacity.sh` compares 8/16 KB data caches with the
instruction cache fixed at 16 KB. Its 12 KB data working set contains
consecutive integers, with independently checked sums and a byte write in
the upper index range. The comparison scripts share
`tests/run-z486-cache-capacity.sh`; after warmup they require the larger
cache to eliminate external reads and complete the repeated workload faster.

Simulation results with early store completion and buffered RAM reads:

- Repeated 12 KB instruction routine: 1,074,856 to 116,299 cycles.
- External DDR commands during those repeats: 48,128 to zero.
- Whole instruction test including installation, warmup and SMC:
  1,247,166 to 228,428 cycles, with 84,244 issued instructions in both.
- The small-code RAM/framebuffer workload is essentially unchanged;
  the larger cache takes 128 extra clocks to initialize its valid bits.

This synthetic test deliberately exceeds the smaller cache. Its large
speedup demonstrates the capacity mechanism, not an application speedup.
A matched hardware Doom comparison is pending.

The data-capacity comparison, with 16 repeated reads of the 12 KB array,
reports 1,136,569 to 836,157 cycles (26.43% fewer) and 24,576 to zero DDR
commands during the measured phase. The complete test including setup and
the byte-write check takes 1,325,731 to 1,006,530 cycles; both configurations
issue 175,314 instructions. The streaming framebuffer workload exceeds both
cache sizes and remains at 1,053,086 cycles.

The complete memory-completion regression suite also accepts
`Z486_ICACHE_SET_BITS=8` and `Z486_DCACHE_SET_BITS=8`. With the instruction
cache enlarged, with both the original and enlarged data cache, it passes both
read-buffer modes, including 52 PUSH/CALL/ENTER fault cases, store/Jcc and
CMPXCHG/XADD faults, reset during a DDR read, all CPU speed settings and
memory-driver initialization at three placements.

Eight 486-enabled differential fuzz seeds (1–8, 1,200 blocks each) also pass
with both caches at 16 KB: all eight GPRs after each block and 384 KB of RAM
match Unicorn. This exposed an existing simulation assertion that rejected
a legal older-shift/younger-load writeback overlap. It also failed with the
B242 cache sizes and memory-completion settings. The datapath's existing
assignment priority produced the correct architectural result.

The simulation check now permits that overlap, excludes suppressed tokens,
and checks that an old stalled shift is suppressed after a younger load.
`deferred_shift_load_probe.asm` reproduces the old assertion with a shift,
frame-relative load and independent successor load. The corrected check
passes; a negative control that lets the older shift overwrite the newer
load fails the probe's independent value comparison. These assertion edits
are inside `synthesis translate_off` and do not change FPGA logic.

PCM86 format/FIFO/IRQ/refill/sample-rate tests and DMA terminal-count,
byte-pointer and ownership checks pass on this tree. Hardware listening is
separate from these simulation checks.

## Instruction-cache FPGA fit

The 90 MHz/64 MB, PR2, native-framebuffer-only, seed-12 build from `6cace92`
fits with 41,289/41,910 ALMs, 539/553 M10Ks and 50 DSPs. The read-buffer
candidate with the original 8 KB instruction cache uses 41,392 ALMs and
the same number of RAM blocks/DSPs. The RAM report confirms four M10Ks per
128-bit data way at a depth of 256, versus 128 previously.

Worst slack is -7.485 ns with ten negative timing checks: within the user's
12 ns allowance, but not timing closure. Pixel global-clock, fitted HPS
peripherals and SDRAM FEC route audits pass.

RBF `PC98_Z486_90_ICACHE16.rbf`: 4,604,368 bytes, SHA-256
`89214228e7e1f5ecab1bab2b36220473bb366e13eaac3531d9a00361fadcd2e8`.
Build evidence: `build/quartus-20261005-005846-153c0d/`.

## Experimental 32 KB instruction cache

`-Z486ICacheKB 32` selects 512 sets in the physically indexed instruction
cache. The data cache stays separately selectable at 8/16 KB; its preread
uses untranslated page-offset bits and is therefore limited to 16 KB.

The 32 KB option also places the two small replacement tables in MLABs,
reclaiming their two M10K blocks for instruction data. The attribute keeps
read-during-write semantics and does not specify `no_rw_check`. The FPGA
resource estimate for 32 KB instruction/8 KB data is 553 M10Ks; the physical
build must confirm fit and timing before hardware use.

`tests/run-z486-cache-capacity.sh instruction32` compares 16/32 KB with a
24 KB instruction routine and SMC in the new upper index range. Its measured
repeat phase changes from 2,142,706 to 231,499 cycles and 96,128 to zero DDR
commands. Both runs issue 168,244 instructions overall. This intentionally
cache-sensitive result is not a Doom measurement.

The 32/8 KB configuration also passes the complete memory-completion suite
in both read-buffer modes (52 stack-fault cases, other memory faults,
reset, CPU speeds and driver initialization), graphics, cache mapping and
invalidation, and eight differential 486 fuzz seeds of 1,200 blocks each.
FPGA and hardware qualification remain pending. Evidence is under
`build/icache32/`, including the exact hardware patch over `e570d00` used
by `build/quartus-20261005-015147-678804/`.
