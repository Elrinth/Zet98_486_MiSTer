# Zet98-486 for MiSTer â€” experimental development

A PC-98 core development project based on **Puu's Zet/98**. The primary
acceptance target is smoother **Rusty** gameplay on MiSTer-compatible hardware,
initially a SuperStation One with SuperDock. A faster CPU must preserve game,
video, timer, sound and disk timing.

**Experimental: the default build still uses Zet.** The optional ao486 build
runs on the SuperStation One and has passed hardware CPU, 64 MB physical-memory,
XMS, disk and interrupt diagnostics at 50 MHz. Rusty reaches its title, intro
and first-stage graphics; Nightslave reaches its title menu. Gameplay frame
rate and audible music quality have not yet been measured. This is not a
complete PC-9821 implementation or a DX4/Pentium performance claim.

The current development features include:

- **ao486 and memory:** optional 16/64 MB DDR-backed RAM and a conventional-RAM
  cache. The 50 MHz hardware benchmark is about 2.31x faster for arithmetic and
  2.13x for RAM copy than the matching 20 MHz build. Actual XMS allocation,
  copy and free pass with both the limited and full-memory DOS profiles.
- **PC-9801-86 sound:** OPNA/FM plus experimental PCM/FIFO/IRQ support. A lost
  FM timer-clear write was fixed; Native50 and Bundle50 pass 100 consecutive
  timer-B IRQ12 deliveries and cascaded PIC EOI. These silent diagnostics do
  not certify musical timing or sound quality.
- **Hard disk:** a raw `.vhd`/`.img` controller and floppy-installed disk BIOS
  boot the owner's DOS 6.20 image. The optional bounded write BIOS persists
  DOS files, verified independently against the resulting FAT and data sectors.
  General geometry discovery and ROM-based HDD boot remain unfinished.
- **Display:** native-aspect fit, exact integer fit and HDMI-only integer crop,
  plus the supplied animated floppy indicator with D0/D1 captions. Hardware
  reports 1728x1080 fit, 1280x800 integer fit and a centered 1920x1080 crop.
  Standard 15 kHz SCART conversion is not implemented.

Recent 50 MHz complete builds have no negative slack in the reported timing
checks; SDRAM/HDMI board-I/O constraints remain incomplete. The 60 MHz builds
are still undergoing timing work and have not been deployed. The latest
50 MHz memory/video changes are being hardware-tested separately from the
verified Bundle50 fallback. See [hardware evidence and limitations](HARDWARE_TESTING.md).

An optional [MPU-PC98II UART prototype](rtl/midi/README.md), built with
`-MidiUart`, passes serial, bus and interrupt simulations. It is off by
default and does not yet implement intelligent-mode sequencing. Hardware
MidiLink playback and game MIDI compatibility remain unverified.

DOS, BIOS ROMs, games and prepared private disk packages are not distributed
in this repository. Complete MIDI/MPU-401, optical-drive support, native HDI mounting,
and native HDM/FDI/NFD selection are still pending. The import utility covers
standard images described below. Doom II boots in software emulation, but
its FPGA graphics are currently corrupt; it is not a supported playable title.

## Priorities

1. Optimize Rusty gameplay with PC-9801-86 sound, preserving video, audio and
   disk timing. Increase CPU clock only with FPGA timing and hardware evidence.
2. Develop the ao486 integration toward a faster PC-9821-class machine, including
   extended RAM (16/64 MB), interrupts, DMA and BIOS support.
   Normal builds retain the lowest-1-MB map. An optional DDR-backed 16/64 MB
   map passes CPU simulation and physical-memory diagnostics on the SuperStation
   at both sizes. The experimental [DOS memory setup](software/README.md) also
   passes hardware XMS allocation/copy/free tests at 16 and 64 MB. It requires
   an initializer and the PC-98 HIMEMX driver on the user's boot disk; it is
   not enabled by the original BIOS alone. This does not establish complete
   PC-9821 compatibility.
3. Support raw PC-98 hard-disk images, including MiSTer-style `.vhd` files, with
   a working disk controller and BIOS path. Dynamic VHD/VHDX containers are a
   separate format and are not promised by a `.vhd` file selector.
   Provide a bootable, user-supplied DOS setup with documented CONFIG.SYS and
   AUTOEXEC.BAT settings for a multi-game disk.
   The experimental [`-RawIde` controller](rtl/storage/README.md) now passes
   task-file and real HPS-interface simulations. Its
   [read BIOS prototype](software/DISK_BIOS.md) passes hardware geometry,
   partition, cylinder-crossing and 64 KB read checks against the private VHD.
   A BIOS-first diagnostic floppy now boots that VHD into DOS 6.20 on Native50
   and launches Rusty's illustrated intro. An optional bounded write BIOS
   passes sector-level hardware checks. Bundle50 also creates, flushes and
   reopens a 70,001-byte file on a separate game VHD; independent comparison
   verifies the data and limits all changes to that file's allocation and
   directory entry. ROM integration and general image/geometry discovery
   remain unfinished.
   A disposable hardware diagnostic passes IDENTIFY,
   sector write/read checksum and four IRQ9 deliveries; only the designated
   test sector changed in the returned image.
   A private DOS 6.20 image now boots Rusty, Nightslave and Doom II in a
   software PC-98 emulator. Its [configuration templates](disk-templates/dos620/README.md)
   provide memory profiles and a game launcher. Four FPGA-oriented profiles
   also boot on Bundle50; EMM386-based profiles remain software-emulator-only. An [import utility](scripts/import_disk_image.py) converts
   standard HDM/FDI/NFD-R0 floppies to D88 and 512-byte-sector HDI disks to raw
   images. Native selection of those additional container formats is pending.
4. Add the PC-98 MIDI interface used by games and route it through MiSTer MidiLink
   for local MUNT/FluidSynth synthesis and USB MIDI hardware. External MT32-pi
   support is a further option, not a requirement for listening to MIDI.
5. Keep full-screen scaling and provide an optional rotating floppy activity
   icon, enabled by default. Assess the SuperStation One optical drive as a
   later storage extension once its host interface is established.
   New [video options](VIDEO_OUTPUT.md) add HDMI integer scaling, capture the
   actual 400-line picture and show the supplied 59-frame disk animation with
   a D0/D1 label and cycling dots. The animation matches the imported frames in hardware captures. New
   native-aspect fit (default), exact integer fit and HDMI-only integer crop
   choices pass simulation and fit in Native50. Hardware confirms native fit
   at 1728x1080 and integer fit at 1280x800 on the 1080p test profile.
   Integer zoom reports a 640x360 crop into 1920x1080. Standard 15 kHz SCART scan conversion is not yet
   implemented.

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
Quartus runs on Docker's native Linux filesystem, with source copied in and the
complete project database/reports copied back. This avoids observed stalls on
Docker Desktop's Windows bind share. Failed exports retain the named container
for inspection. A post-fit guard also verifies global routing of the pixel clock.
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
project for this investigation. `./scripts/report-timing.ps1 -BuildDirectory
build/<snapshot>` runs that audit on native Linux storage and exports the
critical-path and CPU/system-clock reports back to the snapshot.

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

- **Puu / ãƒ—ãƒ¼** â€” original Zet/98 PC-98 implementation and peripheral work.
  [Original development blog](https://fpga8801.seesaa.net/category/22270192-1.html).
- **dentnz** â€” [GitHub source import and MiSTer wrapper update](https://github.com/dentnz/Zet98_MiSTer).
- **Zeus GÃ³mez Marmolejo and the Zet contributors** â€” original Zet CPU.
- **Alexey Melnikov / Sorgelig and MiSTer contributors** â€” MiSTer infrastructure.
- **Aleksander Osman and ao486/MiSTer contributors** â€”
  [ao486](https://github.com/MiSTer-devel/ao486_MiSTer), the replacement CPU.
- [X68000 for MiSTer](https://github.com/MiSTer-devel/X68000_MiSTer) and
  [MidiLink](https://github.com/MiSTer-devel/MidiLink_MiSTer) are storage/MIDI
  integration references; referenced features are not automatically implemented here.

This is an independently maintained derivative project, not an official release
by Puu or MiSTer-devel. Existing copyright and license notices remain in their
source files; this README does not replace or relicense those components.
Machine BIOS files and game images must be supplied separately.
