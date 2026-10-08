# Testing an original NEC BIOS on MiSTer

Use the recommended **75 MHz B248** core (or a later compatible release) for
the PC-9821 bank, shadow-RAM and software-DIP fixes. B247 does not boot the supplied Ce2 and unknown-model PC-9821 dumps.
OpenBIOS remains the default in the download bundle. To try original NEC
firmware, supply your own matching ROM files and pack them as described here.
The project does not include NEC ROM contents.

The supplied **PC-9821Ce2** and **unknown-model PC-9821** sets boot MS-DOS 6.20
and pass ROM-integrity, bank and GDC probes on both the recommended **75 MHz
B248** and the **90 MHz experimental** image. The 90 MHz image faults in Linux
and is not the recommended download.
Ce2 is the model actually tested; this does not establish compatibility of
every PC-9821Ce dump, every file labelled “PC-9821”, or Windows 95.
See [validation and remaining limitations](BIOS_GUIDE.md).

The tested packed files have these SHA-256 fingerprints:

- Ce2: `820ca8ea8bc0133c0df5e3aafb158ca528e9c41eeff22818623ab067ff8cecc6`.
- Unknown-model PC-9821: `8fbffdbcad99031fdb4951736d90ab3fdebd23f0a174509ed5e8da25d71c2ea4`.

A different hash can indicate a different dump, font or optional sound ROM.
Record it when reporting results; these fingerprints do not identify every
dump from the same machine model.

## 1. Prepare one matching ROM set on your computer

Download `PC98_Official_BIOS_Tools_B248.zip` from the core release and extract
it. It contains `pc98_pack_bios.py` and these instructions, without ROM data.
Install Python 3.8 or newer if it is not already available.

Your ZIP or extracted folder must contain these components from the same
machine. Names are case-insensitive:

- `bios.rom`: **98,304 bytes**, the system BIOS.
- `itf.rom`: **32,768 bytes**, the startup firmware.
- `font.rom`: **288,768 bytes**, the character generator.
- Optional `sound.rom`: **16,384 bytes**, the sound-board BIOS.

For folder input, select the folder that directly contains these files.
A ZIP may contain subfolders, but must contain only one copy of each component.

Use the actual `itf.rom` from that set. Do not substitute another model's ITF
or a copy of the BIOS tail. An archive missing ITF is incomplete for this
procedure. `FONT.BMP` is not accepted.

From PowerShell in the extracted tools folder, run either:

```powershell
python .\pc98_pack_bios.py "C:\ROMs\NEC PC-9821Ce2 [ROM].zip" ".\boot.rom"
```

or, for an extracted Ce2 or unknown-model PC-9821 folder:

```powershell
python .\pc98_pack_bios.py "C:\ROMs\PC9821" ".\boot.rom"
```

The output must be **550,912 bytes**. The tool reports its SHA-256 and refuses
to overwrite an existing output. Move your previous output aside before
packing a different set. Save the hash with the model name for comparisons.

If your dump has both `BIOS.ROM` and a 98,304-byte `BOOT.ROM`, pass the ZIP
or folder containing `BIOS.ROM`, `ITF.ROM` and `FONT.ROM`. The converter uses
`BIOS.ROM` and ignores that small `BOOT.ROM`; it does not take a single
component file as its input. The 98,304-byte file is not a complete MiSTer
`boot.rom`. Do not rename it and put it on the MiSTer directly.
Do not concatenate the components. The converter adds the required offsets
and padding; it does not patch the NEC firmware.

## 2. Put the files in the correct MiSTer folders

Use the separate core download, rather than extracting the full OpenBIOS
bundle over a NEC BIOS you want to keep.

1. Put `PC98_Z486_75_B248_20261008.rbf` in **`/media/fat/_Computer/`**
   (the SD card's `_Computer` folder).
2. Back up the existing **`/media/fat/games/PC98/boot.rom`** on your computer.
3. Copy the newly packed **550,912-byte `boot.rom`** to
   **`/media/fat/games/PC98/boot.rom`**, replacing that one file.
4. Select the B248 core from MiSTer's Computer menu. If the core is already
   running, return to the MiSTer menu and load it again. **OSD Reset alone
   does not reload `boot.rom`.**

The core reads this single packed file. It does not load the ZIP or separate
`bios.rom`, `itf.rom`, `font.rom` and `sound.rom` files from that folder.
No changes to `MiSTer.ini` are required for BIOS selection.

These paths apply to the ordinary PC98 core. A custom MGL with a different
`<setname>` can select a different game/configuration folder; put `boot.rom`
in the folder selected by that launcher or use the ordinary core menu for
this comparison.

## 3. Check DOS before trying a game

Use a copy of a known-bootable **PC-98** DOS disk. Mount it as **IDE hard disk**, or mount
the appropriate DOS floppy as FDD 0. A PC-compatible DOS/Windows boot disk
is not a substitute for PC-98 media.

For games expecting the slower graphics-controller clock, open F12 and set
**DIP2-8 GDC clock: 2.5MHz**, then reset the core. B248 makes that OSD setting
visible to the PC-9821 BIOS's software-DIP readback too. Reset is required
after changing the setting. Select 5 MHz only when your program requires it.

Allow POST and DOS boot to complete, then type `DIR` and verify that the
directory appears. A logo or DOS banner alone is not a responsive-DOS test.
Keep the same disk, memory-manager configuration and clock settings when
comparing Ce2, unknown-model PC-9821 and OpenBIOS.

BIOS software settings survive CPU/OSD Reset but are lost on a full FPGA
reload. Hardware beyond the core's implemented devices, including a real
PCI bus, is not provided. Hunt and Windows 95 desktop startup remain
unresolved. Sparse remote screenshots can omit text; check the physical
display before concluding that boot has hung.

To return to OpenBIOS, restore the backed-up `boot.rom` to
`/media/fat/games/PC98/boot.rom`, return to the menu and reload the core.
For a report, include the core version, BIOS model/hash, disk format, GDC
setting, memory manager and last visible screen.
