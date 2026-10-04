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

The PCM86 FIFO, all sample rates, AVSDRV refill/acknowledgement, DMA terminal
count, byte-pointer and grant-ownership regressions also pass. These tests
do not substitute for listening to a game on hardware.

## Hardware comparison with B242

The candidate uses the same 90 MHz, 64 MB, PR2, native-framebuffer-only
configuration, OpenBIOS 2026-10-04.1 and MiSTer settings as B242. The core
source is commit `3bbef91cb7ef0bfbe66ff36a0531086229d89536`.

Two runs of the existing `tests/hardware/extbench.asm` benchmark on each
core measure 120 video frames per operation. The DOS/XMS driver and disk
are identical. Reported KB/s (first/second run):

- Extended RAM STOSD: 21,836/21,836 to 24,922/24,922 (+14.13%).
- Extended RAM MOVSD: 11,150/11,148 to 11,904/11,906 (+6.78%).
- Conventional RAM STOSD: 28,416/28,416 to 30,237/30,237 (+6.41%).
- Conventional RAM MOVSD: 6,288/6,288 to 6,452/6,452 (+2.61%).
- XMS driver move conventional to extended: 19,288/19,288 to
  21,734/21,734 (+12.68%).
- XMS driver move extended to conventional: 11,962/11,962 to
  12,790/12,790 (+6.92%).
- LODSD reads are effectively unchanged (less than 0.1% variation).

The gains above compare the means of the two runs. Absolute rates assume
the benchmark's 56.42 Hz refresh; comparisons use the same video mode.
These are memory benchmarks, not whole-application speedups.

Hardware `QUALIFY` passes four division rounds, 4,008 string-instruction
cases and the conventional/XMS memory check with zero failures. The Linux
stack page-fault probe passes three times. The 100-launch BusyBox `ip`
check reports 100 normal exits and zero SIGSEGVs. The supplied Linux
kernel's separate "socket: Function not implemented" result is unchanged.

The candidate fits at 41,353/41,910 ALMs, 539/553 M10K blocks and 50 DSPs.
B242 uses 41,286 ALMs with the same RAM/DSP counts. Worst slack is
-7.132 ns (B242: -7.303 ns), with ten negative timing checks. This meets
the user's less-than-12 ns allowance but is not timing closure. Pixel
global-clock, fitted HPS peripheral and SDRAM FEC route audits pass.

Candidate RBF: `PC98_Z486_90_WRITE_COMPLETE.rbf`, 4,601,608 bytes,
SHA-256 `b092e17f5031a8d0433b3c29aeb736e308641b75287c85b921b656ba2c48fbab`.

Two fresh B242 Doom runs both finish 11,520 game ticks in 1,870 real ticks,
using `doom -timedemo demo1 -nosound -nomusic -nosfx`. The candidate's one
matched run finishes in 1,814 real ticks: **3.09% higher throughput**
(`1870 / 1814 - 1`), or 2.99% less time. All final counters were verified
visually after return to DOS. No absolute FPS conversion is made from this
PC-98 port's timer counts. This measures the sound-disabled timedemo;
other application gains depend on their memory access patterns.

Local raw results and captures are retained in `build/write-completion/`:
`baseline-hardware.json`, `candidate-hardware.json`, the Doom first/final
frames and polling logs, two EXTBENCH captures per core, `WCFastQualify.png`,
`WCFastLinuxCheck.png` and `linux-100.log`. The Quartus evidence is in
`build/quartus-20261004-234408-9ef67d/`.
