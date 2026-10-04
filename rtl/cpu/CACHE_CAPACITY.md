# Optional 16 KB instruction cache

`scripts/build.ps1 -Cpu z486 -Z486ICacheKB 16` selects 256 sets instead of
128 in the existing four-way, 16-byte-line instruction cache. The default
remains 8 KB. The data cache, memory map, replacement policy and cache
coherence protocol are unchanged. No executable or game is identified.

The 8 KB fitted cache stores each 128-bit-wide data way in four M10K blocks,
with only 128 entries. A 256-entry way may fit in those same four blocks.
This is a resource-layout hypothesis until the 16 KB FPGA build finishes.
The existing physical-address tag and index calculations already support
this size; all index bits remain below the 4 KB page boundary.

`tests/run-z486-icache-capacity.sh` compares both sizes using the actual CPU
and PC-98 bridges. Its generated 12 KB instruction working set is warmed,
executed 32 times, then modified at two addresses and checked again. One
modification exercises the extra cache index bit. It also runs the existing
native execution/SMC, RAM/framebuffer, graphics and stack-allocation probes,
plus cache mapping and invalidation during outstanding fills. The cache
test explicitly checks invalidation in the upper half and final set.

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
