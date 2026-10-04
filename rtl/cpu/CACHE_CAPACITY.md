# Optional 16 KB L1 caches

`scripts/build.ps1 -Cpu z486 -Z486ICacheKB 16` selects 256 sets instead of
128 in the existing four-way, 16-byte-line instruction cache. The default
remains 8 KB. `-Z486DCacheKB 16` independently doubles the data cache. Its
default also remains 8 KB. The memory map, replacement policy and cache
coherence protocol are unchanged. No executable or game is identified.

The 8 KB fitted instruction cache stores each 128-bit-wide data way in four M10K blocks,
with only 128 entries. A 256-entry way may fit in those same four blocks.
This is a resource-layout hypothesis until the 16 KB FPGA build finishes.
The existing physical-address tag and index calculations already support
this size; all index bits remain below the 4 KB page boundary.

The data cache uses 32-bit-wide ways at a depth of 512 DWORDs. Doubling
that depth is expected to require eight additional M10K blocks across the
four ways. FPGA fitting must confirm both resource estimates.

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
FPGA fit, timing and a matched hardware Doom comparison are pending.

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
