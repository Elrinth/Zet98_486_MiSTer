# Choosing and packaging a BIOS

**OpenBIOS is recommended, but it is not mandatory to use the core.**
Use the recommended 75 MHz B248 core with OpenBIOS 2026-10-08. B248 also
adds support for the supplied original Ce2 and unknown-model PC-9821 sets.
The known-working NEC PC-9801VM-based `boot.rom` remains an alternative.

For testing the supplied Ce2 or unknown-model PC-9821 set with the new core,
follow the [original NEC BIOS setup instructions](OFFICIAL_BIOS_SETUP.md).
The B247 failures below are historical controls; the later development
candidate results are recorded separately.

## B248 release qualification, 2026-10-08

The full-feature 75 MHz recommended and 90 MHz experimental B248 images
boot the supplied unmodified Ce2 and unknown-model PC-9821 sets into
MS-DOS 6.20. Each passes the full 96 KiB ROM
rotate/XOR integrity checks against its source dump, the bank-1 POST return and
resident-RAM preservation probe, and a DOS `DIR` command. Fresh guest completion
markers distinguish these runs from earlier candidate logs.

At the default 2.5 MHz setting, both read PPI31h=F3h, SDIP851Eh=E3h and
BDA054Ch/054Dh=4Fh/50h. The separate 75 MHz candidate tests below also cover
5 MHz readback and four native-BIOS games; those game tests are not a claim
that all games were rerun with the final release images.

Fresh OpenBIOS 2026-10-08 passes both images' DOS qualification
with plain HIMEM and no legacy metadata helper: four division rounds, 4,008
string cases, conventional RAM and 16 MiB XMS with zero errors, and 512 EGC
alignment cases (11,904 plane checks). All nine BIOS regression groups pass.
The rebuild uses the existing firmware with equivalent NASM XCHG encodings;
firmware functionality is unchanged from 2026-10-07. The exact recommended
75 MHz bitstream also passes Linux fault-restart checks and 100 normal
process launches/exits, verified with a fresh guest completion marker.

The recommended image completes a full Doom `demo1` timedemo with plain
HIMEM and sound/music/SFX disabled, then returns normally to DOS: 11,520
gametics in 1,926 reported realtics. The monitored game interval is about
816.5 seconds. These PC-98 counter values are not interpreted as absolute FPS;
this lower-clock build is not a performance upgrade.

The three supplied game images were also checked with the exact recommended
75 MHz bitstream and fresh OpenBIOS. Alone in the Dark 2 responds to its
mode/New Game menus and renders the opening 3D sequence; player movement
remains unqualified. Cyberillusion accepts mouse selection of New Game,
opens character/name registration and advances its registration help with
clicks. Toushin Toshi II boots its 256-byte-sector HDI directly, responds to
Game Start and reaches the hint-mode choice. These are limited progression and
interaction checks; audio and full playthroughs are unqualified. The 90 MHz
image also reached the three games' menus/openings, but its Cyberillusion
game-start test was not completed.

The final Windows 95 attempt on the recommended 75 MHz image reaches the
graphical wizard, license, repair/directory preparation, Typical setup choice
and OEM Certificate of Authenticity key screen. The disposable DOS image uses
HIMEM, `TEMP`/`TMP=A:\TEMP` and a 2,048-byte command environment; the original
SETUP executable and cabinet files are preserved. A user-supplied OEM key is
required to continue. Windows desktop startup remains unverified and DirectX
has not been attempted. The earlier reduced-feature 75 MHz control also reaches
the key screen; its result is separate from this full-feature qualification.

The 90 MHz image repeatedly faults in Linux and is distributed separately
as **experimental**. A B246/2026-10-06 control passes the same Linux check.
The earlier 75 MHz candidate also boots Linux, but disables packed graphics
and native DDR; it is not the full-feature release qualification. The cause
of the 90 MHz failures is not established. B248 lowers the recommended CPU
clock from 90 to 75 MHz; no performance gain is claimed.

The recommended build uses Quartus 17.0.2 build 602, PR2, IC32/DC8, 64 MiB RAM,
seed 7, normal packing, packed graphics, raw IDE, MIDI UART, JT08 and
native-DDR framebuffer: **41,405 ALMs / 4,190 LABs**, 43,983 registers,
552 M10Ks and 67 DSP blocks. Worst slack is **-5.660 ns** with four negative
timing summaries, within the maintainer's accepted 12 ns magnitude allowance;
static timing is not closed.

The experimental 90 MHz build uses PR2, IC32/DC8, 64 MiB RAM, seed 12, normal packing,
packed graphics, raw IDE, MIDI UART, JT08 and native-DDR framebuffer:
41,535 ALMs / 4,191 LABs, 43,411 registers, 552 M10Ks and 67 DSP blocks.
Worst slack is -7.628 ns with ten negative timing summaries, within the
maintainer's accepted 12 ns magnitude allowance; static timing is not closed.

Recommended 75 MHz RBF SHA-256:
`4bbe73870e8fd2bf2f8b8602f7557fa8f2b2308bb302a54a4ebb5c075c91146d`.
Experimental 90 MHz RBF SHA-256:
`8ca73f521c0ffabb05ffe6162f44ad78d9931790897b1a691d492cae480e58fd`.
OpenBIOS SHA-256:
`671acbafb4a7baf5ffb69d740ccfd4cf9dc94d840b2b7881a20bf595621fd4f2`.

## Why OpenBIOS is the recommended default

OpenBIOS is built and tested for this core's 486 CPU, extended-memory map and
graphics hardware. Its code and font are freely licensed, it is included in
the ready-to-copy bundle, and compatibility bugs can be fixed in this project.
Recent checks include Policenauts with smooth PCM, N88-BASIC games, and Sword
Dancer's disk changes with the matching core. These are specific validations,
not a claim that every program works better than on every NEC BIOS.

## Why the old Zet98 BIOS recommendation does not carry over unchanged

The traditional PC-9801VM ROM was written for a V30 machine, not a 486/PC-9821.
It sets the V30 identification bit and does not discover this core's extended
RAM or provide a PC-9821-era firmware environment. Without corrections, this
can prevent HIMEM from loading or lead software to select an unsuitable path.

Current releases already compensate for several of these issues in the disk
extension ROM: `software/z98mem_probe.inc` publishes extended RAM at 0401h and
0594h, clears the V30 bit at 0501h and sets the 386+ CPU class at 0480h. Thus
**it would be incorrect to say that HIMEM never works with NEC BIOS on B247**.
These corrections do not turn a VM BIOS into a complete PC-9821 BIOS. The
documented Ultima VIII comparison showed stripes with the VM ROM, while the
matching OpenBIOS reached input and gameplay. Other games work with either.
Windows 95/98 desktop startup remains unresolved; switching BIOS is not a
promised fix for it.

An old downloader's recommended ROM is a recommendation for its original
core/configuration, not a universal PC-98 firmware. Different files named
`boot.rom` can contain different BIOS and font data. Preserve a working ROM
and record its hash before comparing.

## Separate bios.rom / itf.rom / font.rom files

The MiSTer core loads one `games/PC98/boot.rom`, **not a ZIP or separate NP2 ROM
files**. Use the layout converter supplied in this repository (Python 3.8+):

```powershell
python scripts/pc98_pack_bios.py "NEC PC-9821Ce2 [ROM].zip" "boot.rom"
```

Or, for an extracted directory:

```powershell
python scripts/pc98_pack_bios.py "C:\my-rom-dump" "boot.rom"
```

This produces a file with the correct layout; **it does not make that NEC model
compatible**. The Ce2 example fails the B247 boot test below; B248 boots it
with the hardware fixes described above. Use your own
ROM dump; neither this script nor the project provides NEC ROM contents.

Required files, with case-insensitive names:

- `bios.rom`: 98,304 bytes, placed at output offset 0x00000.
- `itf.rom`: 32,768 bytes, placed at 0x18000. This is the startup bank, not
  generally a duplicate of the system BIOS. Do not substitute another model's
  ITF or automatically copy the BIOS tail when the dump lacks it.
- `font.rom`: 288,768 bytes, placed at 0x40000. FONT.BMP is not supported.
- Optional `sound.rom`: 16,384 bytes, placed at 0x20000. Otherwise that region
  remains zero. This sound BIOS does not supply missing motherboard hardware.

The output is exactly 550,912 bytes, with zero-filled unused space. A simple
`copy /b bios.rom+font.rom+itf.rom+sound.rom boot.rom` is incorrect. The script
rejects wrong sizes, duplicate component names, missing required files and an
existing output file. It reads ZIP members without extracting their paths.

Back up `/media/fat/games/PC98/boot.rom`, copy the new file there, and **reload
the core completely**. An OSD reset alone does not reload the file. Keep the
same disk and settings for comparison. Restore the backup and reload if the
new BIOS does not boot. Use separate downloads instead of extracting the full
OpenBIOS bundle over a NEC installation you intend to keep.

## B247 hardware results, 2026-10-07

Tests used the released 90 MHz B247 bitstream, the same isolated MS-DOS 6.20
HDD image and normal settings. Complete archives were converted with the
script above, including sound.rom when supplied. After a fresh core load and
35-second observation:

- Known-working PC-9801VM `boot.rom`: **DOS prompt reached**. SHA-256
  `647b5fa95a1a55096728829b74d4729e45adfd49d8e3a86aabf486a042f21db7`.
- Supplied PC-9821Ce2, PC-9821 unknown model, PC-9801UX, PC-9801 unknown model,
  and PC-9821V20 sets: **no usable BIOS/DOS screen**. Some show small coloured
  blocks at the lower edge. These sets are not recommended for B247.
- Supplied PC-9821V13 ZIP: missing `itf.rom`; **incomplete for this conversion**,
  so no fabricated ITF or hardware compatibility claim is made.
- OpenBIOS 2026-10-07 is restored after testing.

These are results for the supplied dumps, not a claim about every dump of those
models. The failures are not solved by concatenation.
NP2kai boot success cannot by itself prove native MiSTer compatibility:
the emulator supplies BIOS/ITF services that differ from running the actual
firmware against this FPGA hardware. See [NP2kai's source and ROM setup notes](https://github.com/AZO234/NP2kai).

## UX investigation after B247

The supplied PC-9801UX firmware stops with `PROTECTED MODE ERROR`. Its CPU
self-test reads a word from a segment whose limit permits only one byte and
expects a general-protection fault. The core's accelerated load path could
bypass that limit check. A self-authored 16-bit protected-mode regression
reproduces the missing fault on the unmodified CPU RTL.

The candidate core fix admits accelerated reads only for readable ordinary
64 KiB/4 GiB segments containing the whole access. Other cases use the existing
microcode protection checks. The reproducer and 236 boundary cases pass with
the fix. The resulting 90 MHz candidate also boots the **untouched PC-9801UX
ROM to MS-DOS 6.20 on MiSTer**, with keyboard input and `DIR` verified. OpenBIOS
2026-10-07 also boots on this candidate. No BIOS patch is needed or distributed.

Candidate build: `quartus-20261007-134406-6f11c9`, 64 MB, PR2, IC32/DC8, MIDI.
It uses 41,349 ALMs, 4,185/4,191 LABs and 552/553 M10Ks. Worst slack is
-7.771 ns, inside the project's accepted <12 ns negative-slack allowance;
this does not mean timing closure. Candidate RBF SHA-256:
`6065d7e90d7fda3c01faccc541311a8fbcfe7bcdcf18eabd6f5416c09305d80b`.
UX packed-ROM SHA-256:
`ec53fa0bca36269549bd0e8f0c32f40ac126c49985ee4afd0679e43190564ef5`.

This candidate is not B247 and has not been released. The supplied Ce2, V20,
unknown-model PC-9801 and unknown-model PC-9821 still do not reach DOS after
fresh loads and roughly two-minute observation windows on this candidate.
UX boot success is not
a claim of complete game/OS compatibility. OpenBIOS is restored after testing.

## NP2kai comparison, 2026-10-07

All five complete supplied sets reach the same MS-DOS 6.20 prompt in NP2kai
`5939e0c6d5985c4c08fc70f289a83290e5d3e6f7` with suitable settings and enough
boot time. Tests use the exact BIOS/font/sound/ITF components, i486SX emulation,
and the same raw DOS disk wrapped in an HDI header (512-byte sectors, 17 sectors,
8 heads, 8,162 cylinders):

- UX and unknown-model PC-9821: VM model, 3,600-frame run.
- Unknown-model PC-9801 and V20: VM model, 9,000-frame run. Earlier
  3,600-frame snapshots showed only the beginning of the DOS banner.
- Ce2: VX model, 7,200-frame run. A 9,000-frame VM run still showed only `NEC`.

These results confirm useful emulator configurations, not unmodified NEC POST
execution. Normal NP2kai defines `BIOS_SIMULATE`, loads `bios.rom`, patches BIOS
services, and replaces the ITF startup image with its built-in `itfrom` data.
The external `itf.rom` loader is in the alternative compile-time branch; merely
putting that file beside NP2kai does not activate it. See
[NP2kai bios.c](https://github.com/AZO234/NP2kai/blob/5939e0c6d5985c4c08fc70f289a83290e5d3e6f7/bios/bios.c).
The core executes the supplied ITF, so hardware tests remain necessary.

For a bug report include the core version, BIOS model and SHA-256, disk image
format, memory-manager configuration and the last visible screen. Do not
attach copyrighted ROM files to a public issue.

## PC-9821 investigation after B247 (candidate, not released)

Native Ce2/PC-9821 POST exposed several missing hardware behaviors beyond the
UX CPU-protection fix:

- Software DIP storage at `841Eh..8F1Eh`, its bank selector, and DSW2 readback.
- `F0h` CPU-status readback appropriate for the 486 configuration.
- A writable `0439h` readback latch. The old implementation forced bit 3 high,
  preventing the firmware from reading back zero before its startup restart.
- `043Dh` commands `00h/02h`, aliases of the existing `10h/12h` ITF-bank commands.
- ROM-to-shadow copies through the banked memory windows. The old mapper wrote
  back into ROM storage; enabling RAM at `053Dh` then exposed an unpopulated
  shadow. A Ce2 diagnostic trace passes the first ROM checksum and fails the
  second checksum after this switch.

The register, bank and shadow-copy regressions pass in simulation. The original
bank decoder and mapper fail the new regressions. The candidate now boots the untouched Ce2 and unknown-model PC-9821 ROMs
to DOS on MiSTer, as detailed below. This is limited boot qualification, not
a claim that every PC-9821 peripheral or game is supported. Private firmware controls are used only to isolate faults,
and are neither distributed nor treated as successful original-BIOS boots.

The self-authored `tests/hardware/pc9821_boot_controls.asm` now passes on
MiSTer (`OUT 80h = A55Ah`), including ROM preservation and shadow readback.
The previous diagnostic core fails its first register check (`E001`). With
the fixes, the untouched Ce2 reaches the MS-DOS banner. The unknown-model
PC-9821's apparent disk-extension error was later traced to execution of
retained D800 RAM before extension discovery (see below). The earlier
reduced-cache diagnostic builds also fail DOS startup with OpenBIOS.
The later 32 KiB-cache candidate described below reaches a responsive prompt
with both original PC-9821 ROMs.

A further hardware control identified an internal firmware-bank collision in
the unknown-model PC-9821: before scanning D000 extension ROMs, it selects
bank 1 through port `063Ch` and calls `D800:000Ch`. The supplied split-ROM ZIPs
have no separate PCI-bank ROM. Without the selector, this executes ordinary
D800 RAM, including a disk-service resident left from a previous boot.
A private RAM-return control gets past this call and reaches the DOS banner.

The current source candidate adds selector readback and an empty bank-1 POST
initializer for the core's configuration without PCI devices. It does not
implement a PCI bus or the other models' complete internal firmware banks.
Register/mapping tests and the original wrapper executed in a private emulator
model pass.

Hardware candidate `quartus-20261007-221549-e92d94` uses Quartus 17.0.2,
75 MHz, 64 MiB, PR2 and 32/8 KiB instruction/data caches. Both original Ce2
and unknown-model PC-9821 ROMs reach DOS 6.20, pass `ROMBANK.COM`, and run
`DIR` after repeated FPGA reloads. A private DOS probe reads the complete
96 KiB system ROM and matches all three 32 KiB rotate/XOR checksums against
the packed source ROM, confirming which firmware is actually executing.
The original ROMs were not patched.

The candidate fits 41,073 ALMs and 4,185/4,191 LABs. Worst reported slack is
-5.669 ns: within the user's experimental acceptance limit, but not timing
closure. Packed graphics and native DDR are disabled in this test build;
this is not yet qualification of the full release configuration. The firmware
bank probe also passes with OpenBIOS and fails on the previous core, as
expected. Full application compatibility remains unqualified. Some direct
MiSTer screenshots intermittently omit text, but repeated OBS HDMI captures
show the complete screen, and the guest attribute probe reads normal E1h
(non-blinking white text). A sparse screenshot alone must not be classified
as a boot hang. This candidate is not released.


### Initial game checks on both original PC-9821 ROMs

The same 75 MHz candidate was tested with both the Ce2 and unknown-model ROMs.
Results matched across the two BIOSes:

- Hokuto no Ken, floppy only: N88-BASIC title and illustrated story work;
  Space advances dialogue and portraits. No HDD was attached.
- Thexder, floppy only (`thexder2.d88`): title, level start, player movement,
  scrolling and enemy interaction work. No HDD was attached.
- Nightslave, HDD: DOS/VEM486 loads, but the game reports a 5 MHz GDC and asks
  for 2.5 MHz before returning to DOS. F12 already shows 2.5 MHz. The native
  software-DIP state can override the legacy OSD input in this candidate;
  this configuration mismatch remains unresolved.
- Teens, HDD: startup and scenario selection respond, but graphics are
  duplicated and scaled incorrectly. A connection to the GDC mismatch is
  suspected, not established.

These are short functional tests, not full playthroughs or audio-quality
qualification. The remaining HDD game failures prevent a broad PC-9821
compatibility claim. Private screenshots and the detailed test manifest are
retained under `build/nec-bios/game-tests/results.json` and `build/egc-dsp/`.


### GDC software-DIP investigation

The GDC selection code is identical in the supplied Ce2 and unknown-model
system ROMs. Both read port 31h bit 7: clear selects the BIOS 5 MHz setting,
set selects 2.5 MHz. Executing the unmodified selection routine in isolation
confirms both paths for both ROMs. Thus the GDC bit has not changed meaning.

Both hardware diagnostics read PPI31h=73h and software-DIP 851Eh=73h,
while F12 shows 2.5 MHz. The Ce2 ROM factory table contains 73h at that position.
`pc98_sdip` starts blank on every FPGA load, lets firmware initialize it, then
uses the stored software-DIP byte instead of the legacy OSD byte. That is why
an OSD change alone can fail to control the native BIOS's GDC setting.

The storage layout does have differences: 851Eh bit 4 is odd parity, whereas
legacy DSW2 bit 4 comes from 871Eh bit 5 (memory-switch initialization). Our
translation follows [MAME's SDIP mapping](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc98_sdip.h).
Changing the GDC storage bit therefore also requires preserving valid parity;
blindly copying the OSD byte into software-DIP storage is not sufficient.

The candidate fix samples the OSD GDC setting during CPU/OSD reset and uses
that value for both PPI and software-DIP readback. When it changes software-DIP
bit 7, it also flips parity bit 4, preserving whether the stored byte is valid.
Blank or corrupt settings therefore still trigger firmware initialization.
Other software settings and the second bank are unchanged. Changing the OSD
GDC setting requires a reset before the firmware sees it.

The SDIP simulation passes all 256 stored-byte values at both clock settings,
reset behavior, and second-bank readback; the previous implementation fails
the new regression.

Hardware validation on 2026-10-08 used the 75 MHz candidate built with Quartus
17.0.2 (`quartus-20261008-001447-590085`, 4,184 LABs, worst slack -5.002 ns).
Both unmodified Ce2 and unknown-model ROMs boot DOS and pass the ROM-bank test.
At 2.5 MHz, PPI31h=F3h, SDIP851Eh=E3h and BDA054Dh=50h; at 5 MHz these are
73h, 73h and 70h. Other software-DIP bytes remain unchanged within each BIOS.
The original configuration was restored after the 5 MHz checks.

With both BIOSes at 2.5 MHz, Nightslave now passes the GDC check and reaches
its intro; Teens' logo, menus and opening story render without the previous
duplication. Hokuto no Ken still advances through its story from floppy, and
Thexder boots from floppy and responds to movement in its first level. These
are limited progression tests, not complete-game or audio qualification.
Private screenshots and diagnostic values are in `build/nec-bios/gdc-tests`
and `build/egc-dsp/PC9821-GDC-*.png`.

Persistent BIOS setup storage is still absent: CPU/OSD reset retains it, but
FPGA reload loses it. This candidate also predates the separate boot-message
branding update and has not been released.
