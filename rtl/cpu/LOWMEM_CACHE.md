# Experimental conventional-RAM read cache

Add `-LowMemoryCache` to an ao486 build. This optional 8 KB direct-mapped
cache serves complete 16-bit reads from fixed RAM below 80000h. Each of its
4096 entries stores one word and physical tag in synchronous FPGA RAM, with
separately cleared valid bits. It is disabled by default during validation.

All writes reach the original bus and invalidate the corresponding slot.
DMA ownership and writes through banked aliases clear every valid bit. A
miss invalidated while outstanding cannot refill stale data. A hit invalidated
before acknowledgement falls back to the original bus. No dirty data exists.
ROM, I/O, VRAM and banked upper windows bypass this cache. Extended DDR uses
its separate read buffer. CPU-only reset clears cache state, retaining RAM.
The cache is a physical bus buffer independent of ao486's CR0 cache controls.

The lookup adds two cycles to a low-memory read miss; warm reads avoid the
SDRAM round trip. In the actual-CPU simulation with eight added bus wait
cycles, instruction cache on, the VRAM-copy kernel changes from 5309 cycles /
289 legacy transfers to 4232 / 162 (about 25% higher throughput). The ALU loop
changes from 6361 / 17 to 6393 / 17 because its cold instruction fetches now
pass through this lookup. These are simulation kernels, not Rusty FPS.

The standalone test covers all slots, tag collisions, all write-byte masks,
uncached device accesses, delayed acknowledgement release, DMA flush during
hits/misses, mixed random operations and reset. Removing write invalidation
must fail its negative control. Full CPU tests cover DMA-modified code,
self-modifying code, uncached upper-window execution, interrupts, A20 and
protected-mode extended RAM. Fitting and hardware performance remain pending.
