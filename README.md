# Zet98-486 for MiSTer — experimental development

A PC-98 core development project based on **Puu's Zet/98**. The primary
acceptance target is smoother **Rusty** gameplay on MiSTer-compatible hardware,
initially a SuperStation One with SuperDock. A faster CPU must preserve game,
video, timer, sound and disk timing.

**This is currently a Zet-based development baseline, not a working 486 core.**
The name describes the intended upgrade. No DX4-100 performance claim is made.
Inherited RBFs are upstream artifacts, not releases of the new implementation.

## Priorities

1. Reproduce the original build and measure Rusty slowdowns with the same BIOS,
   disk image and gameplay scene on real hardware.
2. Integrate the ao486 CPU with PC-98 I/O byte lanes, memory transfers, interrupts,
   DMA, reset behavior and BIOS mapping; retain a baseline for comparison.
3. Support raw PC-98 hard-disk images, including MiSTer-style `.vhd` files, with
   a working disk controller and BIOS path. Dynamic VHD/VHDX containers are a
   separate format and are not promised by a `.vhd` file selector.
4. Add the PC-98 MIDI interface used by games and route it through MiSTer MidiLink
   for local MUNT/FluidSynth synthesis and USB MIDI hardware. External MT32-pi
   support is a further option, not a requirement for listening to MIDI.
5. Improve display scaling, including a full-screen option.

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

For CPU adapter simulation, see [tests/README.md](tests/README.md).

## Credits and provenance

- **Puu / プー** — original Zet/98 PC-98 implementation and peripheral work.
  [Original development blog](https://fpga8801.seesaa.net/category/22270192-1.html).
- **dentnz** — [GitHub source import and MiSTer wrapper update](https://github.com/dentnz/Zet98_MiSTer).
- **Zeus Gómez Marmolejo and the Zet contributors** — original Zet CPU.
- **Alexey Melnikov / Sorgelig and MiSTer contributors** — MiSTer infrastructure.
- **Aleksander Osman and ao486/MiSTer contributors** —
  [ao486](https://github.com/MiSTer-devel/ao486_MiSTer), the planned CPU foundation.
- [X68000 for MiSTer](https://github.com/MiSTer-devel/X68000_MiSTer) and
  [MidiLink](https://github.com/MiSTer-devel/MidiLink_MiSTer) are storage/MIDI
  integration references; referenced features are not automatically implemented here.

This is an independently maintained derivative project, not an official release
by Puu or MiSTer-devel. Existing copyright and license notices remain in their
source files; this README does not replace or relicense those components.
Machine BIOS files and game images must be supplied separately.
