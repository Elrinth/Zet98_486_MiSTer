# Return a complete DWORD from buffered extended RAM

Released as **B244**, asset `PC98_Z486_90_B244_20261005.rbf`. The release
uses the exact tested bitstream below; subsequent commits change documentation only.

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

The compact implementation at `5ffb5e0` fits at 90 MHz using B243's profile:
64 MB RAM, PR2, IC32/DC8, native framebuffer only, seed 6 and normal register
packing. Build `quartus-20261005-154022-8b90db` uses 41,077 ALMs, 4,186 of
4,191 LABs, 43,047 registers, 551 M10Ks and 50 DSPs. Worst slack is -7.175 ns
with ten negative timing checks, within the user's <12 ns magnitude allowance;
timing is not closed. Pixel-clock, HPS-peripheral and FEC-route audits pass.
The tested-source RBF is `build/ram-dword-compact/PC98_Z486_90_RAM_DWORD_COMPACT.rbf`,
SHA-256 `c9a44fc7d1d0296e06b2a1c6c921a2afad669071985693f3b66cdebee5b49731`.
Hardware uses OpenBIOS 2026-10-04.1 with the unchanged full-speed configuration.
Two fresh menu-first Linux boots pass six stack/page-fault probes and 200
traced BusyBox `ip` launches. Both trace logs contain exactly 100 normal
trace/exit pairs and no SIGSEGV. Evidence is `DwordLinuxCheck1.png`,
`DwordLinuxCheck2.png`, `DwordLinux1.log` and `DwordLinux2.log` under
`build/ram-dword/`.

DOS QUALIFY passes four division rounds, 4,008 string cases, 531 KB of
conventional RAM and 16,384 KB of XMS with zero errors. Two EXTBENCH runs
give 21,010/21,016 KB/s extended reads versus 18,772/18,767 for fresh B243
controls (about 12% faster), and 13,967/13,967 KB/s extended copies versus
13,095/13,098 (about 6.6% faster). Extended writes remain 26,818 KB/s.
XMS extended-to-conventional transfers rise from 14,106 to 15,492/15,491 KB/s.
Conventional-memory and conventional-to-extended rates remain essentially
unchanged. Screenshots: `DwordQualify.png`, `DwordExtbench1.png` and
`DwordExtbench2.png` under `build/ram-dword/`.

Doom `-timedemo demo1 -nosound -nomusic -nosfx` completes 11,520 game ticks
in **1,725/1,725 real ticks** on two fresh menu-first boots, versus **1,736**
for the same-session B243 control: **0.64% more throughput** at the same
90 MHz. Both final counters and returns to DOS were checked visually in
`DwordDoom1-end.png` and `DwordDoom2-end.png`. The monitored game intervals
are 723.53/723.44 seconds versus 726.39 seconds for the control. Those
intervals are approximate because the monitor polls every three seconds;
the game's final counters provide the relative comparison. These PC-98
counter values are not interpreted as absolute FPS. No new hardware
audio-listening result is claimed for this revision.
B243 is the comparison baseline.
Local simulation evidence: `build/ram-dword/` and
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
