# Native DDR memory path

This opt-in path preserves DWORD requests from the CPU through to DDR instead
of splitting them into two halfword handshakes. Enable it with
`scripts/build.ps1 -NativeDdr` in an ao486/z486 build with extended RAM.
The default remains the B240 memory path.

`-NativeDdr -NativeDdrFramebufferOnly -PackedGraphics` is a narrower
experimental configuration: ordinary RAM keeps the B240 halfword bridge and
its read buffer, while enabled linear PEGC aliases use native DWORDs. The
native backend then only needs a 19-bit framebuffer offset. This mode is
intended to isolate the graphics-copy optimization from native RAM routing.

The memory bridge selects the native backend only for an entire burst inside
extended RAM or an enabled linear PEGC framebuffer alias. Low RAM, ROM, MMIO,
banked graphics, unmapped addresses and bursts crossing an aperture boundary
continue through the legacy decoder. The 15–16 MB aperture remains excluded
from ordinary RAM. `00F00000h` and `FFF00000h` framebuffer aliases both reach
the existing `30F00000h` DDR backing.

A store becomes one 64-bit DDR command with four byte enables shifted into the
correct DWORD half. A read uses both DWORD halves of each fetched 64-bit word
when the requested burst includes them. CPU responses remain individual
DWORDs; no game, BIOS or instruction-set changes are required.
DDR reads enable all eight bytes, including the second DWORD reused by a
burst. CPU byte masks only restrict stores.

Stores still complete at DDR acceptance. The shared bus retains ownership
until the transfer finishes, so later I/O stays ordered. Accepted DDR reads
retain their response tag through CPU-only or global reset; canceled data
drains without completing a new request. When RAM uses native transfers, the
fallback extended-RAM read buffer is disabled because stores can bypass it.

## Validation

`tests/run-native-ddr.sh` checks all store byte masks, both DWORD halves,
bursts of 1–8 words, high/low graphics aliases, DDR stalls, zero-latency
responses, canceled writes, reset draining and RAM/graphics boundary
coherence through the actual router. `tests/run-z486-native-ddr.sh` runs
real z486 instructions with the B240 pipeline configuration, comparing the
old and new paths and testing a reboot during a pending DDR read.

The self-authored workload initializes a 64,000-byte source, copies it into
the framebuffer with `REP MOVSD`, then verifies every DWORD through the
high framebuffer alias. With the same modeled DDR waits and CPU instructions:

- Frame copy: 504,083 → 268,884 CPU clocks, 46.66% fewer clocks.
- Complete initialization/copy/readback workload: 1,479,353 → 1,013,753
  clocks, with 128,045 issued instructions in both runs.
- DDR commands for that complete workload: 104,000 → 56,000.

These are simulation measurements of memory transfers. They do not establish
Doom FPS or hardware timing. Hardware qualification results belong below.

## Hardware trial (2026-10-04)

The 90 MHz candidate fitted at 41,543/41,910 ALMs and 539/553 M10K blocks;
TimeQuest reported 10 negative checks with worst setup slack of -8.066 ns.
This is within the maintainer's 12 ns allowance, but is not timing closure.

On the MiSTer, the candidate was loaded with OpenBIOS 2026-10-04.1 and the
same cloned `DOOM_PERF_B240.vhd` used for the baseline. It stopped at the
MS-DOS startup banner: the disk's `Z98MEM`/AUTOEXEC confirmation and DOS
prompt did not appear, and keyboard commands did not advance it. The timedemo
therefore produced no gameplay frame or performance result. Reloading B240
with that disk reached the DOS prompt; its timedemo measured 852.77 seconds.
The candidate is not hardware-qualified and no Doom FPS improvement is
claimed. Keep `-NativeDdr` opt-in until this boot failure is resolved and the
same timedemo completes on hardware.

A follow-up with both `Z98MEM` and `HIMEM` removed from a disposable disk
clone also stopped at the DOS banner. This rules out those CONFIG.SYS
drivers as a prerequisite for the failure; its root cause is still unknown.

The follow-up decoder uses a four-bit burst-tail sum and aligned block
comparisons in place of the 33-bit end-address arithmetic. The regression
compares it with full-width interval arithmetic at every 512 KB boundary
throughout 4 GB, with all legal burst sizes, reads/writes and both graphics
mapping states (10,485,760 comparisons across the tested configurations).

With native transfers restricted to the framebuffer, the same simulated
copy takes 347,284 clocks versus 504,083 (31.11% fewer). The full workload
takes 1,132,151 clocks and 72,000 DDR commands. Native RAM execution, stack
allocation and all three RAM-initialization placements match the B240 path's
cycle and command counts. These are simulation figures; hardware results
for this narrower configuration follow.

## Framebuffer-only hardware candidate

The 90 MHz, pipeline-2, seed-12 build `quartus-20261004-204239-916e8c`
successfully fits at 41,372/41,910 ALMs and 539/553 M10K blocks, with 50 DSPs.
Worst slack is -6.908 ns across 10 negative checks, within the maintainer's
12 ns allowance. HPS peripheral placement, FEC routing and global pixel-clock
checks pass. The RBF SHA-256 is
`d18cd3ff64cdb956445af2a82bd683f01bb2be3675a71ed71e0e1b2d0afb119c`.

With OpenBIOS 2026-10-04.1 and the same Doom disk, this candidate reaches the
DOS prompt. Hardware QUALIFY passes the long-line check, four DIVTEST rounds,
4,008 STRTEST cases and MEMTEST (conventional RAM plus 16 MB XMS), with zero
failures. A fresh B240 timedemo completed 11,520 gametics in 852.25 wall-clock
seconds, consistent with the earlier 852.77-second run.

Both cores completed `doom -timedemo demo1 -nosound -nomusic -nosfx` after a
fresh boot, using the same `DOOM_PERF_B240.vhd`, OpenBIOS and 90 MHz clock.
The candidate returned cleanly to DOS with all 11,520 gametics complete:

- B240: 2,008 reported realtics.
- Framebuffer-only candidate: 1,872 reported realtics.
- Throughput increase by Doom's counter: 7.26% (6.77% less elapsed time).

The candidate screenshot monitor recorded a 783.15-second gameplay interval,
but its automatic end image caught the blank transition before the result
text appeared. That value is not a verified wall-clock completion time and
is excluded from the claimed gain. A separate end capture confirms the
11,520 / 1,872 result and DOS prompt. This is one matched timedemo comparison,
not a claim about every map or sound-enabled performance.

Local evidence is in `build/doom-perf/`: `b240-r5-end.png`,
`fb-only-verified-end.png`, `fb-only-qualify.png`, `fb-only-validation.json`
and `PC98_Z486_90_NATIVE_FB_20261004.rbf`. The full-native RAM configuration
remains unqualified; these results apply only to framebuffer-only mode.

## Native RAM with a two-clock store hold (B261)

The full-native RAM configuration (`-NativeDdr` without
`-NativeDdrFramebufferOnly`) was retried on the B260 sources in October 2026.
Each 32-bit store to extended RAM then costs one 64-bit DDR command instead of
two halfword handshakes (about 10 clocks), so the z486's 3-entry store queue no
longer stalls the pipeline (and instruction fetch) after CALL/PUSH bursts.

On hardware it failed as on 2026-10-04, but differently per placement. MS-DOS
rejected HIMEM.SYS ("bad or missing") while every file read back identically;
Doom (DX386) quit or hung in `R_Init`; a recorder build looped on invalid
opcodes at the DOS banner. Bisection builds (`ZET98_NATIVE_DDR_WRITES_ONLY` /
`_READS_ONLY` in `ao486_memory_bridge.sv`) showed native reads alone are
fine and native stores are the trigger. Holding the store's completion pulse
for `ZET98_NATIVE_WRITE_HOLD` clocks after DDR acceptance fixes it: 6 and 2
both pass. The cause is not known; no simulation reproduced it, including
randomized DDR busy/latency, PEGC scan-out contention, IRQs, paging and the
hardware test programs below. The Cyclone V HPS manual guarantees in-order
execution for overlapping accesses on one FPGA-to-SDRAM port.

Released configuration: `-NativeDdr -NativeDdrWriteHold 2 -PackedGraphics`
(90 MHz, pipeline 2). Seed 3: 41,188 ALMs, worst slack -7.048 ns. Seed 7:
41,258 ALMs, -7.183 ns. Both boot DOS with HIMEM (30,720 KB XMS), pass QUALIFY
including the 16 MB XMS MEMTEST, and run the Doom timedemo; seed 3 also passes
EXTTEST with its interrupt pass and boots Windows 95 to the desktop.

- Doom `-timedemo demo1 -nosound -nomusic -nosfx` (DOOM.vhd, small view):
  B260 801 realtics, B261 seed 3 767 realtics (4.4% faster).
- Dhrystone relinked into extended RAM on the PC-98 testbench
  (`z486_xms_resident_tb`): 550k cycles (halfword RAM path), 443k (native,
  no hold), 452k (native, hold 2).

Hardware test programs (tests/hardware, assemble with NASM, run from DOS):
`exttest98.asm` (1-64 MB stores/copies/code execution, plain, paged and with
IRQ0 at about 600 Hz; stays above the HMA), `extmix98.asm` (4000 real/protected
mode round trips copying conventional <-> extended memory), `a20test98.asm`,
`int1ftest98.asm` (INT 1Fh AH=90h block moves), `crcf98.asm` (file checksum)
and `memsize98.asm` (BIOS memory-size bytes). `irqext_probe.asm` is the
simulation counterpart for `z486_xms_resident_tb` with `PIT_PM_TEST=1`.

## Two-beat line fills (B262)

`pc98_native_ddr_bridge` turns an aligned four-DWORD read (a 16-byte cache
line fill) into one DDR command with burstcount 2. The second 64-bit beat is
held in a register while the first beat's DWORDs are returned; a beat counter
keeps the bridge busy until every accepted beat has drained (also across a
CPU-only reset). `pc98_ao486` keeps the RAM response tag until the last beat
(`ram_read_left`), and the PEGC arbiter passes the RAM burst length through
(it already counted burst beats for video scan-out). Other reads keep the
one-word path.

EXTBENCH on hardware (B261 -> B262): extended LODSD 22,776 -> 28,078 KB/s,
REP MOVSD 18,851 -> 23,986 KB/s, XMS move ext->conv 16,224 -> 19,718 KB/s.
Doom timedemo 767 -> 726 realtics. Tests: `tests/run-native-ddr.sh` (bridge
at latencies 0/1/7/37 incl. a reset during a line fill; router with two-beat
responses), z486 native/write-completion suites, and 10 fuzz seeds with random
DDR timing and PEGC scan-out contention.
