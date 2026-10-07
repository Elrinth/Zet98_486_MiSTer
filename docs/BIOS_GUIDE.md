# Choosing and packaging a BIOS

**OpenBIOS is recommended, but it is not mandatory to use the core.** A
known-working NEC PC-9801VM-based `boot.rom` still boots MS-DOS on B247. You
need both B247 and OpenBIOS 2026-10-07 specifically for the newly verified
Sword Dancer floppy media-change fix. B247 does not disable NEC BIOS support.

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
compatible**. The Ce2 example currently fails the boot test below. Use your own
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
models. The failures are not solved by concatenation. Their precise hardware
failure point remains unconfirmed; no speculative core patch is included.
The Ce2 software-model probe remains in ITF initialization and is diagnostic
only. NP2kai boot success cannot by itself prove native MiSTer compatibility:
the emulator supplies BIOS/ITF services that differ from running the actual
firmware against this FPGA hardware. See [NP2kai's source and ROM setup notes](https://github.com/AZO234/NP2kai).

For a bug report include the core version, BIOS model and SHA-256, disk image
format, memory-manager configuration and the last visible screen. Do not
attach copyrighted ROM files to a public issue.
