# Hardware testing

Test device: SuperStation One with SuperDock and 128 MB SDRAM. The initial
test system uses ConsoleMode's MiSTer executable (ConsoleMode 1.1.4.2).
The TV is connected by HDMI through a switch box. Console Mode output with HDR
was initially stable, later also glitched, and recovered after the user powered
the equipment fully off and on. Keep the recovered display as the control
during core video debugging. The inspected profiles use `direct_video=0`, `video_mode=0`
and `vsync_adjust=0`; the main profile has `hdr=1`.
No credentials, machine BIOS, game images or private screenshots belong in Git.

## Isolated baseline

Use a separate `games/Zet98_Test/` folder and `config/Zet98_Test.CFG`.
An MGL launcher with `<setname>Zet98_Test</setname>` makes MiSTer use this
folder and configuration without replacing the normal Zet98 installation.
For example, using the repository's unmodified upstream 2022 RBF:

```xml
<mistergamedescription>
  <rbf>_Computer/_Zet98_Test/Zet98_Upstream2022</rbf>
  <setname>Zet98_Test</setname>
  <file delay="2" type="s" index="0" path="rusty-system.d88" />
  <file delay="2" type="s" index="1" path="rusty-opening.d88" />
  <reset delay="3" hold="1" />
</mistergamedescription>
```

Supply `boot.rom` in that game folder. Use copies of the disks, since the core
can write to mounted images. The existing 2021 RBF and normal `games/Zet98/`
files remain intact. MGL syntax and folder behavior were checked against
MiSTer Main's MGL parser and `user_io` implementation.

Rusty's system disk displays an MS-DOS 3.30D banner and a Japanese warning
when the GDC graphics clock is configured as 5 MHz. It requests **2.5 MHz**
and a restart (DIP SW2-8 off). In this core's OSD, select `DIP2-8 GDC clock:
2.5MHz`; the corresponding MiSTer status bit is 22. This graphics-controller
setting is separate from the CPU clock being upgraded.

## Observations, 2026-09-21

- The user-supplied development ROM reaches MS-DOS with Rusty's system disk.
  User photos establish this; initial remote captures did not establish boot.
- After setting GDC to 2.5 MHz, the user heard Rusty's startup audio. The game
  requested System Disk plus Opening Disk; the test launcher was corrected
  to mount that pair. This establishes loader progress, not full gameplay.
- The displayed text intermittently shifts/overlaps, and a photograph shows
  a mostly white frame. Cause is not yet established. These observations
  precede deployment of the ao486 test RBF.
- The original 2021 core initially produced a black remote screenshot.
  Subsequent MGL tests produced no screenshot file; the documented scaler
  header at physical address `0x20000000` read as all `FF` on the 2022
  reference test. Remote screenshot failure must not be interpreted as a
  black physical display.
- The installed downloader-generated ROM and the known-working development
  ROM both have the expected 550,912-byte length, repeated final 32 KiB BIOS
  bank, and 128 KiB zero padding. Their BIOS/font contents differ. Layout
  checks do not establish compatibility of the downloader ROM.

Local ROM fingerprints, for reproducing this comparison without distributing
the files:

- Known-working development ROM SHA-256:
  `647b5fa95a1a55096728829b74d4729e45adfd49d8e3a86aabf486a042f21db7`
- Existing installed ROM SHA-256:
  `4ba8a89bca02acd634a1df424dce28f16556e3632259e2e8c8769252b9533c8b`

## First ao486 build

Local snapshot: `build/quartus-20260920-235936-1cbf34/source`.
Quartus Lite 17.0 completed compilation in 25m16s. The build driver correctly
rejected the result because timing checks failed; see the README for resource
and timing figures. The RBF SHA-256 is
`7dab7fcba85690878b104bef9cf2888329ee7e9b348dcd4b697e8351cf7b1e3c`.

The test image was uploaded under the separate name
`_Computer/_Zet98_Test/Zet98_486_20260921_test.rbf`; its device checksum matched.
SSH confirmed the running image and mounted System/Opening disk files.
The user then supplied photos of DOS sound-driver initialization and the
C-Lab logo, and confirmed the logo on screen. This is the first ao486 hardware
boot milestone. Severe horizontal corruption and white frames persisted.
The loader subsequently showed a file-not-found prompt asking for System and
Opening disks despite both files being open in MiSTer; that remains unresolved.

### Power-cycle recovery

The user subsequently reported that corruption persisted after returning to
Console Mode. Fully powering the equipment off and on restored the display.
This demonstrates recovery without deploying a new RBF, but does not identify
which device retained the bad state or which operation triggered it. Previous
warm-load comparisons alone cannot establish a PC-98 rendering defect.
Read-only SSH inspection after this report confirmed a fresh system uptime,
Console Mode running, no mounted test disks, and the preserved GDC 2.5 MHz
configuration. The unchanged upstream 2022 reference was then reloaded with
the same ROM and System/Opening disks, confirmed open through SSH. A screenshot
file could be saved again, but contains only black pixels; this remains
insufficient evidence about the TV picture. The user then confirmed stable
positioning, with a readable file-not-found prompt. The startup sound was heard,
but the logo interval appeared white, so graphics correctness is unresolved.

First retest the already-deployed PC-98 images against the recovered control.
Record whether corruption begins when entering PC-98 and whether it persists
after returning to Console Mode. Do not attribute the recovery to source
changes that have not been loaded.

### Optional video diagnostic

The prepared diagnostic build uses Zet to isolate video changes. It includes a
registered video-output stage, a cheaper text scanline calculation, and OSD
`Video test: Color bars` (status bit 3). The pattern bypasses PC-98 text,
graphics and SDRAM fetches, but uses the same video PLL, scaler and HDMI path.
It runs without waiting for the PC-98 BIOS. Full-screen scaling is also present
in that source. Hardware results are pending; deployment was held after the
power-cycle recovery so the existing images can be compared first.
The first video-test snapshot is `build/quartus-20260921-004058-4b8287/source`.
Compilation finished with 20,358 / 41,910 ALMs (49%), 380 / 553 RAM blocks,
and 61 / 112 DSP blocks. Timing failed: 11 negative-slack checks, worst
`-25.828 ns`. The detailed report's worst path crosses from the Zet CPU to
SDRAM write data; CPU-register setup paths alone pass with `8.148 ns` slack.
This RBF has not been deployed and is not a verified release.

### DOS disk probe

`tests/hardware/disk_probe.asm` is an 8086-compatible DOS shell diagnostic.
Assemble it with NASM `-f bin`, then use `scripts/d88_file.py` to replace
`BOOT.COM` in a **new copy** of the supplied system D88. The replacement must
fit the old file length. The tool preserves the FAT, directory entry, sector
metadata and all unrelated payloads, and refuses to overwrite an output file.
No supplied disk or BIOS is distributed with this program.

The first probe ran on the unchanged 2022 reference with System on FDD0 and
Opening on FDD1. The user supplied a clear, stable photograph showing:

- Default DOS drive A; `A:\SYS_DISK` opens and reads `0D 0A 1A`.
- `A:\OP_DISK` and `A:\MGXLOAD.BIN` return DOS error `0002` (file not found),
  expected for the System disk.
- All three corresponding paths on B return `0003` (path not found).
- The probe reports completing its log write, but the retrieved D88 contains
  no log file. Host-image write persistence is not established.

Version 2 adds the BIOS drive mask at `0000:055C`, DOS drive count, and a B:
free-space query. A trial launcher mounted Opening first, waited eight seconds,
mounted System, then waited another eight seconds before reset. The user
reported a black screen and constant beep rather than diagnostic output.
The test was immediately stopped by returning to Console Mode. This trial
changed both the probe and mount order, so it does not isolate which caused
the failure. Use the earlier System-first order for subsequent probe comparisons.

### Startup speaker mute

The user requested quiet startup while retaining later PC-speaker sound.
`Startup mute: 10s / Off` now defaults to ten seconds after core start/reset.
Only the beeper input to the audio mixer is gated; FM/PSG paths and PIT operation
are unchanged. The timer continues while bypassed and saturates after expiry,
so later menu changes do not restart it. Simulation passed exact duration,
automatic restoration, reset, bypass, and saturation checks.
Quartus Analysis & Elaboration also passed for the ao486 source snapshot
`build/quartus-20260921-011511-1dccf1/source` (0 errors). The feature is now in
the DiskFix test RBF described below. Audible hardware confirmation is pending.

### Per-drive HPS acknowledgement fix

Source inspection found that `hps_io` returns four acknowledgement bits, but
the wrapper connected them to a scalar wire. Only slot 0 reached the disk
engine; slots 1ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ3 could never complete their host transfers. The disk engine
serializes image operations, so a stalled Opening-disk load can also prevent
later System-disk writes. This can prevent Opening-disk loading and is
consistent with the mount-order stall. The hardware retests below confirm
writeback and, after allowing image-loading time, DOS access to both drives.

The wrapper now retains all four bits and ORs them for the serialized legacy
engine. All slots explicitly request one 512-byte block. Mount read-only
metadata is also passed at its actual scalar width and replicated for the
legacy input; this does not add enforcement of host read-only state in the
disk engine.

The real wrapper/HPS regression passes reads and writes on all four slots
(4,096 bytes total), ACK lifetime, LBA, block count, and mount metadata. A
negative control restoring only the scalar ACK fails at slot 1, as expected.
The existing adapter, peripheral, video and startup-mute tests also pass.
The next ao486 build snapshot is `build/quartus-20260921-013307-8d60fc/source`.
Compilation completed in 24m48s with 32,146 / 41,910 ALMs (77%), 395 / 553
RAM blocks, and 63 / 112 DSP blocks. Timing still fails: 11 negative-slack
checks, worst `-22.883 ns`; CPU-register paths alone pass with `19.854 ns`
slack. This is an experimental diagnostic build, not a verified release.

RBF SHA-256: `eab37f279929baef8181551c767ad5bbfaf7b690295cd73eea878ae81e548721`.
The device checksum matched after upload as
`_Computer/_Zet98_Test/Zet98_486_DiskFix_20260921.rbf`. It includes startup
mute and the video-output/text-row changes, but not the later DMA bus rewrite.

A fresh v1 probe image was launched with System first, Opening second and a
three-second reset delay. Both host images were open. After boot/writeback,
the retrieved System image contains `Z98DIAG.TXT`: A:\SYS_DISK reads correctly,
but all B: paths still report `0003`. This proves actual DOS log persistence
to the host D88; it does not prove second-drive access. A follow-up using the
same program/core with a fresh System image and a 60-second reset delay
succeeded. The retrieved log shows `B:\OP_DISK OK read=0000` and
`B:\MGXLOAD.BIN OK read=0010`; the sixteen bytes read match the original
Opening image exactly. `B:\SYS_DISK` now returns `0002` (missing file), as
expected on a valid B drive containing the Opening disk. This isolates the
reset delay as the remaining cause in this probe comparison. Keep a 60-second
delay for now; the minimum safe delay and faster image loading remain unmeasured.

Rusty was subsequently launched on the same DiskFix RBF with System/Opening
images and that 60-second reset delay. It resets once after the initial wait.
The user confirms a correctly displayed C-Lab logo and opening cutscenes, but
reports extremely poor performance. This proves further game loading and
visible intro graphics, not satisfactory gameplay speed. Startup-speaker
confirmation and a repeatable gameplay measurement remain pending.

### DMA byte-lane feedback removal

The detailed baseline timing report explicitly includes a combinational loop
through `dbus`: the high-byte fallback reads the final low byte, and vice versa.
In the 20 MHz Zet video-test fit this contributes 22.254 ns of a 34.838 ns
data path, against a 10 ns system-to-SDRAM clock relationship. The first ao486
fit also reports the bus loop on its failing CPU-to-SDRAM paths.

The revised source resolves each lane's normal device priority into a data byte
and a driven flag. DMA then copies the selected source byte only when the
destination lane has no primary driver. There is no cross-coupling of final
outputs. The actual top-level expressions match the historical bus in 57,748
simulation cases, including device-enable pairs, lane masks, CPU/DMA ownership,
and FDC bytes sent to/read from even and odd memory addresses. A deliberate
routing-error control fails the test. This is mux equivalence, not a full DMA
controller simulation or hardware result.

The separate timing-comparison snapshot is
`build/quartus-20260921-014115-47680a/source` (ao486, 20 MHz). Compilation
completed in 25m32s with 32,458 ALMs (77%), 395 RAM blocks and 63 DSP blocks.
Worst reported slack improves from -22.883 ns to -5.493 ns, with nine negative
checks remaining. CPU-register setup alone passes at +20.828 ns. Both snapshots
report 27,077 registers before fitting. No combinational-loop warning appears
in the new build. Remaining critical paths include video counters feeding
system-clock peripheral write inputs through the shared data bus.

RBF SHA-256: `0889dc674ab81d1ce76e0fc28f918ba1113a581e8db0f3b5135a0f75bc18fc53`.
It includes the disk ACK fix and startup mute, but is not deployed; Rusty's
confirmed intro is on the earlier DiskFix snapshot without this bus change.

### Pixel-clock constraint audit

The inherited SDC does not constrain the `VTIMING.clk3sft[2]` clock, which
drives text/graphics logic and SDRAM video requests. It rotates `001` at
75 MHz, producing a 25 MHz clock with one-third duty cycle. Its reset permits
three phases relative to the other PLL clocks.

`scripts/report-pixel-timing.tcl` adds all three possible generated-clock phases
to a completed timing netlist for investigation. It does not change the saved
project constraints or RBF. Running this audit on the completed Zet video-test
fit exposed setup failures from text addressing into the font RAM clocked at
75 MHz (`-5.082 ns`) and from the system-clock text GDC into pixel logic
(`-4.291 ns`). These paths were previously unconstrained. The audit adds no
data-path exceptions; inherited constraints remain in force. The three mutually
exclusive phases are excluded only from timing against each other.
The saved audit script reproduces these setup results and also reports hold
failures from/to the pixel clock (`-0.277 ns` / `-2.621 ns`).

These are additional outstanding timing issues, not evidence that the bus fix
failed or that the user's display symptoms have one established cause. The
audit on the new ao486 bus-rewrite fit reports setup from/to the pixel clock
of -7.136 / -5.520 ns and hold of -0.175 / -2.384 ns. These are additional
checks beyond its ordinary nine negative checks. Full production constraint
coverage remains unfinished.

### Instruction-cache performance work

The DiskFix RBF that shows Rusty's intro still disables the instruction cache.
The new source enables caching only below physical address 80000h. Upper and
banked windows remain uncached. CPU writes use the existing instruction snoop;
external DMA ownership and bank-window writes aliasing fixed RAM invalidate
prefetch and all cache tags. An outstanding fill drains before tag clearing.
This is an instruction-cache change, not the upstream platform's L2/data cache.

The DMA arbiter previously required a falling CPU-strobe edge before granting
ownership. Cached execution or HLT can leave the bus idle indefinitely, so DMA
now acquires an already idle bus while still waiting for an active CPU transfer.
The cache/map/DMA regressions and the full CPU smoke test pass. The latter needs
590 legacy transfers versus the original uncached run's 1,822; this is a test
program, not a Rusty performance measurement.

The full CPU benchmark with eight simulated memory wait cycles reports an ALU
loop of 434,005 cycles / 32,833 transfers with cache disabled and 6,361 / 17
with cache enabled. A VRAM-write loop changes from 114,260 / 8,641 to
6,463 / 417. Both verify output checksums. These deliberately small hot loops
expose repeated code-fetch costs; their ratios must not be advertised as Rusty
speedup. The memory model does not include the complete SDRAM/video arbitration.
The negative control with external invalidation disconnected fails on stale
code, confirming that the coherence test actually exercises cached instructions.

Quartus Analysis & Elaboration passed before the small DMA idle-grant change.
The complete build including it is in
`build/quartus-20260921-022919-fb952a/source`. Compilation completed in 25m40s
with 32,506 ALMs (78%), 395 RAM blocks and 63 DSP blocks. The full design still
fails timing: ten negative checks, worst -5.704 ns. CPU-register setup passes
at +21.539 ns; the worst complete-design path remains video VCOUNT through the
shared read-data mux into OPNA write logic. The separate pixel-clock audit finds
setup from/to the pixel clock of -7.101 / -5.902 ns and hold of +0.103 / -3.000 ns.
These additional constraints do not modify the RBF. This is an experimental
test build, not a timing-verified release.

RBF SHA-256: `043146c966dc9d9371bb0cc4165e373c5064c95699739f64e88a4aee5cb3f450`.
The remote checksum was verified and the cache benchmark launched at 02:59:40
local time. An earlier cache build was deliberately stopped to include the
DMA grant fix. No 66/100 MHz performance claim is established.

`tests/hardware/cpu_bench.asm` is an 8086-compatible DOS benchmark for an isolated
System disk. It uses the DOS clock, checks results and saves `Z98PERF.TXT`.
Version 1 completed on DiskFix with 131,072 iterations in 200 hundredths for
ALU and 500 hundredths for RAM copy. Both checksums passed. The reported clock
appears to have whole-second resolution, so the revised v2 synchronizes to a
clock transition and repeats 131,072-iteration blocks for at least ten reported
seconds. Each kernel must still take less than one hour. This measures neither
Rusty frame rate nor original 486 equivalence.

The uncached v2 baseline was launched at 02:38:43 local time with a single
disposable disk and a 60-second reset delay. The retrieved host D88 contains:
ALU **4 blocks / 1100 hundredths**, RAM copy **2 blocks / 1100 hundredths**,
and passing checksums. Each block contains 131,072 iterations. Baseline and
future cache-test disks start byte-identical; only BOOT.COM's allocation differs
from the supplied System image. The cache build also includes the data-bus
feedback removal and DMA idle-grant fix, so this comparison is between complete
builds at the same 20 MHz clock, not a runtime cache-toggle experiment.

The cache run saved its result at 03:02:36 and was retrieved at 03:03:34:
ALU **106 blocks / 1000 hundredths**, RAM copy **40 blocks / 1000 hundredths**,
with both checksums passing. Normalized by reported elapsed time, these are
**29.15x** and **22x** the uncached baseline throughput respectively. DOS time
has coarse resolution and these are small hot loops; they measure neither
Rusty frame rate nor improvement over the original Zet CPU. The authoritative
local copies are `build/hardware/cpu-bench-v2-baseline-return-2.d88` and
`build/hardware/cpu-bench-v2-cache-return-2.d88`, with extracted `.txt` logs.
The isolated Rusty cache launcher uses the same System/Opening images and
60-second reset delay. Game A and Game B are both available in the test folder
for later swaps. User confirmation of cached-build gameplay remains pending.

During this first Rusty comparison the user initially reported a black screen
and long beeps, then reported that Rusty did boot after a long wait. A rollback
to DiskFix had already been requested in response to the first report and
interrupted the intro the user was watching. The exact build responsible for
the visible intro is therefore not established. A temporary split in the intro
graphics reportedly corrected itself. Do not count this as either a confirmed
cached-build boot failure or a successful Rusty speed comparison. That
run was left on DiskFix; the next comparison needed an identified build and a
longer uninterrupted observation window. The ten-second speaker timer also
does not establish a quiet complete boot; the source of the later beeps remains
unconfirmed.

A new uninterrupted Cache run was launched at 03:33:59 local time on
2026-09-21. After a longer observation window, the user confirmed that the
animation looked "a bit better". This establishes a visible improvement on the
identified cached 20 MHz build, not a frame-rate measurement or satisfactory
gameplay. The run was left intact while the next changes were compiled.

An independent CPU/adapter 66 MHz feasibility fit completed under
`build/cpu-probe-66-20260921`. `scripts/probe-cpu.tcl` uses virtual pins and
one-nanosecond input/output delays; it is not a board design or a deployable RBF.
Its register timing and unconstrained-path reports distinguish CPU headroom
from the still-unresolved platform clock crossings. The fit uses 17,983 ALMs,
16 RAM blocks and three DSP blocks. It fails register setup by -1.708 ns;
register hold passes at +0.363 ns and the isolated design is fully constrained
for setup/hold. The worst setup path runs from execute operand-size state into
the prefetch FIFO count. Same-clock Fmax is estimated at 59.32 MHz for this fit;
that estimate is not validation of a complete core at 59, 66 or 100 MHz.

### Direct CPU I/O write path

The next source change supplies 30 CPU-only I/O write inputs directly from
the CPU output, retaining the loader override. Previously, peripheral read
outputs (including video timing) fed those inputs through the shared priority
mux even though selected CPU writes override them. The FDC DMA data path and
memory/GRCG read-modify-write paths retain the shared bus. All adapter tests
pass; the data-bus regression compares 8,556 selected write bytes against the
historical mux, and a deliberately swapped-lane control fails.

The I/O-only change compiled in 23m37s under
`build/quartus-20260921-031038-7aa6c5/source`, using 32,525 ALMs (78%),
395 RAM blocks and 63 DSP blocks. Worst reported slack improves from -5.704 ns
to -3.864 ns, but eight negative checks remain. CPU-register setup passes at
+19.519 ns. The worst remaining path feeds VCOUNT through the shared bus into
the floppy write-data register; NVRAM and text-memory write inputs also appear.
The pixel-clock audit still fails setup (-4.916 / -5.684 ns from/to the pixel
clock) and hold (+0.117 / -2.491 ns). No constraints were suppressed.
This RBF was not deployed. SHA-256:
`3b51e967adccf4f2f42e2037e651d8b8a9ca9768bacf005d68ef6b0e1aaef7bc`.

The next change separates memory writes into loader, CPU and FDC DMA sources,
and restricts memory-to-FDC DMA selection to memory devices. It preserves
odd/even byte routing, loader priority and the live GRCG read-modify-write
mask. Tests add 20,000 DMA routing comparisons and 4,096 actual GRCG plane
results with delayed memory data; the complete adapter suite passes. Exercising
the actual GRCG also exposed an existing eight-bit-versus-sixteen-bit XOR in
tile comparison. It now compares both bytes, with distinct high/low matches
tested on all four planes. The complete fit under
`build/quartus-20260921-034632-5dde7d/source` finishes in 24m09s, using
32,414 ALMs, 395 RAM blocks and 63 DSP blocks. Eight negative timing checks
remain; worst slack improves to -2.937 ns and CPU setup passes at +20.185 ns.
The remaining worst path carries video retrace status into CPU I/O read data.
The pixel-clock audit still reports violations. This RBF was not deployed;
SHA-256 `662d1a75dbbb2e83408ad9c3d669d5d5e16c8114e336e8a03eead20f9a60cdd5`.

### Extended RAM and optical-drive investigation

The optional 16/64 MB DDR map passes real-CPU simulation, and the 16 MB mixed
VHDL/SystemVerilog integration passes Quartus analysis/elaboration. It has
now passed the disposable DOS physical-memory probe on hardware at both sizes.
See `rtl/cpu/EXTENDED_RAM.md` for the memory hole,
cache limitations and outstanding BIOS/XMS work. Default builds still use
the original low-memory map.

Read-only inspection of the SuperStation's Linux device tree finds `/dev/sr0`,
an HL-DT-ST DVDRAM GUD1N behind an Initio USB bridge. This establishes host
visibility only. No PC-98 optical controller, guest driver or media transport
has been implemented or tested, and no disc was read, written or ejected.

RAM16 at 40 MHz (`quartus-20260921-042706-f51ef0`) fits at 32,826 ALMs,
395 RAM blocks and 63 DSP blocks. It fails 12 timing checks, worst -4.684 ns;
CPU setup passes at +2.936 ns. Pixel setup remains -6.043 / -5.486 ns from/to.
The worst reported paths now concern SDRAM requests, not raw retrace status.
SHA-256: `fff5a1cc35b9cd1e392bb97793ff77f9d88d2700735f13f87298b58ccde41c88`.
Launched at 04:57:47 CEST; `ram-probe-16-return-1.d88` contains a passing
`Z98RAM.TXT` for the 16 MB map (14 MB extended RAM).

RAM64 at 40 MHz (`quartus-20260921-043344-4171e7`) fits at 32,917 ALMs with
the same RAM/DSP use. It fails 18 timing checks, worst -4.383 ns; CPU setup
passes at +4.364 ns. Pixel setup remains -7.475 / -6.816 ns from/to.
SHA-256: `00332526633b443f2d1a89e5e0cf7cbd8274d21cb42f489a45104007bdf92584`.
Launched at 05:03:48 CEST; `ram-probe-64-return-1.d88` contains a passing
`Z98RAM.TXT` for the 64 MB map (62 MB extended RAM). Both probes check distinct
sentinels at both ends of every mapped MB, partial/unaligned writes and return
to DOS from protected mode. They do not test BIOS/XMS discovery, every byte of
RAM, long-term stability or game compatibility. Default build options remain
unchanged pending that work.

### Short-read optimization and usability changes

The memory bridge now omits an unused halfword on single-DWORD data reads.
The unmodified ao486 Avalon generator supplies meaningful byte enables for
these requests. Eight-DWORD instruction fetches and multi-DWORD data reads
retain full reads, because their shared mask cannot describe each beat.
The upstream-master integration passes 156 commands and verifies the transfer
counts directly; the adapter tests cover all masks, bursts and stalls.
The full CPU smoke test passes with 576 transfers (previously 590).

With the same eight-wait-cycle simulation, the cached CPU VRAM-copy kernel
changes from 6,463 cycles / 417 transfers to 5,309 / 289, about 21.7% higher
throughput. Arithmetic is unchanged at 6,361 / 17. Cache coherence, self-modifying
code, upper-window bypass and output checksums still pass, including the
disconnected-invalidation negative control. This is a synthetic simulation
result, not a Rusty or complete SDRAM-controller measurement.

The revised startup mute waits for an ongoing speaker tone to end before
restoring audio after its ten-second minimum. A rotating floppy overlay uses
actual FDC busy plus HPS floppy-slot traffic, defaults on at status bit 5 clear,
and can be disabled. All adapter tests pass, including long-beep/later-tone
behavior and eleven overlay frames with timing, rotation and mode-size checks.
Hardware verification and complete fits of these changes are pending.

The completed Opt20 build (`quartus-20260921-040034-eb1e55`) uses 32,375 ALMs,
395 RAM blocks and 63 DSP blocks. It has five negative timing checks, worst
-2.731 ns, and CPU setup +22.467 ns. The Opt40 build
(`quartus-20260921-040055-563579`) uses 32,780 ALMs with the same RAM/DSP use;
14 timing checks fail, worst -5.404 ns, while CPU setup is +4.146 ns and
system-to-system setup is +3.243 ns. Pixel audits still fail. These are
experimental hardware diagnostics, not timing-qualified releases.

Opt20 was hash-verified and launched at 04:31:53 CEST. Its saved DOS benchmark
reports ALU 106 blocks and RAM copy 46 blocks, each in 1000 hundredths, both
checksums passing. That is 15% higher RAM-copy throughput than Cache20's 40
blocks, with unchanged arithmetic. Opt40 was launched at 04:35:09 CEST and
reports ALU 202 / RAM copy 83 blocks in the same elapsed time, both passing:
about 1.91x / 1.80x Opt20 throughput. These remain synthetic throughput
measurements, not Rusty frame rates. Authoritative results are the returned
`cpu-bench-v2-opt20-return-1.d88` and `cpu-bench-v2-opt40-return-2.d88` under
`build/hardware`, with extracted text logs. SHA-256:

- Opt20: `d7b7a7a9f6f47024d20d213c6079b615caf62264b712ff1044a41a9ba436d3e6`
- Opt40: `0e1959ab75b09f9af2b7cb18b57e6f4229c6372731f888b913fa713164563406`

A fresh-disk Opt40 repeat launched at 04:43:52 CEST reports ALU 202 / RAM
copy 84 blocks, each in 1000 hundredths, again with both checksums passing.
Its returned disk is `cpu-bench-v2-opt40-repeat-return-1.d88`.

An optional 50 MHz setting now preserves OPNA/PIT rates and 100 ns VFO pulses
in simulation. PS/2 scaling multiplies before dividing, avoiding truncation
at a non-integer multiple of 20 MHz. The 64 MB / 50 MHz fit
(`quartus-20260921-044331-0e2634`) finishes in 28m38s, using 33,192 ALMs,
395 RAM blocks and 63 DSP blocks. CPU and system setup pass at +2.335 ns.
One production-summary timing check fails: HDMI setup -0.040 ns at the slow
-40 C corner. The separate pixel-clock audit still fails setup -6.150 / -4.510 ns
and hold -0.036 / -2.568 ns from/to the pixel clock. This is not timing closed.
RBF SHA-256: `c5d6cc14478326d1810b89df5893fed1d7291ac6a43779496accab600b9c17d1`.

The first launch at 05:14:36 had its diagnostic D88 uploaded to the core folder,
not the MGL setname's game folder, and no disk mounted. That attempt says
nothing about guest boot. After correcting the deployment, the 05:21:33 run
mounted the disk under `games/Zet98_Test` and saved a passing result:
ALU 245 / RAM copy 98 blocks, each in 1000 hundredths. This is about 21% / 17%
above the repeated 40 MHz result and 2.31x / 2.13x the matching 20 MHz result.
The authoritative return is `cpu-bench-v2-50-mounted-return-2.d88` and its
extracted text log. It remains a synthetic benchmark, not Rusty FPS.

The same 50 MHz RBF was launched with the 64 MB physical-memory probe at
05:34:21 CEST. `ram-probe-64-50-return-1.d88` contains a passing `Z98RAM.TXT`
for all 62 mapped extended MB, partial/unaligned access and real-mode return.
BIOS/XMS discovery remains untested.

The next source change registers horizontal/vertical retrace status in the
video domain, then synchronizes the two independent levels into the CPU
domain before GDC status reads and PIC IRQ2. This removes the decoded raster
counter from those long combinational paths. The actual raster regression
passes at 20/40 MHz with bounded status latency and no extra edges. Video
output timing is unchanged; no timing exceptions have been added. Its first
complete fit also enables the optional 16 MB DDR map for hardware diagnosis.

The optional `-SoundBoard PC9801_86` integration adds PCM playback and shared
IRQ12. Standalone PCM and PIC regressions pass, and Quartus analysis/elaboration
passes in `quartus-20260921-044759-401082`. The complete PCM build and silent
DOS FIFO/IRQ diagnostic now pass on hardware. The 40 MHz / 64 MB PCM fit
(`quartus-20260921-045234-21f89e`) finishes in 26m17s, using 33,087 ALMs,
427 RAM blocks and 65 DSP blocks. It fails 17 timing checks, worst -4.630 ns;
CPU setup is +3.613 ns and pixel setup is -7.112 / -7.044 ns from/to.
SHA-256: `faa15038020039556947e45a94cd93cf0e41a2a0cd11f5cfc807164a2df24d37`.
Launched at 05:25:22, the silent diagnostic saves `Z98PCM.TXT` reporting the
86-board ID, 32 KB FIFO full/empty/reset, and two IRQ12 deliveries with pending
status, acknowledgement and PIC EOI. Returned disk: `pcm86-probe-return-1.d88`.
PCM is muted throughout; actual sound quality and game-driver compatibility
remain unverified. See `rtl/PCM86.md` for explicit limitations.

### Combined 50 MHz hardware and usable XMS

`quartus-20260921-051952-cb3951` combines 50 MHz ao486, 64 MB DDR, PCM86, the
coherent DDR word buffer and registered SDRAM request metadata. It compiles in
25m43s with 33292 ALMs, 427 RAM blocks and 65 DSP blocks. The original timing
summary has no negative slack (minimum +0.084 ns), and CPU setup is +1.917 ns.
However, the added pixel-clock audit fails setup -6.907 / -3.869 ns and hold
+0.141 / -2.532 ns from/to. It is not timing closed. New source includes those
three alternative pixel-clock phases in production SDC, so future fitting can
optimize them; it does not suppress paths to other clocks.
RBF SHA-256: `8a45c465a682d4128b216012ab02623326b6fe4af2f9cf232f373cb39e18a703`.

The combined build passes the PCM probe launched 05:48:14 and RAM probe launched
05:50:12 CEST. Returns are `buffered50-pcm-return-1.d88` and
`buffered50-ram-return-1.d88`. Its 05:51:50 benchmark saves ALU 243 / RAM copy
98 blocks in 1000 hundredths each, both checksums passing
(`buffered50-bench-return-2.d88`). This is essentially the earlier 50 MHz result.

Rusty was launched at 05:56:37 with the existing System/Opening disk copies.
Remote screenshot `rusty-buffered50-060040.png` shows the rendered intro scene
and bottom-right floppy icon. This time remote capture works. It establishes
rendering at that instant, not gameplay FPS, icon rotation or audio quality.

The new `software/z98mem.asm` DOS initializer preserves probed RAM and supplies
BIOS memory counts to the separate open-source HIMEMX(98) driver. On the
combined 50 MHz build, the first 64 MB XMS run launched 06:01:53 passes, with a
saved log and screenshot (`xms64-probe-return-2.d88`, `xms64-probe-060420.png`).
It allocates/locks 17 MB above the aperture, checks round trips at both ends,
unlocks/frees it and verifies recovered free memory. A repeat launched 06:11:41
records **63424 KB free**, allocation at **01000000h**
(`xms64-repeat-return-1.d88`). The 16 MB / 40 MHz fallback launched 06:07:16 also
passes, recording **14272 KB free**, allocation at **00110000h**
(`xms16-probe-return-2.d88`). All use disposable disk copies. This makes XMS
usable with the documented drivers; the original BIOS alone still does not
advertise extended RAM, and EMS/UMB support has not been validated.

### Optional 8 KB conventional-RAM cache

The first cache fit (`quartus-20260921-053817-c952db`) completes in 36m58s,
using 36964 ALMs, 438 RAM blocks and 65 DSP blocks. Its original timing summary
has no negative checks (minimum +0.117 ns); CPU setup is +1.258 ns. The pixel
audit still fails setup -5.926 / -4.510 ns and hold +0.017 / -2.423 ns from/to.
SHA-256: `6930fddc632f108ae096fee83695e7180be4b047bfe6459455906a693b2ad2e1`.
Launched at 06:20:06, the DOS benchmark saves ALU **244** / RAM copy **119**
blocks per 1000 hundredths, both checksums passing
(`lowcache50-bench-return-2.d88`). This is about 21% higher RAM-copy throughput
than the otherwise matching 50 MHz build. The XMS run launched at 06:23:58 also
passes and reports 63424 KB free (`lowcache50-xms-return-2.d88`).

The subsequent cache fit with explicit pixel clocks
(`quartus-20260921-054634-e21f65`) completes in 39m05s with 36989 ALMs,
437 RAM blocks and 65 DSP blocks. Its production summary now includes those
clocks and fails 23 checks, worst -3.139 ns. A separate cache revision moves
validity into RAM and uses a nonblocking background clear, aiming to reduce
logic use. Its unit and full CPU/coherence/extended-memory tests pass, with
unchanged ALU/VRAM simulation kernels. Its 50 MHz fit
(`quartus-20260921-062504-f9ca37`) completes in 37m42s with 33348 ALMs, 438 RAM
blocks and 65 DSP blocks: 3616 fewer ALMs than the first cache. CPU setup is
+1.101 ns, but the complete design fails 21 timing checks, worst -2.703 ns.
RBF SHA-256: `b7542ba77e4bebfc8d2b266cd4ea6cbfa5faa516f902e1a2782020bfd52e02c5`.
This version still has the earlier graphics handshake. The fresh hardware
benchmark launched at 07:13:51 and passes with ALU 244 / RAM copy 119 blocks
per 1000 hundredths, unchanged from the larger cache
(`compactcache50-bench-return-3.d88`, `compactcache50-bench-071628.png`).
The 07:17:10 PCM run also passes the board/FIFO/two-IRQ checks
(`compactcache50-pcm-return-1.d88`). Its XMS run launched at 07:20:00 passes
with 63424 KB free and the 17 MB block at physical 01000000h
(`compactcache50-xms-return-1.d88`).

The `-SystemClockMHz 60` experiment passes OPNA/PIT/PCM-rate and SDRAM request
simulation. Its first full fit (`quartus-20260921-061451-2d245c`) completes in
32m41s with 34747 ALMs, 425 RAM blocks and 65 DSP blocks. Timing fails 48 checks,
worst -6.658 ns; even the CPU-internal setup report fails at -0.393 ns. It is
not deployed. No reliable 60 MHz hardware claim is made.

The first cache-enabled 50 MHz PCM test launched at 06:27:21 also passes
(`lowcache50-pcm-return-1.d88`). It verifies the board ID, FIFO and two IRQ12
deliveries, with PCM muted. Rusty launched on that build at 06:35:03 shows its
intro text at 06:38:29 (`rusty-lowcache50-063829.png`), then a black frame at
06:48:27. A Space key sent through a temporary Linux keyboard at 06:49:21 does
not immediately change that frame. This is not a successful gameplay test.

To isolate the intro-to-game transition, a disposable System disk changes only
three bytes: it skips the BOOT.COM call to OP.COM (offset 0143h in the file).
All original source images remain untouched. This disk plus Game Disk A was
launched at 06:51:33 using `Zet98_Rusty_SkipIntro50.mgl`. The 06:54:19 capture
shows the title menu. Temporary keyboard input reaches the cemetery story
scene at 06:56:46 and dialogue at 06:58:50; advancing dialogue reaches the
actual first stage at 07:02:31. The player, enemies, HUD and timer render
coherently (`rusty-skipintro50-070231.png`). This is a gameplay milestone for
the private intro-skipping disk, not proof that the original intro completes.
A two-second Right-key trial coincides with apparent death/respawn and is not
a valid movement or FPS measurement. Sound quality remains unverified.

### Pixel-clock text memories

Text, attribute and font display ports now share the 25 MHz renderer clock;
their independent CPU ports are unchanged. This removes the 75 MHz to pixel
RAM-output crossings and gives font address/enable logic a full pixel period.
Kanji right-half prefetch is explicitly scheduled at pixel phase 2, after the
synchronous text read settles and before font capture at phase 6.
`tests/run-text-pixel-memory.sh` verifies 1024 pixels per run across all 16 font
rows, alternating Latin/two-cell Kanji, both font banks, independent colors,
reverse video and underline. It passes with 0/12/25 ns RAM delays, and rejects
a deliberately late 200 ns response. Fitting and hardware validation of this
text-memory change are pending.

### Graphics transfer timing work

The explicit pixel-clock constraints exposed unsynchronized graphics control
crossings as well as bundled address/data buses being timed against arbitrary
adjacent clock edges. SDRAMC now uses synchronized request/completion toggles.
It no longer consumes raw pixel-domain ACK or job bits in its memory domain.
Only each control synchronizer's first input stage is excepted; its remaining
stages and control logic remain timed. The two held address/data buses have
20 ns maximum-delay constraints, with normal hold checks retained.

`tests/run-video-sdram.sh` connects the real SDRAMC and GRAPHSCR98 with a checked
line-RAM model. It verifies 16 complete lines, all four plane values and their
order, concurrent CPU reads, and six relative clock phases. Data and address
each carry 20 ns transport delay; enabled RAM capture must still have 20 ns
of data stability. A deliberately late data path must fail. CPU SDRAM tests
also pass at 20/40/50/60 MHz. The test additionally covers the corrected reset
of VIDDAT3 and explicit 10-bit graphics line-counter wrap.

An audit of the previous constrained 50 MHz fit matches all 64 data bits and
14 address bits plus duplicates. Those bundled buses pass the justified
20 ns limit; other control/configuration/text-video paths still fail. A fresh
50 MHz fit includes the new control handshake, compact cache and constraints.
The first attempt (`quartus-20260921-064725-d61d77`) stopped at the constraint
endpoint guard: before RAM packing, 64 line-data bits are represented by 32
two-bit input keepers. The corrected guard accepts that representation while
still requiring all 64 source registers. A mapped-netlist check matches
14/13/64/32 address-source/address-target/data-source/data-target registers
and both control synchronizers. The fresh retry is
`quartus-20260921-070116-c80cce`. It completes in 26m12s with 33218 ALMs,
435 RAM blocks and 65 DSP blocks. CPU-internal setup passes at +0.764 ns,
but 19 full-design checks fail, worst -0.951 ns. Remaining paths include
text-RAM-to-pixel hold (-0.951), CPU write-data-to-SDRAM setup (-0.623),
the MiSTer scaler (-0.441), and video reset recovery (-0.195 ns).
The 07:39:16 hardware benchmark passes with ALU 246 / RAM copy 121 blocks
(`graphicssync50-bench-return-1.d88`). Rusty launched at 07:42:49 reaches the
title at 07:47:08 and the introductory map at 07:52:36. This still uses the
private intro-skipping disk; it does not establish original intro completion,
frame rate, or a fix for the earlier HDMI issue.

### Subsequent text-clock, cache-size and reset builds

The text-clock build `quartus-20260921-072136-f80571` fits in 27m19s with
33286 ALMs, 435 RAM blocks and 65 DSPs. Reported failing checks drop from
19 to 2, worst -0.231 ns: CPU text-cursor settings still cross directly into
the glyph comparison. RBF SHA-256 is
`7b0436fce926ad744235abefb1805af357c614b81dc064c147a57009d2250d6c`.
Its benchmark launched at 08:00:41 passes ALU 246 / RAM copy 121 blocks
(`pixeltext50-bench-return-1.d88`).

The matching 64 KB conventional-cache build `quartus-20260921-073124-f4b543`
fits in 29m31s with 33226 ALMs, 503 RAM blocks and 65 DSPs. Two timing checks
fail, worst -0.164 ns. RBF SHA-256 is
`f0f0f134f076dca0187418f1f45ad0fc2f7637a237d5ff2da78a0286cbbef9ad`.
The 08:05:06 benchmark also passes ALU 246 / RAM copy 121 blocks
(`cache64k50-bench-return-1.d88`). This does not demonstrate an advantage
over 8 KB, which remains the working baseline.

The reset-release build `quartus-20260921-073713-f711bc` adds separate
two-stage video/pixel reset release. Its simulation verifies 40 release
phases and stopped-clock recovery. Its full fit nevertheless fails 14 checks,
worst -0.647 ns; it is not deployed. Source now also pipelines cursor settings
into the pixel domain, with all original cursor paths still timed. Rendered
text tests cover cursor on/off, font/attribute alignment and late-data rejection.

The raw IDE build `quartus-20260921-080409-c14854` fits with 38865 ALMs,
435 RAM blocks and 65 DSPs, but fails three timing checks, worst -0.896 ns.
It was loaded at 08:38:24. `rawide50-probe-return-1.d88` reports PASS for
IDENTIFY, the exact 1 MB image signature, sector 17 write/read checksum and
four IRQ9 deliveries. Host-side comparison of `rawide50-disk-return-1.vhd`
confirms only sector 17 changed, with all 256 expected words. This verifies
PIO/IRQ plumbing on hardware, not bootable hard-disk support.

The IDE buffer initially consumed 5083 ALMs because Quartus could not infer
its dual old-data write ports. The shared-write-port version passes the
sector and real-HPS regressions and synthesizes to 4096 RAM bits / 171
registers in an isolated controller build. Integrated fit/hardware validation
is still pending. Integer scaling, the supplied animated overlay, the global
pixel-clock assignment and corrected graphics row addressing are also under
FPGA validation. See `rtl/storage/README.md` and `VIDEO_OUTPUT.md` for limits.

Keep BIOS, disks and settings identical when comparing Zet and ao486.
Still required: reliable unmodified intro-to-game loading, repeatable gameplay
timing, sound pitch/tempo, and video stability. Neither the
initial logo nor successful FPGA fitting measures Rusty speed.

### Native50: reported timing pass and hardware interrupt/disk checks

Snapshot `quartus-20260921-115048-aca4bf` uses clean source commit
`ff843f37a40ff762edf4935bb28443d53f3c6fde`: ao486 at 50 MHz, 64 MB RAM,
PC-9801-86 sound, 8 KB conventional-memory cache and raw IDE. It includes
the FM clear fix, native/integer scaling, graphics row correction and the
compressed 59-frame overlay. Compilation completes in 31m45s with 34194/41910
ALMs, 453/553 RAM blocks and 66/112 DSPs. The tile overlay saves 25 RAM blocks.
All reported setup/hold/recovery/removal/pulse-width checks have nonnegative
slack; the minimum is +0.045 ns. All clocks are constrained. However, the
inherited board interface still has 24 unconstrained input ports and 86
unconstrained output ports, including SDRAM DQ and HDMI signals. These need
board/device timing budgets before complete interface sign-off. Do not hide
them behind blanket false paths or describe this build as fully certified.

RBF SHA-256:
`38bbb7f7f2f5f00ff66cb4c7e1a979afb95f6f8db830b4b4bea1e20b5b2b80e3`.
The separately named Native50 test RBF on the SuperStation matches this hash.

- FM probe loaded at 12:24:38 CEST: the returned disposable D88 contains
  `PASS: 100 FM timer B IRQ12 deliveries`, including status clear and cascaded
  PIC EOI. The earlier Integer50 probe failed at two deliveries. This is a
  silent interrupt test, not an audible music-quality measurement.
- Read BIOS probe loaded at 12:30:18: geometry, IPL/partition checksums, a CHS
  cylinder crossing and a 64 KB linear transfer pass against the full private
  DOS game VHD. The image's local and device SHA-256 hashes match. The probe
  performs no HDD writes and does not test HDD boot.
- Original System/Opening Rusty disks loaded at 12:33:05: early captures are
  black; after Space/Enter at 12:38:29, a 12:39:18 capture shows a coherent
  Rusty title/menu. This does not establish an unattended opening transition.
- Scaler metadata confirms 640x400 captured into a 1728x1080 native-fit
  viewport. After changing only the isolated core's scaling bits, integer
  fit reports a 1280x800 viewport. Global HDMI/HDR settings are unchanged.
- Integer zoom reports 640x360 captured into 1920x1080, consistent with the
  centered 3x crop. Fit native was restored afterward. A separate direct-game
  Rusty launch reaches a coherent portrait/story scene at 12:51:31; this is
  not a measured gameplay frame rate.

### Prefetch optimization at 60 MHz

`quartus-20260921-123624-22e6a5` completes in 29m34s with 34484 ALMs,
453 RAM blocks and 66 DSPs. CPU-internal setup now passes at +0.030 ns.
Eleven full-design checks fail, worst -5.898 ns from CPU byte-enable control
to SDRAMC MEMDAT. Other failures include DMA readback, video crossings and
memory-ready reset recovery. This RBF was not deployed; Native50 stays on
the device. The next fit tests registered CPU write set/preserve bundles and
CPU-domain release of memory-ready reset.

### First DOS 6.20 VHD boot on Native50

The COM bootstrap's trace stopped at DOS's first root-directory read. Its
partition IPL sets SS=0/SP=028Eh; the 512-byte caller-stack bounce buffer
overwrote interrupt vectors. A private resident stack fixes the reproduced
IVT failure. The COM approach still failed to reach the new DOS, so the next
test starts the resident loader directly from a new floppy IPL, before any
old DOS interrupt hooks are installed.

`Zet98_HD_Boot6_Native50.mgl`, loaded at 13:34:06 CEST, reaches the DOS 6.20
game menu at 13:36:28 using the full private VHD. Its 13:37:36 MEM report shows
541 KB largest conventional block and zero XMS under the original NEC HIMEM
profile. Rusty selected at 13:38:01 reaches an illustrated intro at 13:40:05.
The BIOS performs reads only. This is neither HDD save/profile-write support
nor a measured gameplay frame rate. The following test uses a separately
verified image copy with Z98MEM/HIMEMX and no on-screen BIOS trace.

The separate XMS image preserves 2026 existing files except CONFIG.SYS, plus
the original IPL/partition bytes. It adds the exact initializer, HIMEMX, its
source/license archive and FPGA profile. SHA-256 is
`879d4b51964ccad3b8f553eda7507ca97a913e7bdcc982f19dd6de185dd0798e`, verified
again on the SuperStation before loading at 13:44:25. DOS 6.20 reaches its
menu and MEM shows DOS moved high with a 608,912-byte largest conventional
block. NEC MEM still reports zero XMS, so a direct API probe was necessary.

The same VHD was reloaded with a separate disposable diagnostic floppy at
13:50:48. The XMS probe run from C: passes allocation/locking of 17 MB above
16 MB, pattern copy/verification at both ends, unlock/free and recovery of
the original free-memory total (at least 60000 KB). The returned floppy's
`Z98XMS.TXT` and 13:55:07 screenshot confirm PASS. No VHD write was performed.

The XMS game image was loaded again at 13:57:52 with the clean BIOS-first
floppy loader. Its menu is visible at 14:04:19. Selecting Nightslave at
14:05:17 reaches the coherent title screen captured at 14:07:23. This is a
VHD launch check, not a gameplay-throughput or MIDI/audio-quality result.

### CPU read/write crossing work after Native50

The 60 MHz write-bundle fit `quartus-20260921-132727-3d85bc` completes in
29m17s with 34620 ALMs, 453 RAM blocks and 66 DSPs. Nine reported checks fail,
worst -3.120 ns. The previous -5.898 ns CPU-to-SDRAM write path is replaced
as the worst path by SDRAM read data into CPU execution logic. CPU-internal
setup regresses to -0.202 ns; the complete CPU-clock domain fails by
-0.575 ns. Memory and video setup also fail, as does video-reset recovery
(-0.080 ns in the detailed post-fit report). This RBF was not deployed.

The next source revision captures CPU read results with the existing ACK
assertion, leaving internal RMW in the memory domain. All 9216 buffered and
1536 legacy transactions pass with varied per-plane read data. Their 28
simulation completion times exactly match the prior regression runs.
Deliberately late write admission and a one-cycle-late read capture both
fail as intended. Graphics arbitration and GRCG/data-bus regressions pass.
FPGA fitting and hardware validation of this read change are pending.

The write-bundle/prefetch source at 50 MHz, snapshot
`quartus-20260921-135403-d6bfcb` / commit `61f80ff`, completes in 33m46s with
34160 ALMs, 453 RAM blocks and 66 DSPs. No reported timing check is negative;
minimum slack is +0.056 ns. Board-I/O constraint limitations still apply.
It excludes the subsequent CPU read-capture change. The separately named
Bundle50 RBF has SHA-256
`d6df5d57b53ad208f053bd1efb55ba8238052e53f42487830d69750924950bc6`.
Its first FM diagnostic was loaded at 14:31:47. The returned floppy and
14:33:51 capture confirm 100 timer-B IRQ12 deliveries, status assertion/clear
and cascaded PIC EOI. This silent test does not measure audible music quality.

### Bounded BIOS sector writes on Native50

Loaded at 14:24:33, `Zet98_BIOSWrite_Native50.mgl` uses a newly generated
1 MB diagnostic VHD and a floppy with `ide_write_probe.asm` as its shell.
The probe checks IDENTIFY capacity and the exact marker before writing;
the BIOS write window admits only sector 17. The returned floppy reports
PASS for full/partial writes, readback, CHS/LBA and protected neighbors.
Host comparison confirms only sector 17 changed, with all 512 expected
bytes including the preserved tail after the 31-byte update. No game VHD
was written by this test.

### DOS file persistence on Bundle50

`Zet98_HD_RW_Bundle50.mgl` was loaded at 14:41:21 using a separate game-image
copy and a write-enabled BIOS-first loader. The initial image SHA-256 is
`ad572500a2ffd6559aca3371d6f14811c044e42e8d683487777ca3deb58720f7`; the
loader D88 SHA-256 is
`8493b35ed46b448200904acfdc6a78f1e922d2797a824f0e1a7e5085cf870ae3`.
It preserves 2030 previous files except PROFILE.BAT and adds compatible
FPGA profiles and the file diagnostic. DOS reaches the FPGA-profile menu.

FTEST.COM run at 14:45:01 creates a new 70,001-byte Z98WRITE.BIN, flushes,
closes, reopens, compares every byte and checks EOF. The 14:46:08 capture
shows PASS. An independent full-image comparison at 14:48:25 finds exactly
140 changed sectors, confined to FAT/root metadata and clusters 7026ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ7030.
A stricter metadata audit confirms all unrelated FAT and directory entries
are identical to the pristine archive. Both FAT copies agree. The extracted
payload also matches on the host, SHA-256
`f3484c7e4e06abc4978a08c7947518521c0e5017a95728d39bc04be091a67141`.
This is a DOS file-persistence result, not a game-save or power-loss test.

### CPU read capture at 60 MHz

`quartus-20260921-141137-e39c88` completes in 29m41s with 34731 ALMs, 453
RAM blocks and 66 DSPs. Seventeen reported checks fail, worst setup
-2.289 ns from the separate GDC drawing path into SDRAM. CPU-internal setup
passes at +0.256 ns; the full CPU-clock domain still fails by -0.033 ns.
Video setup, pixel hold/removal and other hold checks also fail. This build
was not deployed. The post-fit reporter now includes incoming memory/video
paths so a CPU improvement cannot obscure the remaining peripheral limits.

### Writable DOS memory profiles on Bundle50

The profile menu saved LIMITED at 14:57:35 on September 21. After reload at
14:58:44, DOS reached the LIMITED menu. LIM.COM passed at 15:05:06: 14,272 KB
free XMS (hex 37C0), a 1 MB block at physical 00110000, both-end copy/readback,
unlock/free and full recovery of the free count. The returned diagnostic
floppy contains the same result. The full FPGA profile was saved again at
15:09:46. After reload at 15:10:37, DOS reached the FPGA menu. The
15:16:25 screenshot and returned log pass the 64 MB diagnostic: 63,424 KB
free (hex F7C0), a 17 MB block at physical 01000000, both-end verification
and recovery of the full free count after unlock/free.

### Video corner timing preparation

The all-corner 60 MHz report identifies -0.626 ns parent-settings-to-pixel
hold and -0.239 ns parent-reset-to-raster removal at slow/-40 C. Settings now
pass through an opposite-edge parent register before the pixel registers;
normal half-cycle setup/hold checks remain. The raster counters use the
existing pixel reset chain; the clock divider still uses parent reset.
Full CRTC render tests pass six reset phases (640 visible pixels), raster
counter tests pass, and 40 reset phases/stopped-clock recovery pass. A test
that reconnects raster reset to the parent domain fails as intended. Physical
timing and hardware verification of these video changes remain pending.

The same 60 MHz netlist also reports -1.284 ns from video_calc measurements
through its CPU-clock parameter mux and -1.593 ns from cfg_dis into the HDMI
PLL's video measurement logic. Measurement words are now registered before
the status mux, retaining normal timing checks. The real video_calc passes
two raster modes and all width/height/line/frame/pixel parameter reads at
four system rates. The test raster includes a vertical back porch, as the
core does; putting active video on the VS falling edge incorrectly omitted
its first pixel in the initial test model.

HDMI tuning now keeps both scaler measurement clocks unmasked and registers
configuration enable on the input-video clock before masking data/CE. Forty
enable phases pass, with exactly preserved clock-edge counts. A deliberately
restored configuration clock gate fails. No global MiSTer configuration or
physical HDMI output mode is changed. These framework changes still require
full FPGA timing and hardware validation; they do not establish the cause
of the user's earlier display-chain glitches.

The CONV profile was saved at 15:25:13 and booted after reload at 15:27:54.
Its 15:31:55 MEM report shows 655,360 conventional bytes, 553,856 free,
a 553,840-byte largest DOS block, no upper-memory blocks and no XMS manager.
BARE was saved at 15:35:47 and reloaded at 15:36:39; the 15:39:56 capture
shows the expected DOS 6.20 shell without launching the menu. All four
FPGA-oriented profiles have now booted on Bundle50. Restoring the default
full-memory profile follows this check.

### GDC/read-capture 50 MHz fit and caption pipeline

`quartus-20260921-151039-e5e123` (b02ac1e) finishes in 29m29s with 33921
ALMs, 453 RAM blocks and 66 DSPs. Its single reported failing check is slow
-40 C video setup, -0.117 ns, from floppy-overlay x[0] through its caption
font logic. All other reported checks are nonnegative. The build was not
deployed. It predates the floppy-bundle and newer video/framework changes.

The caption now splits coordinate division and glyph selection over the
two existing internal stages, retaining the same three-clock output latency
as the animated sprite. All 59 GIF frames and wrap, dots, D0/D1 labels,
hold/disable, crop/mode placement, CE/sync and 56576 continuous/bursty pixel
checks pass. Its FPGA timing is still pending.

### September 21 afternoon follow-up

The full FPGA memory profile was restored at 15:43:04 and reloaded at
15:43:58. The 15:47:12 capture confirms the game menu. Doom II was selected
at 15:49:23. At 15:51:56 it reports pc9821.drv and reaches zone-memory
initialization; the 15:56:47 capture contains orange horizontal stripes,
not usable game graphics. This is not a playable-Doom result. The video
subsystem does not yet implement the complete PC-9821/PEGC feature set.
The verified Bundle50/profile launcher was reloaded at 16:09:11.

The earlier full 60 MHz snapshot quartus-20260921-152915-dea3d1 (7f6ad16)
finishes in 27m57s but has ten failing checks, worst -1.584 ns. All-corner
reports identify remaining GDC plane/address controls into SDRAM, scaling
options and floppy activity into video, plus a floppy-RAM output hold path.
CPU-internal setup is -0.031 ns and the system path is -0.211 ns. This build
predates both the decode-buffer and caption fixes and was not deployed.

The decode-buffer CPU-only 66 MHz probe finishes but fails setup by 1.221 ns;
its Fmax is 61.08 MHz compared with 59.32 MHz before the change. The critical
path now goes through segment access checking to memory-write completion.
This is an isolated virtual-I/O result, not complete-core timing or a
hardware clock setting. The complete uncached regression passes with
434005 ALU cycles and 112340 VRAM cycles.

The next GDC payload includes address, bank and byte/plane masks, retaining
the same request/ACK protocol. Scaling settings are registered in the
video domain before arithmetic, and floppy activity is registered in the
CPU domain before its existing overlay synchronizer. Memory regressions
and all scaling/crop/overlay cases pass. The FEC RAM port-B read is also
registered in its RAM clock; its existing transfer wait covers the latency
in 24 real-controller/latency-model tests, with a stale-data negative.
All these changes await complete FPGA timing and hardware validation.

The decode/caption full 60 MHz snapshot quartus-20260921-155027-b6f840
(5bab734) completes in 30m58s with 34208 ALMs, 453 RAM blocks and 66 DSPs.
It fails 15 timing checks, worst -1.690 ns; it was not deployed. CPU-internal
setup improves to +0.373 ns and same-system-clock setup is +0.041 ns. The
incoming CPU paths still fail by -0.300 ns (SDRAM return/completion signals).
Remaining failures include GDC controls, CPU palette data into video and
OSD/floppy-buffer hold paths. The next source already addresses GDC metadata,
scaling/activity inputs and the floppy buffer; its fits are separate.

Rusty launched from the Bundle50 writable image at 16:15:00 reaches the
coherent illustrated intro captured at 16:17:47. The simplified package
launcher without the diagnostic D1 carrier was loaded at 16:19:24 and reaches
the FPGA-profile menu at 16:22:14. The private installation ZIP contains the
verified Bundle50 RBF, owner ROM, pristine VHD, loader, scoped configuration
and that launcher. Archive CRC and all payload SHA-256 checks pass. Nothing
from the ROM/DOS/game package is included in source control.

### Metadata50 timing and isolated CPU comparison

`quartus-20260921-161512-c13500` (8a64ed1) completes in 32m57s with
33925 ALMs, 453 RAM blocks and 66 DSPs. All reported timing checks are
nonnegative; minimum reported slack is +0.075 ns. It includes CPU decode
and segment changes, completed-read capture, GDC/floppy data bundles,
registered FEC-buffer output, video settings and the caption pipeline.
It predates the palette and OSD settings changes. Board-I/O constraint
coverage remains incomplete.

The RBF SHA-256 is
`1f231364079a8d5fe75c3331e3db717a37c40dc20ff4579cdd7edcbd07807bdc`.
An isolated FM diagnostic on this build was loaded at 16:50:33 device time.
The 16:53:04 capture and returned Z98FM.TXT confirm 100 timer-B IRQ12
deliveries, status assertion/clear and cascaded PIC EOI. The test is silent;
real music quality remains unverified. The private hard-disk/profile launcher
was loaded at 16:55:41 for the next boot/XMS check. Bundle50 remains available
as the fallback.

The segment-change CPU-only 66 MHz fit regresses to 59.55 MHz Fmax and
-1.642 ns worst setup, versus 61.08 MHz / -1.221 ns for decode-only.
The worst path moves to read_commands through readiness and decode logic.
This is not evidence of faster hardware. A separate probe with physical
register retiming disabled is in progress; no production setting changed.

The Bundle50 package launcher without a D1 carrier launches Rusty at
16:33:44 and shows a coherent castle intro in the 16:41:01 capture.
Still images do not measure gameplay frame rate or audio quality.

### Metadata50 hardware and Metadata60 remaining paths

Metadata50 reaches the DOS 6.20 FPGA-profile game menu at 16:57:21 and
passes the full-memory XMS test at 16:59:05. Z98XMS.TXT on the returned
carrier confirms 63424 KB free, a 17 MB allocation at 01000000h, copy/verify
at both ends, unlock/free and recovery of free RAM. The source picture is
640x400 with a 1728x1080 viewport. These are functional checks, not FPS or
physical-output stability measurements.

The matching 60 MHz fit `quartus-20260921-161509-9f7a22` finishes in
40m54s but fails six setup checks, worst -1.013 ns. All reported hold,
recovery and removal checks pass. Detailed paths show palette-to-video
-1.013 ns (addressed by the later palette stage), CPU-internal -0.372 ns,
same-CPU-domain -0.640 ns, and FEC address-to-RAM -0.443 ns. The CPU paths
now start at rd_cmdex and end at TLB linear address / memory bridge high_half.
This candidate was not deployed.

The FEC buffer's port-B clock now follows FECcont's cpuclk in the Zet98
integration. Both buffer users and the address/write controls already run
there. This removes the CPU-to-100-MHz address crossing while retaining
registered RAM output and existing FEC waits. The real controller plus a
RAM-latency model passes all 256-word write/refill/write checks at
20/40/50/60/90/100 MHz, in both same-clock operation and four phases of the
legacy 100 MHz buffer clock; a stale-output negative test fails as intended.
This is simulation coverage, not proof of a 90/100 MHz FPGA build. Complete
FPGA timing and hardware verification of the clock change remain pending.

The Metadata50 scratch-disk write test was loaded at 17:06:15. Its returned
Z98HDWR.TXT reports full/partial sector writes, CHS/LBA reads and protected
neighbors passing. An independent comparison of the 1 MB image confirms
only sector 17 changed. The original carrier contained no result log.

The palette-stage 60 MHz snapshot `quartus-20260921-163431-94f579`
(db11309) completes in 30m41s but fails seven checks, worst -0.826 ns.
CPU-internal setup is +0.031 ns. Remaining paths include OSD settings
(-0.826 ns), CPU SDRAM address/masks (-0.678 ns), FEC buffer address
(-0.456 ns) and graphics line-buffer input hold (-0.254 ns). It was not
deployed. The subsequent OSD, complete CPU metadata and FEC clock changes
address the first three categories; graphics input hold still needs review.

After the scratch test, Metadata50 returned to the simplified private VHD
launcher at 17:13:54. The 17:17:12 capture shows the game menu with the
activity overlay correctly absent while idle. Rusty was selected at
17:18:00. Source remains ahead of hardware: the currently tested RBF is
8a64ed1; later palette, OSD, parallel segment sums, CPU metadata, FEC clock
and graphics input-capture changes need their own passing fit and tests.

The 17:19:39 capture confirms a coherent Rusty castle intro on Metadata50
from the simplified writable-VHD launcher. This validates the startup
path on that build; gameplay FPS and audible music remain unmeasured.

### MIDI50 guest test and physical UART placement

The MIDI50 RBF from `quartus-20260921-175150-60ecc2` (e94b42e) uses
34025 ALMs, 455 RAM blocks and 66 DSPs. Reanalysis of the identical fitted
netlist with the corrected graphics input-capture endpoint (3160a61) passes
all sixteen corner/type timing checks, minimum +0.091 ns. Original reports
using the obsolete line-buffer endpoint are retained separately. Board-I/O
constraint coverage remains incomplete. RBF SHA-256:
`8aa2024c6a6307f17f82542b99142b58df400b203ae3e724ad126444ae9e6718`.

The disposable MPU diagnostic was loaded at 18:35:13 device time. Its
18:39:57 screenshot and returned Z98MPU.TXT confirm 200 ACK/IRQ6 deliveries
and EOI. A separately configured HPS capture received zero bytes; this is
not a MIDI playback pass. Quartus's fitted atom database identifies the
cause: the unassigned UART was placed at Y66 (UART0), instead of MiSTer's
required Y67 (UART1). An explicit project assignment and a post-fit guard
have been added; the guard rejects the old netlist. No Linux UART pinmux
registers were modified. The corrected build awaits fit and hardware capture.

Independent private NP2kai testing of Nightslave observes only UART-entry
and reset commands, with 6335 bytes in the final UART session. Replaying
that session through the actual MPU RTL and an independent 31250-baud
decoder passes without dropped/reordered bytes or overflow. Game/music
data remain private; this is protocol coverage, not FPGA audio validation.

The complete-metadata 50 MHz fit (126dcd2) also passes all timing corners
with minimum +0.093 ns. Its 60 MHz counterpart fails by -0.415 ns. Corrected
graphics-capture and compositor 60 MHz analyses still fail by -0.316 ns and
-0.613 ns respectively; none were deployed. The next 60 MHz snapshot
(8040277) stages framebuffer viewport controls and is still fitting.

That viewport 60 MHz fit subsequently completes in 30m50s, but fails five
summary checks, worst -0.760 ns; it was not deployed. A separate CPU change
removes system-read length decoding from virtual segment checks. Yosys proves
the new and original lengths equal for every command input whenever segment
checking is active; a wrong byte length produces a counterexample. Cached
and uncached full-CPU regressions pass (576 bus transfers each). A new fit
is needed to measure the effect on the read-command-to-TLB critical path.

### Stack-memory optimization and benchmark v3

The conventional-RAM cache now allocates completed full-word writes, while
partial writes still invalidate their slot and every write reaches SDRAM.
Standalone 8/32/64 KB tests and full-CPU coherence/ALU/VRAM/stack checks pass.
Against the previous policy on the same CPU source, the 128-iteration stack
kernel improves from 6420 cycles / 273 bus transfers to 5268 / 145; ALU and
VRAM measurements are unchanged. This is simulation evidence, not Rusty FPS.
The new 50 MHz fit includes this change and has not yet been hardware-tested.

DOS benchmark v3 adds a 131072-iteration stack block to the unchanged ALU and
RAM-copy kernels, checking every popped value and the final stack pointer.
It retains at least ten reported seconds per kernel. An independent x86/DOS
model verifies all three checksums, exact log saving and hour rollover, and
rejects a deliberately wrong POP instruction. The 843-byte program fits the
existing disposable BOOT.COM allocation. No source disk sectors outside that
file were changed. The Metadata50 baseline was loaded at 19:15:16 device time;
its result remains pending. The core had previously returned to the DOS 6.20
game menu at 19:02:19, confirmed by the 19:06:37 screenshot.
