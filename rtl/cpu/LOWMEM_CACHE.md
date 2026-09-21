# Experimental conventional-RAM read cache

Add `-LowMemoryCache` to an ao486 build. This optional 8 KB direct-mapped
cache serves complete 16-bit reads from fixed RAM below 80000h. Each of its
4096 entries stores one word, physical tag and valid bit in synchronous FPGA
RAM. It is disabled by default during validation.

All writes reach the original bus and invalidate the corresponding slot.
DMA ownership and writes through banked aliases immediately disable hits and
start a background sweep of all valid bits. A
miss invalidated while outstanding cannot refill stale data. A hit invalidated
before acknowledgement falls back to the original bus. No dirty data exists.
ROM, I/O, VRAM and banked upper windows bypass this cache. Extended DDR uses
its separate read buffer. CPU-only reset clears cache state, retaining RAM.
The cache is a physical bus buffer independent of ao486's CR0 cache controls.

The sweep takes 4096 clocks (81.92 microseconds at 50 MHz), and also runs on
reset. During it, reads and writes continue through the original bus, with
no cache fills. It does not stall DMA or make the CPU wait for the sweep.
Repeated invalidation while clearing needs no restart because no new entries
can become valid. This avoids thousands of resettable validity registers.

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
protected-mode extended RAM. The first version with register-held validity
fits at 36964 ALMs (88%) and 438 RAM blocks. Its hardware DOS benchmark rises
from 98 to 119 RAM-copy blocks per ten seconds at 50 MHz, with unchanged
arithmetic (243 versus 244 blocks). It also passes the 64 MB HIMEMX diagnostic.
Pixel timing still fails. The RAM-held validity revision preserves the same
simulation kernel results and passes the CPU/memory regressions; its FPGA
fit and hardware tests remain pending.
