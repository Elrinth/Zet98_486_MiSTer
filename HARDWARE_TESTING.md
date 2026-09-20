# Hardware testing

Test device: SuperStation One with SuperDock and 128 MB SDRAM. The initial
test system uses ConsoleMode's MiSTer executable (ConsoleMode 1.1.4.2).
The TV is connected by HDMI through a switch box. The user reports stable
Console Mode output with HDR; keep that connection as the control during core
video debugging. The inspected profiles use `direct_video=0`, `video_mode=0`
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

The user's immediate priority is now fixing video corruption in the core.
The next diagnostic build uses Zet to isolate video changes. It includes a
registered video-output stage, a cheaper text scanline calculation, and OSD
`Video test: Color bars` (status bit 3). The pattern bypasses PC-98 text,
graphics and SDRAM fetches, but uses the same video PLL, scaler and HDMI path.
It runs without waiting for the PC-98 BIOS. Full-screen scaling is also present
in that source. Hardware results are pending.
The first video-test snapshot is `build/quartus-20260921-004058-4b8287/source`.

Keep BIOS, disks and settings identical when comparing Zet and ao486.
Still required: reliable complete floppy/game loading, Rusty gameplay,
repeatable scene timing, sound pitch/tempo, and video stability. Neither the
initial logo nor successful FPGA fitting measures Rusty speed.
