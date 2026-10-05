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
that depth requires eight additional M10K blocks across the four ways,
confirmed by the combined 16/16 KB build: 547 M10Ks, 41,455 ALMs and 50 DSPs,
with -7.776 ns worst slack. That initial build predates the coherence fixes;
the corrected version still needs hardware qualification.
The initial combined-cache RBF panics during Linux boot too
(`build/dcache-capacity/Cache16LinuxBoot.png`); do not promote it.

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
Hardware results for the individual candidates follow below.

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

Eight 486-enabled differential fuzz seeds (1â€“8, 1,200 blocks each) also pass
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

This initial RBF passes two EXTBENCH runs and DOS QUALIFY, but Linux panics
during boot. The panic repeats without keyboard input and also at the
slower CPU setting. The same Linux disk boots on the read-buffer candidate
with the original caches. Do not treat this RBF as hardware-qualified.
The investigation and the coherence correction below require a new build.

## Instruction-cache fill/invalidation collision

A focused regression found an existing stale-code bug, also reproduced
against B242's original 8 KB instruction cache. A line fill and a CPU-store
or DMA snoop can need the same way's tag-RAM write port in the same cycle.
The old arbitration let the fill win on the assumption that replacing its
tag also invalidated the snooped line. That is false when their set indices
differ. If another snoop arrives immediately, the earlier address is lost
and the modified line can remain valid with old instruction bytes.

The cache now gives that invalidation priority and answers the outstanding
fetch without installing the conflicting fill's tag or data. Fills in a
different way still install normally. Tag snoop matches are qualified by
their valid pulse so old registered matches cannot repeatedly clear tags.

An adjacent read/write collision also returned stale code: a CPU tag read
sharing the edge that invalidates that entry captures its old valid bit.
By the following LOOKUP cycle, the registered snoop may be gone. A four-bit
mask now accompanies the synchronous tag read and excludes only the ways
invalidated on that edge. An unaffected way in the same set can still hit.

`tests/run-z486-icache-coherence.sh` checks all 48 combinations of 8/16/32 KB,
CPU/DMA snoops, conflicting/independent ways, fill/read collisions, and
whole-line/four-DWORD memory responses. It
checks modified code values, successful fill responses, retained independent
fills/hits, and hits after refetch. All pass. The fill test with B242's
8 KB cache returns the old
instruction word instead of the new value. Evidence is in
`build/icache-capacity/coherence*.log` and its `coherence/` directory.
Both DWORD-path collisions also reject B242 with stale instruction data;
the extended positive/negative results are under `build/icache-coherence/`
in `unit-both-paths.log` and `dword-negative.log`.

With both corrections (`8a2bda7`) and both caches at 16 KB, the complete memory suite
passes both read-buffer modes, including all 52 stack-fault cases, reset,
CPU speed settings and driver initialization. Eight differential fuzz
seeds also match all GPR records and 384 KB of RAM after 1,200 blocks each.
The final-source results are `build/icache-coherence/final-full-sim.log`
and `final-fuzz-verified.log`.

`smc_stream_probe.asm` adds 4,096 patched executions across 64 cached
routines at varied byte alignments. It checks DWORD and byte modifications,
including immediates crossing DWORD/cache-line boundaries, through direct
calls at varied distances from the store. Both the execution result and
backing memory must match. It passes on the corrected 16/16 KB CPU model
and is included in the memory-completion and capacity runners.

This proves the coherence bug and its directed correction; it does not yet
prove that the correction resolves the Linux boot panic. Hardware
qualification is still required.

The corrected 16/16 KB seed-12 build failed placement: it required 4,214
LABs, exceeding the device's 4,191, despite reporting 41,790 ALMs. It
produced no usable RBF. Seed-6 and seed-3 retries required 4,193 and 4,207
LABs respectively. All three exceeded 4,191 available LABs. The corrected
16/16 KB configuration is therefore set aside; retain the coherence fixes
when selecting a fitted candidate.

## Experimental 32 KB instruction cache

`-Z486ICacheKB 32` selects 512 sets in the physically indexed instruction
cache. The data cache stays separately selectable at 8/16 KB; its preread
uses untranslated page-offset bits and is therefore limited to 16 KB.

The 32 KB option also places the two small replacement tables in MLABs,
reclaiming their two M10K blocks for instruction data. The attribute keeps
read-during-write semantics and does not specify `no_rw_check`. The FPGA
32 KB instruction/8 KB data build fits in 549 M10Ks, 41,353 ALMs and 50 DSPs.
Each 512-entry data way uses seven M10Ks, leaving four device RAM blocks
unused. Worst slack is -7.573 ns, within the user's 12 ns allowance but
still negative. Pixel-clock, HPS peripheral and SDRAM FEC audits pass.

`tests/run-z486-cache-capacity.sh instruction32` compares 16/32 KB with a
24 KB instruction routine and SMC in the new upper index range. Its measured
repeat phase changes from 2,142,706 to 231,499 cycles and 96,128 to zero DDR
commands. Both runs issue 168,244 instructions overall. This intentionally
cache-sensitive result is not a Doom measurement.

The 32/8 KB configuration also passes the complete memory-completion suite
in both read-buffer modes (52 stack-fault cases, other memory faults,
reset, CPU speeds and driver initialization), graphics, cache mapping and
invalidation, and eight differential 486 fuzz seeds of 1,200 blocks each.
The initial RBF also passes DOS QUALIFY, three Linux stack-fault probes
and 100 traced BusyBox `ip` launches with normal exits and no SIGSEGVs.
Two matched Doom runs each complete 11,520 game ticks in 1,767 real ticks,
versus B242's 1,870/1,870 and the buffered-read core's 1,809/1,809. This is
5.83% more throughput than B242 and 2.38% over the buffered-read core;
the final counters were verified in `IC32Doom1-end.png` and
`IC32Doom2-end.png`. This RBF predates both
coherence fixes, so final qualification requires the corrected build.
Evidence is under
`build/icache32/`, including the exact hardware patch over `e570d00` used
by `build/quartus-20261005-015147-678804/`.

The corrected 32/8 KB source also passes both read-buffer modes of the
complete memory suite, including the SMC stream, and eight additional
486 differential fuzz seeds. All GPR records and 384 KB RAM match Unicorn.
Evidence: `build/icache32-coherent/full-sim.log` and
`fuzz-486-verified.log`. The retained fuzz runner accepts cache/pipeline
settings and saves them with its results in `profile.txt`.

The corrected 32/8 KB seed-12 attempt passed placement but did not finish
routing: the existing watchdog stopped it after 25 minutes without output
(exit 125). Diagnostics are saved in `build/icache32-coherent/watchdog/`;
there is no qualified RBF from that attempt. A seed-6 retry and a corrected
8/8 KB fallback are building with a bounded 45-minute silence allowance.

## Reducing instruction patch logic

The byte-enabled line patch helper now uses fixed byte lanes. Previously
it selected the old DWORD, merged its bytes, and inserted that DWORD back
into the 128-bit line. The equivalent fixed-lane expression avoids that
read/modify/insert selection logic. It changes no registers or cycles and
retains queued, registered and live store forwarding.

Isolated Quartus synthesis at 16 KB reports 2,729 to 1,426 combinational
ALUTs with both memory reply paths exposed. With whole-line inputs tied to
zero, matching `z486_pc98_adapter`, the count is 1,428 to 1,009. These are
component synthesis counts, not whole-core fitted ALMs or timing results.
The exact smaller-core fit still needs a new FPGA build.

`tests/run-z486-icache-byte-patch.sh` checks 1,152 cases: all 16 byte masks,
four destination DWORDs, queued/registered/live stores, both memory reply
paths and all three instruction-cache sizes. Its expected line comes from
an independent shifted-mask calculation with distinct source bytes. The
previous implementation also passes; a control that ignores byte enables
fails. The full memory suite and eight 486 fuzz seeds pass at both 32/8 KB
and 16/16 KB after the change. The 32/8 KB results have identical
cycle/instruction/active-cycle records in all
80 CPU cases compared with the previous implementation. Results are in
`build/icache-area/`.
