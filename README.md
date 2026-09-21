# Zet98-486 for MiSTer — experimental development

A PC-98 core development project based on **Puu's Zet/98**. The primary
acceptance target is smoother **Rusty** gameplay on MiSTer-compatible hardware,
initially a SuperStation One with SuperDock. A faster CPU must preserve game,
video, timer, sound and disk timing.

**The default build uses Zet; the optional ao486 integration is experimental.**
The ao486 DiskFix hardware test reaches DOS, displays Rusty's C-Lab logo
correctly and plays opening cutscenes with the user's BIOS/disks. The user
reports extremely poor performance on that uncached build. A new cached ao486
build passes the hardware arithmetic/RAM checksums and substantially improves
small-loop throughput at the same clock; Rusty gameplay speed remains unverified.
Earlier severe video corruption affected Console Mode too and cleared
after a full power cycle. The isolated DOS probe now reads both System and
Opening disks and persists its log to the host image. Rusty's cached-build
animation now looks somewhat better to the user; there is no measured gameplay
frame-rate or DX4-100 performance claim yet.
The newer 40 MHz ao486 test also passes two hardware benchmark runs, with
about 1.9x arithmetic and 1.8x RAM-copy throughput versus its matching 20 MHz
build. Full-design timing still fails; these measurements do not certify
gameplay stability. Optional extended RAM and 86 PCM playback are described in
[extended RAM](rtl/cpu/EXTENDED_RAM.md) and [PCM86](rtl/PCM86.md).
The source now fixes a truncated HPS disk acknowledgement that prevented
slots 1–3 from completing transfers. The regression reproduces the old failure
and passes with the fix. Hardware also requires waiting for image loading
before reset: a 60-second delay makes drive B accessible in the DOS probe,
where the earlier three-second delay did not. Rusty gameplay remains unverified.
Inherited RBFs are upstream artifacts, not releases of the new implementation.

## Priorities

1. Optimize Rusty gameplay with PC-9801-86 sound, preserving video, audio and
   disk timing. Increase CPU clock only with FPGA timing and hardware evidence.
2. Develop the ao486 integration toward a faster PC-9821-class machine, including
   extended RAM (16/64 MB), interrupts, DMA and BIOS support.
   Normal builds retain the lowest-1-MB map. An optional DDR-backed 16/64 MB
   map passes CPU simulation and physical-memory diagnostics on the SuperStation
   at both sizes. BIOS/XMS discovery remains required before DOS can use it
   normally. This does not establish complete PC-9821 compatibility.
3. Support raw PC-98 hard-disk images, including MiSTer-style `.vhd` files, with
   a working disk controller and BIOS path. Dynamic VHD/VHDX containers are a
   separate format and are not promised by a `.vhd` file selector.
   Provide a bootable, user-supplied DOS setup with documented CONFIG.SYS and
   AUTOEXEC.BAT settings for a multi-game disk.
4. Add the PC-98 MIDI interface used by games and route it through MiSTer MidiLink
   for local MUNT/FluidSynth synthesis and USB MIDI hardware. External MT32-pi
   support is a further option, not a requirement for listening to MIDI.
5. Keep full-screen scaling and provide an optional rotating floppy activity
   icon, enabled by default. Assess the SuperStation One optical drive as a
   later storage extension once its host interface is established.

## Current source and build

The imported baseline is `dentnz/Zet98_MiSTer` commit
`1efa2d5` (full upstream history retained). The MiSTer project is
`Zet98/v17/Zet98.qpf`, revision `release-Zet98MiSTer`, using Quartus Lite 17.0.
The internal core name remains `Zet98` during baseline work, preserving the
existing game-directory and settings identity. The GitHub repository name is
independent of that identifier.

With Docker Desktop running, from PowerShell:

```powershell
./scripts/build.ps1
```

The script uses the locally installed `theypsilon/quartus-lite-c5:17.0` image
by default. Override `-Image` and `-DockerContext` if needed. It compiles an
isolated source snapshot under `build/`, retaining the log and Quartus reports.
Compilation alone does not establish working hardware or acceptable timing.
After compilation, the script records the reported slack in `timing-results.json`
and exits with an error if any timing check reports negative slack. The RBF and
reports are retained for investigation. Missing timing results also fail the
build; nonnegative slack still requires constraint-coverage review.

The imported 20 MHz baseline completed Quartus compilation on 2026-09-20, using
49% of the FPGA ALMs, but **failed timing** (worst reported setup slack
`-22.563 ns`, plus unconstrained paths). Its generated RBF is not a verified
release. The timing failures must be understood before claiming stable higher
clock rates. `scripts/report-timing.tcl` generates detailed paths from a fitted
project for this investigation.

An experimental **40 MHz Zet** build can be prepared with
`./scripts/build.ps1 -SystemClockMHz 40`. It is an intermediate performance
experiment, not the 486 upgrade. The default remains 20 MHz. The 40 MHz build
adjusts the system-frequency parameter, PS/2 clock divider, OPNA clock enable,
and VFO interrupt pulse width; SDRAM and video clocks stay at 100 and 75 MHz.
It needs timing closure and hardware checks for boot, floppy access, music
pitch/tempo and Rusty gameplay before it can be recommended. A doubled clock
does not imply doubled frame rate. `-PrepareOnly` creates the source snapshot
without running Quartus.

The first 40 MHz experiment compiled on 2026-09-20 but **failed timing**. Its
CPU-only setup path has `-11.991 ns` slack at the slow 100 C corner, with a
system-clock Fmax estimate of `27.03 MHz` for same-clock paths. Increasing the
clock alone is therefore not a reliable 40 MHz solution. The 486 integration
remains the performance path; these measurements are not Rusty benchmarks.

Use `./scripts/build.ps1 -Cpu ao486` for the optional full CPU integration at
20 MHz. Its memory and I/O bridges now connect to the PC-98 fabric, with
independent even/odd I/O decoding and a separate interrupt-vector path. CPU-only
simulation passes 486 `BSWAP`, unaligned DWORD memory and I/O, `REP MOVSD`, A20
switching, reset-ROM aliases, interrupt/IRET, and software CPU reset. The existing
PC-98 PICs separately pass master/slave vector, masking and EOI tests.

The first complete ao486 build finished on 2026-09-21 (local time). It fits
with 32,397 / 41,910 ALMs (77%), 395 / 553 RAM blocks (71%), and 63 / 112 DSP
blocks (56%). CPU-register setup paths pass at 20 MHz with `20.482 ns` slack,
but the **complete design still fails timing**: 13 negative-slack checks,
worst `-22.188 ns`, including crossings between the system, SDRAM and video
clocks. Passing the CPU paths does not make this a timing-clean core or
establish a higher usable clock. The test RBF is for boot investigation only.

The source now removes a combinational feedback loop between the two PC-98
data-bus byte lanes. Device selection is resolved before DMA byte routing,
preserving the old priorities without routing final outputs back into each
other. Simulation matches the historical mux over 57,748 cases. The new fit
improves worst reported slack from -22.883 ns to -5.493 ns, but still fails
timing; the additional pixel-clock audit also finds violations. This is not
yet a clock-rate result. The bus rewrite is included in the newer Cache test
RBF; its full-design timing still fails at -5.704 ns, while CPU setup passes.

The default integration retains the existing low-1-MB memory map.
Unmapped addresses return `FFFF` and discard writes instead of aliasing low RAM.
CPU control ports F0/F2/F6 implement reset and A20 controls, using
[NP2kai's CPU I/O implementation](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/io/cpuio.c)
as a behavioral reference. Extended RAM, NMI, independent CPU clocking and
complete game compatibility remain work in progress. Cache is forced off in
the earlier DiskFix RBF. The newer Cache test RBF enables instruction caching for
fixed low RAM, with full invalidation for external DMA and aliased bank-window
writes. It also allows DMA to acquire an already idle CPU bus, which becomes
essential when the CPU executes cached code. Simulation passes, including
stale-code negative controls. The full FPGA build fits but still fails timing.
On the SuperStation One at 20 MHz, the new build passes both hardware benchmark
checksums and gives about 29x arithmetic-loop and 22x RAM-copy throughput versus
uncached ao486 at 20 MHz. These are small hot-loop results, not Rusty frame rates
or a comparison against the original Zet CPU. See the hardware notes for raw
counts, timing limits and the separate 66 MHz CPU feasibility result.
An uninterrupted hardware run now has user-confirmed improvement in Rusty's
animation ("a bit better"); acceptable gameplay speed is still unverified.
Further source changes separate CPU and DMA write data from unrelated
peripheral reads, reducing the I/O-only fit's worst reported timing failure to
-3.864 ns. The follow-up memory/FDC change passes simulation and is being built.

Run `./scripts/test.ps1` for simulation; see [tests/README.md](tests/README.md).
Hardware observations and the isolated test setup are recorded in
[HARDWARE_TESTING.md](HARDWARE_TESTING.md).

`Startup mute: 10s / Off` defaults to **10s** (status bit 4 clear). It silences
the PC-98 speaker for at least ten seconds after core start/reset, then restores
it when the speaker becomes inactive. An ongoing boot beep stays muted to its
end; later software tones are allowed. FM/PSG audio paths and mixer gain are
preserved. Select **Off**
to hear startup beeps immediately. This is a fixed timer, not BIOS-completion
detection; early software speaker tones within those ten seconds are also
muted. Earlier test RBFs use a fixed ten-second timer that can expose a long
beep's tail. The revised behavior passes simulation; hardware checks are pending.

`Floppy icon: On / Off` defaults to **On** (status bit 5 clear). A small rotating
floppy appears at the lower right during controller activity and floppy image
transfers, with a short hold for visibility. It follows the measured active
raster, leaves blanking/sync unchanged, and disappears when idle. This is new
source functionality, not present in the earlier Cache hardware test RBF.

The source now offers `Aspect ratio: Full Screen` through MiSTer's scaler.
The existing 4:3 and 16:9 setting values are preserved. This affects scaling,
not video synchronization; it does not claim to fix the observed frame glitches.
It is present in the newer DiskFix test RBF, but not the first ao486 image.

The newer experimental test build registers pixel data, blanking and sync together
with the MiSTer pixel enable. It also replaces the variable modulo in the text
font-address path with a scanline counter, verified for all 32 character heights.
`Video test: Color bars` supplies an independent 640x480 raster through the
same scaler/HDMI path (status bit 3). This helps distinguish PC-98 graphics
generation from output-path faults. These changes pass simulation; the hardware
glitch is not claimed fixed until retested.

## Credits and provenance

- **Puu / プー** — original Zet/98 PC-98 implementation and peripheral work.
  [Original development blog](https://fpga8801.seesaa.net/category/22270192-1.html).
- **dentnz** — [GitHub source import and MiSTer wrapper update](https://github.com/dentnz/Zet98_MiSTer).
- **Zeus Gómez Marmolejo and the Zet contributors** — original Zet CPU.
- **Alexey Melnikov / Sorgelig and MiSTer contributors** — MiSTer infrastructure.
- **Aleksander Osman and ao486/MiSTer contributors** —
  [ao486](https://github.com/MiSTer-devel/ao486_MiSTer), the replacement CPU.
- [X68000 for MiSTer](https://github.com/MiSTer-devel/X68000_MiSTer) and
  [MidiLink](https://github.com/MiSTer-devel/MidiLink_MiSTer) are storage/MIDI
  integration references; referenced features are not automatically implemented here.

This is an independently maintained derivative project, not an official release
by Puu or MiSTer-devel. Existing copyright and license notices remain in their
source files; this README does not replace or relicense those components.
Machine BIOS files and game images must be supplied separately.
