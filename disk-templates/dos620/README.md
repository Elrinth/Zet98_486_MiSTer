# Private DOS 6.20 game disk templates

These text files configure the user's NEC PC-98 MS-DOS 6.20 installation.
No DOS kernels, drivers, game files or disk images belong in this directory.
The tested private image is a raw 512-byte-sector hard disk, booted as `A:`.
Its original PC-98 IPL, partition table and DOS system files are preserved.

Copy the templates and `PROFILES` directory into the image's root. Keep the
original `CONFIG.SYS` and `AUTOEXEC.BAT` under `Z98BACK`, and create `TEMP`.
The image needs the user's PC-98 versions of `DOS/HIMEM.SYS`, `EMM386.EXE`,
`CHOICE.COM`, `MEM.EXE` and `FC.EXE`; the optional VEM profile also needs
`TOOLS/VEM486.EXE`.

The default is HIMEM with DOS in high memory. `GAMES.BAT` offers Rusty,
Nightslave, Doom II, Doom setup, memory details, profile selection and a shell.
The tested installations use these paths:

- `GAMES/RUSTY/BOOT.COM`: the user's English Rusty launcher.
- `MELODY/NS/NSS.COM`: Nightslave's original launcher.
- `GAMES/DOOM2/DOOM2.EXE` and `SETUP.EXE`: the PC-98 Doom II installation.

`PROFILE.BAT` selects HIMEM, no memory manager, EMM386 upper memory, EMM386
with EMS, VEM486 upper memory, or a minimal shell. The selection changes
`CONFIG.SYS` for the **next core reset**; it cannot change already-loaded
memory managers in the current DOS session. The active profile comes from
`SET CONFIG=...` in that boot's configuration. A previous configuration is
saved as `Z98BACK/PREVIOUS.SYS`; `FC /B` verifies both copies because NEC
COMMAND.COM's successful COPY can retain CHOICE's nonzero error level.

The initial IBM-compatible MENUITEM/INCLUDE configuration did not select a
profile on the supplied NEC DOS installation. These flat configurations and
the explicit next-reset selector were tested against that installation.

NP2kai software-emulator checks on 2026-09-21 reached Rusty's English intro,
Nightslave's title screen and Doom II's running demo using the default profile.
All six profiles reached their memory report or minimal shell. HIMEM reported
65,994,752 bytes of free XMS and a 608,704-byte largest DOS program block.
VEM booted, but NEC MEM displayed inconsistent extended-memory totals with
64 MB configured; keep that profile experimental. Audio was not measured.

Software-emulator boot checks do not establish FPGA compatibility. The
current core's extended-memory BIOS initializer/HIMEMX setup is separate
(see [software/README.md](../../software/README.md)). The EMM386/VEM profiles
remain experimental on FPGA. No resident mouse, CD, MIDI or sound-board
initialization driver is automatically installed by these templates.

A BIOS-first diagnostic floppy now boots the private DOS 6.20 VHD on Native50
and reaches this menu and Rusty's illustrated intro. This is still a fixed-image
read-only experiment, not general ROM-based HDD boot. Profile changes and game
saves cannot work with that read-only loader. A separate write-enabled
Bundle50 test now passes DOS file creation and independent image comparison;
individual games' save behavior remains to be tested.

The additional `PROFILES/FPGA.SYS` uses `Z98MEM.SYS` and the PC-98 HIMEMX
driver instead of the old BIOS's memory report. It requires the optional
16/64 MB ao486 build and those separately supplied drivers. On Native50 the
separate private VHD copy boots with a 608,912-byte largest conventional
block and passes direct 17 MB XMS allocation, copy, verification and free.
NEC MEM reports zero XMS despite this passing API check. Keep EMM386/VEM disabled with the
current resident disk BIOS; they may reuse its D8000-DFFFF RAM area.

For a writable FPGA test image, install `FPGA_MENU.BAT` as `PROFILE.BAT`.
It selects the full HIMEMX profile, `LIMITED.SYS` (14 MB including HMA),
`CONV.SYS` (conventional memory only), or the existing bare shell. It keeps
the same backup and byte-comparison workflow. HIMEMX's `/MAX=14336` limits
what the memory manager exposes; it does not change the FPGA's physical RAM
map. The limited/conventional profile boot checks are still pending.
The emulator-oriented EMM386/VEM menu should not be installed with the
current resident HDD BIOS.
