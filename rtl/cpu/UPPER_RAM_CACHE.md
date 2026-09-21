# Upper conventional RAM instruction cache

`scripts/build.ps1 -Cpu ao486 -UpperRamICache` permits instruction caching in
80000h–9FFFFh while the PC-98 bank-89 register selects native conventional RAM
(08h or 09h). The option defaults off until FPGA timing and hardware tests are
complete. The low-memory data cache remains limited to addresses below 80000h.

This covers a real workload missed by the previous fixed 512 KB instruction
cache limit: a local Rusty reference trace executes its font conversion code
at CS=8BDEh, IP=4841h and above. Allowing that region to hit the existing L1
cache avoids repeated instruction fetches over the legacy 16-bit memory bus.
It does not change the clock frequency or establish a game frame-rate result.

`pc98_cache_policy.vhd` is instantiated by the top-level memory fabric. It
keeps low fixed RAM cacheable when bank 89 is remapped, while bypassing the
upper window. VRAM, ROM and all addresses from A0000h upward still bypass L1.
Bank writes at odd ports 0461h/0463h invalidate the cache and prefetch state.
DMA invalidation lasts through the entire memory ownership interval.

Native CPU stores use the existing physical-address snoop. Stores through a
banked window that alias cached low RAM invalidate globally; with the option
enabled, bank AB stores that alias currently cacheable upper RAM do too.
Changing bank 89 away from and back to native RAM also flushes, so intervening
writes cannot revive stale upper-window tags. Bank bit zero remains ignored,
matching the actual memory mapper. No cache data/tag capacity is added.

Verification commands, inside the `tests/Dockerfile.mixed` simulation
environment with Intel's local `altera_mf.v` model available:

```sh
bash tests/run-cache-map.sh
bash tests/run-upper-cache.sh
CACHE_CONFIGS=11 bash tests/run-cache.sh
```

The mapping test instantiates the real `memorymap.vhd`, compares all bank
values at 4 KB boundaries under 64 ROM/EMS/display settings, and repeats for
both cache-option values. A second real mapper independently decides whether
80000h maps to native RAM. It also checks reads, I/O, loader exclusion, DMA
ownership and bank control writes. A widened bank-decode negative control
must fail.

The full-CPU test translates the actual VHDL policy with GHDL and connects it
to ao486, its instruction cache, data cache and 16-bit bus adapters. It checks
native self-modification, bank-AB alias writes, a multi-cycle DMA update,
bank-89 remap/restore, ROM bypass and arithmetic checksums. Separate negative
controls disconnect alias, DMA and mapping invalidations. A loop at 90100h
compares cycles and external instruction reads with upper caching off/on;
the test requires both fewer cycles and at least ten times fewer upper RAM
fetches.

Simulation results: both mapping configurations pass 4,197,632 cases each,
plus the control/DMA cases, and the widened-decode negative control fails.
The full-CPU loop falls from 218,562 to 5,470 cycles and from 16,512 to 48
upper instruction bus reads. All coherence checks pass; disconnecting each
of alias, DMA and mapping invalidation causes the expected failure. The
existing lower-RAM cached ALU/VRAM/stack regression remains at
6,392/3,720/5,268 cycles and 17/162/145 transfers, including its DMA negative
control. These are synthetic simulation measurements, not Rusty frame rates.
FPGA timing and hardware validation of this option remain pending.

For a hardware comparison, assemble `tests/hardware/cpu_bench.asm` with
`nasm -f bin -DUPPER_CODE=1`. This relocates the existing arithmetic kernel
to 90000h, retains its checksum and ten-second measurement interval, and
labels the output accordingly. RAM-copy and stack kernels stay unchanged.
Run it only as the shell of a disposable DOS floppy without memory managers;
PSP ownership and program/stack placement guards reject unsafe allocations.
The build without this define remains byte-identical to the original low-code
benchmark (verified by assembling and comparing both source versions).

Hardware baseline, SuperStation One, FontMap50 (source 971ace7, 50 MHz),
2026-09-22: the relocated ALU kernel completes 5 blocks in 1,000 DOS-clock
hundredths; RAM copy completes 130 and stack 102 in their respective
1,000-hundredth intervals. All checksums pass. `Z98PERF.TXT` was recovered
from the diagnostic D88 after unloading the core and confirming the image
was closed. The returned D88 has SHA-256
`5311efcc98877916b921c2d55bb1a789c0e5527143fa3931381f60107d81b01d`.
Upper instruction caching is disabled in this baseline; a result from the
cache-enabled core is still required before claiming a hardware improvement.
