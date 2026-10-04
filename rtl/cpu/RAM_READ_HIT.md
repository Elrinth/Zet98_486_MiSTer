# Earlier completion of buffered RAM reads

The extended-RAM bridge keeps the last 64-bit DDR read. Previously each
subsequent halfword read from that word entered a registered ACK state
before returning already-resident data. An optional combinational hit now
returns the matching halfword in the request cycle. The bridge still latches
and holds the normal response until the request is released.

Misses and writes retain their existing protocol. Hits require an exact
physical tag, a mapped RAM address, a read request and the idle state. Reset
suppresses ACK immediately and invalidates the buffer. Accepted byte writes
still patch resident bytes after DDR acknowledgement. No new cache capacity,
memory mapping, instruction or application-specific behavior is introduced.

`EXT_RAM_EARLY_READ_HIT=0` on `pc98_ao486` selects the previous behavior;
the bridge's parameter is `EARLY_READ_HIT`. Full-native RAM configurations
disable this private read buffer and therefore cannot use the bypass.

`tests/run-extmem-bridge.sh` tests all four cache/bypass combinations,
request-cycle data/ACK, held responses, reset, RAM boundaries and byte-write
coherence. Negative controls reject missing write coherence and a missing
physical tag comparison. `tests/run-z486-read-hit.sh` uses the same real-CPU
regression suite as the store-completion comparison, with store completion
enabled in both read-bypass modes.

The real-CPU comparison passes native execution/self-modification, graphics,
stack allocation, memory initialization at three placements, store/Jcc and
CMPXCHG/XADD faults, all CPU speed settings, reset during DDR reads and 26
PUSH/CALL/ENTER fault cases per mode. Both sides use the store-completion
optimization from `STORE_COMPLETION.md`.

The 64,000-byte fill/copy/readback simulation reports:

- RAM fill: 240,100 cycles in both modes.
- RAM-to-linear-framebuffer copy: 330,485 to 308,087 cycles (6.78% fewer).
- Complete workload: 1,075,357 to 1,052,960 cycles (2.08% fewer).
- Both modes issue 128,045 instructions, charge 576,227 active execution
  cycles and send 72,000 DDR commands.

These are simulation measurements; the hardware results follow.

## Hardware qualification

The source-`33aa292` candidate uses the same 90 MHz/64 MB, PR2,
native-framebuffer-only configuration and OpenBIOS 2026-10-04.1 as the
store-completion baseline. Two EXTBENCH runs on each core give:

- Extended RAM reads: 17,095/17,104 to 18,451/18,439 KB/s (+7.87%).
- Extended RAM copies: 11,904/11,906 to 12,478/12,481 KB/s (+4.83%).
- XMS move extended to conventional: 12,790/12,790 to 13,595/13,599 KB/s
  (+6.31%).
- Write throughput and conventional-RAM operations remain effectively
  unchanged. Each measurement uses 120 video frames; rates are the existing
  benchmark's printed KB/s using 56.42 Hz.

QUALIFY passes four division rounds, 4,008 string cases and conventional/
16 MB XMS memory checks with zero failures. Linux passes three deterministic
stack page-fault probes and 100 traced BusyBox `ip` launches: 100 normal
exits, no SIGSEGV. The kernel's missing socket functionality is unchanged.
The first matched Doom run reports 11,520 game ticks in 1,809 real ticks,
versus 1,870/1,870 for B242 and 1,814/1,816 for store completion alone.
That is 3.37% more throughput than B242, and 0.33% above the mean of the
store-only runs. The final counters were checked visually in
`build/read-hit/RHDoom1-end.png`. This is one run of the read-buffer core;
the small incremental Doom gain should not be confused with its larger
memory-copy improvement.

The candidate fits at 41,392 ALMs, 539 M10Ks and 50 DSPs. Worst slack is
-7.367 ns with ten negative timing checks. This is within the user's
12 ns allowance, not timing closure. Pixel-clock, fitted HPS peripheral and
SDRAM FEC route audits pass.

RBF `PC98_Z486_90_READ_HIT.rbf`: 4,597,008 bytes, SHA-256
`5a36f0e644e2d6f77bcf25598435d4b8d9910a912e7b9726b3b104a4f4063a84`.
Raw results/captures are in `build/read-hit/hardware.json` and the adjacent
files; FPGA reports are in `build/quartus-20261005-004919-702867/`.
