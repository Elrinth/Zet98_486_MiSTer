# Experimental conventional-RAM read cache

Add `-LowMemoryCache` to an ao486 build. This optional 8 KB direct-mapped
cache serves complete 16-bit reads from fixed RAM below 80000h. Each of its
4096 entries stores one word, physical tag and valid bit in synchronous FPGA
RAM. It is disabled by default during validation. Experimental
`-LowMemoryCacheKB 32` and `-LowMemoryCacheKB 64` sizes retain the same mapping
and coherence rules; 8 KB remains the default when enabled.

All writes reach the original bus. Once a full-word write is acknowledged,
its address, tag and both bytes fill the corresponding cache slot. Partial
and zero-byte writes invalidate the slot because the untouched byte is not
known. No entry is filled before the legacy write completes or while
invalidation/clearing is active. This lets a following stack or data read
reuse the completed word without another SDRAM access.
DMA ownership and writes through banked aliases immediately disable hits and
start a background sweep of all valid bits. A
miss invalidated while outstanding cannot refill stale data. A hit invalidated
before acknowledgement falls back to the original bus. No dirty data exists.
ROM, I/O, VRAM and banked upper windows bypass this cache. Extended DDR uses
its separate read buffer. CPU-only reset clears cache state, retaining RAM.
The cache is a physical bus buffer independent of ao486's CR0 cache controls.

The sweep takes one clock per word: 4096 clocks (81.92 microseconds at 50 MHz)
for 8 KB, 16384 for 32 KB, and 32768 (655.36 microseconds) for 64 KB. It also
runs on reset. During it, reads and writes continue through the original bus, with
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
simulation kernel results. The compact 8 KB version fits in 33348 ALMs and
438 RAM blocks, then repeats ALU 244 / RAM-copy 119 blocks on hardware. Its
64 MB HIMEMX and silent PCM86/IRQ tests also pass, with remaining video timing
violations.

Standalone regressions cover every slot at 8/32/64 KB, including full-capacity
warm reads, complete flushes, byte writes and in-flight invalidation. The real
CPU/coherence regression also passes at 64 KB. Its tiny VRAM kernel runs while
the larger cache's post-DMA clear is still in progress, so that result is a
correctness check, not a warmed-cache performance comparison. A 64 KB FPGA fit
completes in `quartus-20260921-073124-f4b543`: 33226 ALMs and 503/553 RAM
blocks. Hardware gives ALU 246 / RAM copy 121 blocks, exactly matching the
8 KB version with the same pixel-clock changes. This benchmark demonstrates
no benefit from 64 KB; 8 KB remains the baseline. Timing still fails two
checks, worst -0.164 ns. Rusty gameplay benefit from 64 KB remains unmeasured.

## Completed-word write allocation

The standalone 8/32/64 KB tests pass with write allocation, including all
byte masks, cold-word allocation, tag collisions, all-slot flushes, delayed
ACK release, in-flight invalidation and 3000 mixed random sequences per size.
Disabling partial-write invalidation still fails with stale data.

The actual ao486 CPU passes DMA/code coherence, upper-window bypass and a
new 128-iteration push/pop kernel that checks every returned value and the
final stack pointer. With the instruction cache and 8 KB data cache enabled,
and eight external bus wait cycles, the previous cache takes 6420 cycles /
273 transfers; write allocation takes 5268 / 145. This is 17.9% fewer cycles
(21.9% greater throughput) for that kernel. The matching ALU and VRAM kernels
remain 6392 / 17 and 3720 / 162. These compare otherwise identical current
CPU sources. They are simulation results, not Rusty FPS or hardware results.
The full CPU sweep also passes with both caches disabled and with only the
instruction cache enabled, including the same stack and coherence checks.
The new allocation policy still needs full FPGA timing and hardware tests.
