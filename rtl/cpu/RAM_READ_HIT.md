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

These are simulation measurements. FPGA/hardware qualification is pending.
