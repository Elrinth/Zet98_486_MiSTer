# Prefetch queue RAM write control

The instruction queue retains its 16-entry logical capacity, immediate
empty-queue bypass, fault markers and original enqueue/dequeue decisions.
Its physical RAM now has 32 slots. Incoming data can be stored at the write
pointer before the late enqueue decision; only an accepted logical write
advances that pointer or makes the entry visible.

The pointer distance never exceeds 16 in a 32-slot ring. Consequently, the
write pointer always names free storage, including when the logical queue is
full. A rejected full write or consumed bypass can overwrite that free slot
without changing live queue contents. Removing the spare slots is unsafe.

This removes execute/decode backpressure from the MLAB's write-enable input.
An earlier 60 MHz fit's critical path ran from a code-segment-limit comparison
through execute readiness, decode acceptance and the bypass decision to that
input. Logical pointer/count updates remain timed; no clock exception or
extra instruction latency is introduced. The separate snoop FIFO uses the
original storage mode.

`tests/run-prefetch-store.sh` compares 10188 cycles with the original queue:
50 consumed bypasses, 1824 rejected full stores, 159 physical pointer wraps,
simultaneous full reads/writes, fault markers and resets. Removing the spare
address bit must fail the negative control. Intel's actual MLAB simulation
model is used. The full ao486 instruction and cache-coherency regressions
also pass, including DMA modification and self-modifying code.

With eight bus wait cycles, the cached ALU kernel remains 6361 cycles and
the VRAM-copy kernel 4543 cycles; enabling the 8 KB conventional-memory
cache gives 6393 and 3720 respectively. These match the current bridge
baseline. This change targets clock headroom, not fewer cycles per operation.
The full 60 MHz fit `quartus-20260921-123624-22e6a5` now passes CPU-internal
setup at +0.030 ns. Its new limiting CPU path is write-result to decoder count.
The complete design still fails 11 timing checks, worst -5.898 ns on CPU
write-data to SDRAM. It uses 34484 ALMs, 453 RAM blocks and 66 DSPs and was
not deployed. The next change separates the static graphics write set/mask
from the live memory-domain merge; see [SDRAM writes](SDRAM_WRITE_BUNDLE.md).
