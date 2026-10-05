# Return a complete DWORD from buffered extended RAM

The extended-RAM bridge already fetches and retains 64 bits from DDR. The
legacy CPU memory bridge normally requests both 16-bit halves of a DWORD
separately, including an ACK-release interval between them. An aligned RAM
read can now return both halves on its first acknowledgement, using that
existing buffer. There is no new cache storage or DDR command.

The sideband carries only the upper 16 bits; the existing read bus supplies
the lower half. Address capability is separate from acknowledgement, and
the memory bridge consumes both halves only on ACK. This avoids a duplicate
low-halfword mux and keeps ACK out of the width-selection logic.

`EXT_RAM_DWORD_READ=0` on `pc98_ao486` selects the B243 path for comparison.
The memory bridge accepts the wider result only for a read starting at the
low halfword with both halfwords requested. Narrow reads keep the existing
omitted-halfword value. Writes, byte enables, MMIO and graphics retain their
existing transactions. Ordinary RAM boundaries are DWORD aligned; a burst
can change between the RAM and legacy paths at each DWORD. The RAM buffer
must be enabled. Native-RAM configurations disable it and retain their
previous behavior.

`tests/run-ram-dword-read.sh` checks masks, 1-8 DWORD bursts, both DDR halves,
RAM/aperture boundaries, delayed ACK release, byte-write coherence, concurrent
I/O and reset response draining. The independent byte-addressed model checks
each response and side effect. Negative controls reject missing write
coherence, incorrect buffer tags and swapped DWORD halves.

`tests/run-z486-ram-dword.sh` compares actual z486 execution at the B243
profile: PR2, 32/8 KB caches, native framebuffer only. All 84 cases pass,
including 52 stack-fault cases, other memory faults, self-modification and
CPU speed settings. The 64,000-byte RAM/framebuffer copy takes 285,685 to
252,086 clocks (11.76% fewer), and the whole fill/copy/readback workload
takes 1,019,724 to 986,124 clocks (3.29% fewer). Both execute 128,045
instructions and issue 72,000 DDR commands. The self-modifying-code stream
takes 402,942 to 365,271 clocks (9.35% fewer), with unchanged instruction
and DDR-command counts. These are simulation results, not Doom gains.

Forty differential 486 seeds of 1,200 blocks each pass with randomized
legacy-bus waits of 0-30 clocks. They access cached conventional RAM,
uncached upper RAM and a 16 KB DDR window. Every logged general register
and the 384 KB conventional-RAM dump matches Unicorn. Evidence:
`build/ram-dword/fuzz-verified.log` and `build/ram-dword/fuzz/`.

Hardware fit, timing and application qualification are pending. B243 remains
the released baseline. Local simulation evidence: `build/ram-dword/` and
`build/simulation-20261005-150210-fc9efb/`.

The first implementation (`a643666`) passes simulation and differential
testing but does not fit: 41,670 ALMs and 4,200 LABs versus 4,191 available,
at 90 MHz with B243's seed-6 profile. No RBF was produced. Its report is
`build/ram-dword/failed-fit.rpt`, build `quartus-20261005-151142-6ab9c1`.
The smaller sideband implementation passes the unit tests and all 84 CPU
cases again, with identical cycle/instruction/active counts in all 84 runs.
Its 40 randomized differential seeds also match Unicorn again.
Evidence for this revision is in `build/ram-dword-compact/` and
`build/simulation-20261005-153208-4cd138/`.
