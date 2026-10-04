# Complete stores after the final physical write

The z486 adapter waited for the whole fabric to become idle after each
store. The final memory write had already completed, but legacy ACK release
and bus-owner turnaround still held the CPU. This affects ordinary RAM,
graphics and other mapped writes, without depending on any application.

The memory bridge now reports a registered completion pulse after the last
selected halfword is acknowledged, or after the native DDR backend accepts
the write. z486 may proceed on this pulse. External bus ownership and I/O
ordering are unchanged, and the next external request still waits for ACK
release. The optional command-queue configuration retains idle-based
completion because a queue completion may belong to an older store.

This adds no posted-write buffer: all selected bytes reach their target
before CPU completion. `EARLY_WRITE_COMPLETE=0` selects the B242 behavior
for controlled comparisons.

## Simulation

`tests/run-write-completion.sh` checks byte masks, held ACKs, DDR stalls,
banked/linear aliases, reset draining and concurrent I/O. Independent memory
models verify that every selected byte is visible at completion. A mutation
that signals completion on the first halfword is rejected.

`tests/run-z486-write-completion.sh` compares the same real CPU programs with
completion disabled/enabled, using the B242 90 MHz configuration's pipeline
and native-framebuffer settings. It covers self-modifying RAM code, stack
allocation, graphics, store/Jcc faults, CMPXCHG/XADD faults, memory-driver
initialization, reset during a DDR read, all CPU speed settings and 26
PUSH/CALL/ENTER stack-fault cases.

The 64,000-byte fill/copy/readback workload reports:

- RAM fill with interleaved arithmetic: 280,090 to 240,100 cycles (14.28%
  fewer cycles).
- Copy from RAM to linear framebuffer: 347,284 to 330,485 cycles (4.84%
  fewer cycles).
- Whole workload: 1,132,151 to 1,075,357 cycles (5.02% fewer cycles).
- Both modes issue 128,045 instructions, charge 576,227 active execution
  cycles, and send 72,000 DDR commands. Only wait cycles are removed.

These are simulation results, not measured Doom FPS. FPGA fit, timing and
hardware application qualification are pending.
