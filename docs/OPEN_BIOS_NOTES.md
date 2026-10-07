# Notes for an open PC-98 boot.rom

For current BIOS selection and separate-ROM packaging, see [BIOS_GUIDE.md](BIOS_GUIDE.md).
The notes below are historical investigation notes; current releases compensate
for several VM BIOS CPU/memory-identification limitations.

Starting material for a legally distributable replacement for the user-supplied
`boot.rom`. Findings from 2026-09-26; verify before relying on them.

## What the core loads today

`boot.rom` is 550,912 bytes, assembled by `mister_games_downloader`
(`Scripts/.mister_game_downloader/zet98.py`, following puu's `BIOS/mkrom.sh`):

| Offset | Size | Content |
|---|---|---|
| 0x00000 | 96 KiB | System BIOS, mapped at E8000h-FFFFFh |
| 0x18000 | 32 KiB | Last BIOS bank again (ITF bank, mapped at F8000h while ITF is enabled; port 43Ch writes 10h/12h switch it) |
| 0x20000 | 128 KiB | Zeroes |
| 0x40000 | 282 KiB (288,768) | Character generator ROM (ANK + JIS kanji), same format as NP2's `FONT.ROM` |

The BIOS chips are MAME's **PC-9801VM** set (a V30 machine). The known-working
local file has SHA-256 `647b5fa9...42f21db7` (see HARDWARE_TESTING.md).
`tests/z486_boot_probe_tb.sv` shows the address mapping used in simulation.

## Why a PC-9801VM BIOS is wrong for this 486 core

- At F000:DA2Bh it runs `in al,42h / test al,20h / mov ax,6001h / ... /
  or word [0500h],ax`: bit 6 of 0501h (the **V30 flag**) is set
  unconditionally. Stock PC-98 `HIMEM.SYS` 3.10 then refuses to load.
- It never counts memory above 1 MB. HIMEM reads **0401h** (extended RAM
  below 16 MB, 128 KiB units) and **0594h** (MB above 16 MB).
- It does not know about EGC/PEGC or the PC-9821 feature flags.

`software/z98mem_probe.inc` (Z98MEM / the core's disk extension ROM since
B165) patches exactly these three fields after the BIOS runs: 0401h = 112,
0594h = 48 on the 64 MB map, and clears 0501h bit 6.

## What an open BIOS must provide (first-pass list)

- POST: PIC, PIT, DMA, uPD7220 text/graphics GDC, CRTC, keyboard 8251, FDC
  (uPD765), calendar clock (uPD4990), sound-board detection hooks.
- BIOS work area 0400h-05FFh with the layout DOS and games expect
  (0500h/0501h flags, 0480h, 0458h, disk equipment bytes, keyboard buffer ...).
- Interrupt services: INT 18h (keyboard, text CRT, graphics GDC), INT 1Bh
  (floppy and hard disk; the core's `software/pc98_ide_read_bios.inc` already
  implements the ATA hard-disk part), INT 1Ch (timer/calendar), INT 1Ah
  (printer), INT 19h (RS-232C), INT 1Fh, IRQ handlers.
- Boot: the PC-98 IPL protocol (boot sector to 1FC0:0000, boot-device order,
  extension ROM scan at D0000h for the disk ROM).
- Fixed entry points some software calls directly; find them by tracing.
- Font: replace the NEC character generator with freely licensed 8x8/8x16 ANK
  and 16x16 JIS X 0208 bitmap fonts, converted to the FONT.ROM layout.

## Suggested method

1. Behavioural references (read, do not copy): the PC-9800 technical data
   books, DOSBox-X's PC-98 BIOS services, NP2kai `bios/`, MAME `pc9801.cpp`.
2. Differential testing, like the CPU fuzzer: run the real BIOS and the new one
   in `z486_boot_probe_tb`-style simulation with the same service calls and
   compare the work area and results. The existing boot probe needs a PIT model
   (it currently stalls at the BIOS timer-readback loop at EIP 99h).
3. Stages: MS-DOS boot from VHD with text and keyboard; floppy; graphics
   services and the remaining details; then games on hardware.
4. Ship `boot.rom` next to the RBF (release or downloader); the FPGA has no
   room for a 96 KiB+ internal ROM.
